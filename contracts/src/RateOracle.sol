// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRateOracle} from "./interfaces/IRateOracle.sol";
import {CIP} from "./libraries/CIP.sol";
import {WadMath} from "./libraries/WadMath.sol";

/// @title RateOracle
/// @notice Price and rate truth for the book. Three defences, because a margin
///         engine is only ever as safe as its mark:
///
///         1. **Medianised multi-source spot** — App Kit Swap mid and an ECB
///            reference feed report independently; the mark is their median.
///         2. **Disagreement guard** — if sources spread beyond
///            `maxSourceSpreadBps` the oracle reports unhealthy and the engine
///            stops opening and liquidating rather than trusting either print.
///         3. **Circuit breaker** — a median that jumps more than `maxMoveBps`
///            in one update is rejected outright and trips the breaker for a
///            guardian to clear. Real gaps get walked in; garbage prints don't.
contract RateOracle is IRateOracle, Ownable {
    using WadMath for uint256;

    struct Report {
        uint256 price;
        uint64 timestamp;
    }

    error NotSource();
    error NotRatesKeeper();
    error OracleUnhealthy();
    error NoSettlementYet();
    error AlreadySettled();
    error BadPrice();

    address[] public sources;
    mapping(address => bool) public isSource;
    mapping(address => Report) public reports;

    address public ratesKeeper;

    uint256 public maxAge = 1 hours;
    uint256 public maxSourceSpreadBps = 100; // 1% disagreement between feeds
    uint256 public maxMoveBps = 500; // 5% single-update move trips the breaker
    uint256 public minSources = 1;

    uint256 public lastMedian;
    uint64 public lastMedianAt;
    bool public breakerTripped;

    uint256 public rUsd; // SOFR, annualised WAD
    uint256 public rEur; // €STR, annualised WAD
    uint64 public fixingsAt;

    mapping(uint256 => uint256) public settlementPrice;

    event SpotPosted(address indexed source, uint256 price, uint256 median);
    event FixingsPosted(uint256 rUsd, uint256 rEur);
    event CircuitBreakerTripped(uint256 attempted, uint256 last, uint256 deviationBps);
    event CircuitBreakerReset(uint256 newMedian);
    event SettlementRecorded(uint256 indexed expiry, uint256 price);
    event SourceSet(address indexed source, bool enabled);

    modifier onlySource() {
        if (!isSource[msg.sender]) revert NotSource();
        _;
    }

    constructor(address owner_, address ratesKeeper_) Ownable(owner_) {
        ratesKeeper = ratesKeeper_;
    }

    // ─────────────────────────────── reporting ───────────────────────────────

    function postSpot(uint256 price) external onlySource {
        if (price == 0) revert BadPrice();
        reports[msg.sender] = Report({price: price, timestamp: uint64(block.timestamp)});

        (uint256 med, uint256 spreadBps, uint256 live) = _median();
        if (live < minSources) return;
        if (spreadBps > maxSourceSpreadBps) return; // stale-mark until feeds reconverge

        if (lastMedian != 0) {
            uint256 dev = med.deviationBps(lastMedian);
            if (dev > maxMoveBps) {
                breakerTripped = true;
                emit CircuitBreakerTripped(med, lastMedian, dev);
                return;
            }
        }
        lastMedian = med;
        lastMedianAt = uint64(block.timestamp);
        emit SpotPosted(msg.sender, price, med);
    }

    /// @notice Post the published SOFR / €STR fixings that anchor the CIP curve.
    function postFixings(uint256 rUsd_, uint256 rEur_) external {
        if (msg.sender != ratesKeeper && msg.sender != owner()) revert NotRatesKeeper();
        rUsd = rUsd_;
        rEur = rEur_;
        fixingsAt = uint64(block.timestamp);
        emit FixingsPosted(rUsd_, rEur_);
    }

    /// @notice Freeze the fixing a listed expiry cash-settles against.
    function recordSettlement(uint256 expiry) external returns (uint256 price) {
        if (block.timestamp < expiry) revert NoSettlementYet();
        if (settlementPrice[expiry] != 0) revert AlreadySettled();
        price = spot();
        settlementPrice[expiry] = price;
        emit SettlementRecorded(expiry, price);
    }

    // ──────────────────────────────── reads ──────────────────────────────────

    function spot() public view returns (uint256) {
        if (!healthy()) revert OracleUnhealthy();
        return lastMedian;
    }

    function fixings() external view returns (uint256, uint256) {
        return (rUsd, rEur);
    }

    function forwardRate(uint256 expiry) external view returns (uint256) {
        uint256 s = spot();
        if (expiry <= block.timestamp) return s;
        return CIP.forward(s, rUsd, rEur, CIP.yearFraction(block.timestamp, expiry));
    }

    function healthy() public view returns (bool) {
        if (breakerTripped) return false;
        if (lastMedian == 0 || fixingsAt == 0) return false;
        if (block.timestamp > lastMedianAt + maxAge) return false;
        if (block.timestamp > fixingsAt + 7 days) return false; // fixings publish daily
        (, uint256 spreadBps, uint256 live) = _median();
        if (live < minSources) return false;
        return spreadBps <= maxSourceSpreadBps;
    }

    function sourceCount() external view returns (uint256) {
        return sources.length;
    }

    /// @return med median of live reports
    /// @return spreadBps spread between the highest and lowest live report, bps of median
    /// @return live number of unexpired reports
    function _median() internal view returns (uint256 med, uint256 spreadBps, uint256 live) {
        uint256 n = sources.length;
        uint256[] memory vals = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            Report memory r = reports[sources[i]];
            if (r.price != 0 && block.timestamp <= r.timestamp + maxAge) {
                vals[live++] = r.price;
            }
        }
        if (live == 0) return (0, type(uint256).max, 0);

        // insertion sort — `live` is single digit by construction
        for (uint256 i = 1; i < live; ++i) {
            uint256 key = vals[i];
            uint256 j = i;
            while (j > 0 && vals[j - 1] > key) {
                vals[j] = vals[j - 1];
                --j;
            }
            vals[j] = key;
        }
        med = live % 2 == 1 ? vals[live / 2] : (vals[live / 2 - 1] + vals[live / 2]) / 2;
        spreadBps = med == 0 ? type(uint256).max : ((vals[live - 1] - vals[0]) * 10_000) / med;
    }

    // ──────────────────────────────── admin ──────────────────────────────────

    function setSource(address source, bool enabled) external onlyOwner {
        if (enabled && !isSource[source]) sources.push(source);
        if (!enabled && isSource[source]) {
            uint256 n = sources.length;
            for (uint256 i; i < n; ++i) {
                if (sources[i] == source) {
                    sources[i] = sources[n - 1];
                    sources.pop();
                    break;
                }
            }
            delete reports[source];
        }
        isSource[source] = enabled;
        emit SourceSet(source, enabled);
    }

    function setRatesKeeper(address keeper) external onlyOwner {
        ratesKeeper = keeper;
    }

    function setGuards(uint256 maxAge_, uint256 maxSourceSpreadBps_, uint256 maxMoveBps_, uint256 minSources_)
        external
        onlyOwner
    {
        maxAge = maxAge_;
        maxSourceSpreadBps = maxSourceSpreadBps_;
        maxMoveBps = maxMoveBps_;
        minSources = minSources_;
    }

    /// @notice Clear the breaker and re-anchor the mark after human review.
    function resetBreaker(uint256 newMedian) external onlyOwner {
        breakerTripped = false;
        if (newMedian != 0) {
            lastMedian = newMedian;
            lastMedianAt = uint64(block.timestamp);
        }
        emit CircuitBreakerReset(lastMedian);
    }
}
