// SPDX-License-Identifier: UNLICENSED
// © 2026 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FeeSwapper V2 Test Harness (EPSILON)
 * @notice Live test version — sends AERO to owner instead of Splitter
 * @dev 
 * IDENTICAL routing/execution to production. Only differences:
 *   - swap()/swapSingle() send AERO to owner() instead of Splitter
 *   - No splitter dependency for swap functions
 *   - withdraw() added for owner to pull any token
 *   - sweepDust() has no epoch restriction
 *
 * FLOW:
 *   1. Send fee tokens to this contract (EOA transfer)
 *   2. Keeper/owner calls swap(tokens[]) with the token list
 *   3. For each token, calculates optimal route at swap time
 *   4. Phase 1: T → AERO (direct) or T → USDC/WETH (intermediate)
 *   5. Phase 2: Accumulated USDC/WETH → AERO
 *   6. All AERO sent to owner()
 *
 * ROUTE OPTIMIZATION:
 *   For each token T, scores three candidate routes:
 *     S1 = T_in_T/AERO × 1                                              (direct)
 *     S2 = T_in_T/USDC × USDC_in_USDC/AERO / (USDC_in_T/USDC + USDC_in_USDC/AERO)  (via USDC)
 *     S3 = T_in_T/WETH × WETH_in_WETH/AERO / (WETH_in_T/WETH + WETH_in_WETH/AERO)  (via WETH)
 *   Hop ratio detects second-leg bottlenecks. Tiebreak: Direct > USDC > WETH
 *
 * DUAL ROUTER:
 *   - Classic pools (volatile/stable): Aerodrome V2 Router
 *   - CL pools (concentrated liquidity): SlipStream Swap Router
 *   - Pool selection is automatic — deepest pool wins regardless of type
 *
 * PRICING:
 *   - Reserve-based constant-product estimate for amountOutMin
 *   - No TWAP dependency — works identically for Classic and CL pools
 *   - Slippage tolerance applied to reserve estimate
 *
 * DESIGN:
 *   - Zero storage for token tracking (calldata-driven)
 *   - No MSIG route management — routes computed dynamically
 *   - Bounded by calldata length (caller controls iteration)
 *
 * SECURITY:
 *   - Slippage protection via reserve-based estimate
 *   - Max 10 tokens per swap call
 *   - try/catch on all external swap calls (no revert on single failure)
 *   - sweepDust() restricted to last hour of epoch
 */

// ═══════════════════════════════════════════════════════════════════════════════
// INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

interface IPool {
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1, uint256 blockTimestampLast);
    function token0() external view returns (address);
}

interface ICLPool {
    function liquidity() external view returns (uint128);
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        bool unlocked
    );
    function token0() external view returns (address);
}

interface IPoolFactory {
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address);
}

interface ICLFactory {
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address);
}

// ISplitter not used in test harness

/// @dev Aerodrome V2 Router — handles Classic (volatile/stable) pool swaps
interface IAerodromeRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }
    
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

/// @dev SlipStream Swap Router — handles CL (concentrated liquidity) pool swaps
interface ICLSwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        int24 tickSpacing;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

// ═══════════════════════════════════════════════════════════════════════════════
// STRUCTS
// ═══════════════════════════════════════════════════════════════════════════════

struct PoolInfo {
    address pool;
    address factory;
    bool stable;       // Classic only (volatile=false, stable=true)
    bool isCL;
    int24 tickSpacing; // CL only
}

contract FeeSwapperV2TestHarness is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════
    
    uint256 public constant MAX_TOKENS_PER_SWAP = 10;
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 200;  // 2%
    uint256 public constant MAX_SLIPPAGE_BPS = 1000;     // 10%
    uint256 public constant MIN_SWAP_AMOUNT = 1e6;       // Dust threshold
    
    address public constant CL_FACTORY   = 0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A;
    address public constant CL_FACTORY_2 = 0xaDe65c38CD4849aDBA595a4323a8C7DdfE89716a;
    
    uint256 internal constant Q96 = 2 ** 96;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════════
    
    IAerodromeRouter public immutable ROUTER;        // Classic pool swaps
    ICLSwapRouter public immutable CL_ROUTER;        // CL pool swaps
    IPoolFactory public immutable FACTORY;
    IERC20 public immutable AERO;
    address public immutable USDC;
    address public immutable WETH;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // STATE (minimal)
    // ═══════════════════════════════════════════════════════════════════════════
    
    // No splitter in test harness — AERO goes to owner
    uint256 public slippageBps;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════
    
    event Swapped(address indexed token, uint256 amountIn, uint256 amountOut, address indexed via);
    event SlippageSet(uint256 bps);
    event SwapSkipped(address indexed token, uint256 balance, string reason);
    event AeroReturned(address indexed to, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════
    
    error ZeroAddress();
    error SlippageTooHigh();
    error TooManyTokens();
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════
    
    constructor(
        address _router,
        address _clRouter,
        address _factory,
        address _aero,
        address _usdc,
        address _weth
    ) Ownable(msg.sender) {
        if (_router == address(0) || _clRouter == address(0) || _factory == address(0) || 
            _aero == address(0) || _usdc == address(0) || _weth == address(0)) {   
            revert ZeroAddress();
        }
        
        ROUTER = IAerodromeRouter(_router);
        CL_ROUTER = ICLSwapRouter(_clRouter);
        FACTORY = IPoolFactory(_factory);
        AERO = IERC20(_aero);
        USDC = _usdc;
        WETH = _weth;
        slippageBps = DEFAULT_SLIPPAGE_BPS;
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CORE: SWAP
    // ═══════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Swap tokens to AERO using optimal routes, return to owner
     * @dev Caller provides token list (no storage iteration).
     *      Phase 1: Each token → optimal target (AERO direct, or USDC/WETH)
     *      Phase 2: Accumulated USDC/WETH → AERO
     *      Any AERO already held is included in the total.
     * @param tokens Tokens to swap (from EOA transfer)
     * @return totalAero Total AERO returned to owner
     */
    function swap(address[] calldata tokens) external nonReentrant returns (uint256 totalAero) {
        if (tokens.length > MAX_TOKENS_PER_SWAP) revert TooManyTokens();
        
        // Phase 1: Swap each token to optimal target
        uint256 len = tokens.length;
        for (uint256 i; i < len; ) {
            address token = tokens[i];
            
            // Skip AERO, USDC, WETH (intermediates handled in Phase 2)
            if (token != address(AERO) && token != USDC && token != WETH) {
                uint256 balance = IERC20(token).balanceOf(address(this));
                if (balance >= MIN_SWAP_AMOUNT) {
                    _swapTokenOptimal(token, balance);
                }
            }
            
            unchecked { ++i; }
        }
        
        // Phase 2: Convert accumulated USDC → AERO
        uint256 usdcBalance = IERC20(USDC).balanceOf(address(this));
        if (usdcBalance >= MIN_SWAP_AMOUNT) {
            _executeSwap(USDC, address(AERO), usdcBalance);
        }
        
        // Phase 2: Convert accumulated WETH → AERO
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        if (wethBalance >= MIN_SWAP_AMOUNT) {
            _executeSwap(WETH, address(AERO), wethBalance);
        }
        
        // Total AERO after all swaps
        totalAero = AERO.balanceOf(address(this));
        
        // Return all AERO to owner
        if (totalAero > 0) {
            AERO.safeTransfer(owner(), totalAero);
            emit AeroReturned(owner(), totalAero);
        }
    }
    
    /**
     * @notice Swap a single token using optimal route
     * @param token Token to swap
     * @return aeroOut AERO received
     */
    function swapSingle(address token) external nonReentrant returns (uint256 aeroOut) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        
        if (token == address(AERO)) {
            aeroOut = balance;
        } else if (balance >= MIN_SWAP_AMOUNT) {
            _swapTokenOptimal(token, balance);
            
            // Convert any intermediates produced
            uint256 usdcBal = IERC20(USDC).balanceOf(address(this));
            if (usdcBal >= MIN_SWAP_AMOUNT) {
                _executeSwap(USDC, address(AERO), usdcBal);
            }
            uint256 wethBal = IERC20(WETH).balanceOf(address(this));
            if (wethBal >= MIN_SWAP_AMOUNT) {
                _executeSwap(WETH, address(AERO), wethBal);
            }
            
            aeroOut = AERO.balanceOf(address(this));
        }
        
        if (aeroOut > 0) {
            AERO.safeTransfer(owner(), aeroOut);
            emit AeroReturned(owner(), aeroOut);
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL: ROUTE OPTIMIZATION
    // ═══════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Calculate optimal route and execute first leg
     * @dev Direct routes produce AERO immediately.
     *      USDC/WETH routes accumulate intermediates for Phase 2.
     * @param token Token to swap
     * @param amount Amount to swap
     */
    function _swapTokenOptimal(address token, uint256 amount) internal {
        (address intermediate, uint256 score) = _getOptimalRoute(token);
        
        if (score == 0) {
            emit SwapSkipped(token, amount, "no liquidity");
            return;
        }
        
        uint256 amountOut = _executeSwap(token, intermediate, amount);
        
        if (amountOut > 0) {
            emit Swapped(token, amount, amountOut, intermediate == address(AERO) ? address(0) : intermediate);
        }
    }
    
    /**
     * @notice Calculate optimal route for a token
     * @dev Scores each route using T depth × hop ratio:
     *
     *      S1 = T_in_T/AERO × 1                           (direct, no hop)
     *      S2 = T_in_T/USDC × USDC_in_USDC/AERO / (USDC_in_T/USDC + USDC_in_USDC/AERO)
     *      S3 = T_in_T/WETH × WETH_in_WETH/AERO / (WETH_in_T/WETH + WETH_in_WETH/AERO)
     *
     *      Hop ratio R is dimensionless (USDC/USDC or WETH/WETH).
     *      R approaches 1 when second leg is deep relative to first.
     *      R approaches 0 when second leg is a bottleneck.
     *      S is in T units, directly comparable across routes.
     *
     *      Tiebreak: Direct > USDC > WETH (fewer hops preferred)
     *
     * @param token Token to route
     * @return intermediate Best target (AERO for direct, USDC, or WETH)
     * @return score Best route score (0 if no route)
     */
    function _getOptimalRoute(address token) internal view returns (address intermediate, uint256 score) {
        // T depth in each candidate pool
        uint256 tInDirect = _getTokenReserve(token, address(AERO));
        uint256 tInUsdc = _getTokenReserve(token, USDC);
        uint256 tInWeth = _getTokenReserve(token, WETH);
        
        // S1: Direct (R1 = 1)
        uint256 s1 = tInDirect;
        
        // S2: Via USDC
        // R2 = USDC_in_USDC/AERO / (USDC_in_T/USDC + USDC_in_USDC/AERO)
        uint256 s2 = 0;
        if (tInUsdc > 0) {
            uint256 usdcInTokenPool = _getTokenReserve(USDC, token);
            uint256 usdcInAeroPool = _getTokenReserve(USDC, address(AERO));
            uint256 totalUsdc = usdcInTokenPool + usdcInAeroPool;
            if (totalUsdc > 0) {
                s2 = tInUsdc * usdcInAeroPool / totalUsdc;
            }
        }
        
        // S3: Via WETH
        // R3 = WETH_in_WETH/AERO / (WETH_in_T/WETH + WETH_in_WETH/AERO)
        uint256 s3 = 0;
        if (tInWeth > 0) {
            uint256 wethInTokenPool = _getTokenReserve(WETH, token);
            uint256 wethInAeroPool = _getTokenReserve(WETH, address(AERO));
            uint256 totalWeth = wethInTokenPool + wethInAeroPool;
            if (totalWeth > 0) {
                s3 = tInWeth * wethInAeroPool / totalWeth;
            }
        }
        
        // Select max with tiebreak priority: Direct > USDC > WETH
        if (s1 >= s2 && s1 >= s3 && s1 > 0) {
            return (address(AERO), s1);
        }
        if (s2 >= s3 && s2 > 0) {
            return (USDC, s2);
        }
        if (s3 > 0) {
            return (WETH, s3);
        }
        
        return (address(0), 0);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL: POOL DISCOVERY
    // ═══════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Find deepest pool for a token pair across Classic + CL factories
     * @dev Checks all 10 candidates (2 Classic + 4 CL ticks × 2 factories),
     *      returns the pool with highest active reserve for tokenA.
     *      Prevents shallow/dead pools from shadowing deep CL pools.
     * @param tokenA Token whose reserve depth determines best pool
     * @param tokenB The other token in the pair
     * @return best Pool with highest tokenA reserve (pool == address(0) if none)
     */
    function _findBestPool(address tokenA, address tokenB) internal view returns (PoolInfo memory best) {
        uint256 bestReserve;
        address pool;
        
        // Classic volatile
        pool = FACTORY.getPool(tokenA, tokenB, false);
        if (pool != address(0)) {
            PoolInfo memory info = PoolInfo(pool, address(FACTORY), false, false, int24(0));
            uint256 r = _getReserveForPool(info, tokenA);
            if (r > bestReserve) {
                bestReserve = r;
                best = info;
            }
        }
        
        // Classic stable
        pool = FACTORY.getPool(tokenA, tokenB, true);
        if (pool != address(0)) {
            PoolInfo memory info = PoolInfo(pool, address(FACTORY), true, false, int24(0));
            uint256 r = _getReserveForPool(info, tokenA);
            if (r > bestReserve) {
                bestReserve = r;
                best = info;
            }
        }
        
        // CL factories — try common tick spacings
        int24[4] memory ticks = [int24(1), int24(50), int24(100), int24(200)];
        address[2] memory clFactories = [CL_FACTORY, CL_FACTORY_2];
        
        for (uint256 f; f < 2; ) {
            for (uint256 i; i < 4; ) {
                pool = ICLFactory(clFactories[f]).getPool(tokenA, tokenB, ticks[i]);
                if (pool != address(0)) {
                    PoolInfo memory info = PoolInfo(pool, clFactories[f], false, true, ticks[i]);
                    uint256 r = _getReserveForPool(info, tokenA);
                    if (r > bestReserve) {
                        bestReserve = r;
                        best = info;
                    }
                }
                unchecked { ++i; }
            }
            unchecked { ++f; }
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL: RESERVE CALCULATION
    // ═══════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Get tokenA's active reserve in a known pool
     * @dev Classic pools: getReserves() returns full reserves
     *      CL pools: active reserve at current tick via L and sqrtPriceX96
     *        x = L * 2^96 / sqrtPriceX96  (tokenA is token0)
     *        y = (L >> 48) * (sqrtPriceX96 >> 48)  (tokenA is token1, overflow-safe)
     * @param info Pool metadata from factory lookup
     * @param tokenA Token whose reserve we want
     * @return reserve TokenA's active reserve in the pool
     */
    function _getReserveForPool(PoolInfo memory info, address tokenA) internal view returns (uint256) {
        if (!info.isCL) {
            // Classic pool — getReserves
            try IPool(info.pool).getReserves() returns (uint256 r0, uint256 r1, uint256) {
                address token0 = IPool(info.pool).token0();
                return token0 == tokenA ? r0 : r1;
            } catch {
                return 0;
            }
        } else {
            // CL pool — x = L / sqrt(p), y = L * sqrt(p)
            try ICLPool(info.pool).liquidity() returns (uint128 L) {
                if (L == 0) return 0;
                
                (uint160 sqrtPriceX96,,,,, ) = ICLPool(info.pool).slot0();
                if (sqrtPriceX96 == 0) return 0;
                
                address token0 = ICLPool(info.pool).token0();
                if (tokenA == token0) {
                    // x = L * 2^96 / sqrtPriceX96
                    // Safe: L(128) + Q96(96) = 224 bits max
                    return uint256(L) * Q96 / uint256(sqrtPriceX96);
                } else {
                    // y = L * sqrtPriceX96 / 2^96
                    // L(128) * sqrtPriceX96(160) = 288 bits — overflows uint256
                    // Bitshift each down 48: (L >> 48) * (sqrtPriceX96 >> 48)
                    // = L * sqrtPriceX96 / 2^96 — exact same division, no overflow
                    return (uint256(L) >> 48) * (uint256(sqrtPriceX96) >> 48);
                }
            } catch {
                return 0;
            }
        }
    }
    
    /**
     * @notice Get token's active reserve in the deepest pool with another token
     * @param tokenA Token whose reserve we want
     * @param tokenB The other token in the pair
     * @return TokenA's active reserve in the best pool
     */
    function _getTokenReserve(address tokenA, address tokenB) internal view returns (uint256) {
        PoolInfo memory info = _findBestPool(tokenA, tokenB);
        if (info.pool == address(0)) return 0;
        return _getReserveForPool(info, tokenA);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL: SWAP EXECUTION
    // ═══════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Execute a single-hop swap with reserve-based slippage protection
     * @dev Finds best pool (Classic or CL), estimates output via constant-product
     *      reserve math, executes with slippage tolerance.
     *      Classic pools → Aerodrome V2 Router (swapExactTokensForTokens)
     *      CL pools → SlipStream Router (exactInputSingle)
     *      Never reverts — emits SwapSkipped on failure.
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Amount to swap
     * @return amountOut Output amount (0 on failure)
     */
    function _executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        PoolInfo memory info = _findBestPool(tokenIn, tokenOut);
        if (info.pool == address(0)) {
            emit SwapSkipped(tokenIn, amountIn, "no pool");
            return 0;
        }
        
        // Reserve-based estimate for amountOutMin
        // expectedOut = amountIn * reserveOut / (reserveIn + amountIn)
        uint256 reserveIn = _getReserveForPool(info, tokenIn);
        uint256 reserveOut = _getReserveForPool(info, tokenOut);
        
        if (reserveIn == 0 || reserveOut == 0) {
            emit SwapSkipped(tokenIn, amountIn, "zero reserves");
            return 0;
        }
        
        uint256 expectedOut = amountIn * reserveOut / (reserveIn + amountIn);
        if (expectedOut == 0) {
            emit SwapSkipped(tokenIn, amountIn, "dust output");
            return 0;
        }
        
        uint256 minOut = (expectedOut * (10000 - slippageBps)) / 10000;
        
        if (!info.isCL) {
            // ─── Classic pool → V2 Router ───
            IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
            routes[0] = IAerodromeRouter.Route({
                from: tokenIn,
                to: tokenOut,
                stable: info.stable,
                factory: info.factory
            });
            
            IERC20(tokenIn).forceApprove(address(ROUTER), amountIn);
            
            try ROUTER.swapExactTokensForTokens(
                amountIn,
                minOut,
                routes,
                address(this),
                block.timestamp
            ) returns (uint256[] memory amounts) {
                amountOut = amounts[amounts.length - 1];
            } catch {
                emit SwapSkipped(tokenIn, amountIn, "classic swap failed");
                return 0;
            }
        } else {
            // ─── CL pool → SlipStream Router ───
            IERC20(tokenIn).forceApprove(address(CL_ROUTER), amountIn);
            
            try CL_ROUTER.exactInputSingle(
                ICLSwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    tickSpacing: info.tickSpacing,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: minOut,
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256 out) {
                amountOut = out;
            } catch {
                emit SwapSkipped(tokenIn, amountIn, "cl swap failed");
                return 0;
            }
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════════
    
    function setSlippage(uint256 _slippageBps) external onlyOwner {
        if (_slippageBps > MAX_SLIPPAGE_BPS) revert SlippageTooHigh();
        slippageBps = _slippageBps;
        emit SlippageSet(_slippageBps);
    }
    
    /**
     * @notice Withdraw any token from the contract
     * @param token Token to withdraw
     * @param to Recipient
     */
    function withdraw(address token, address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(to, balance);
            emit Withdrawn(token, to, balance);
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Get optimal route for a token
     * @param token Token to check
     * @return intermediate Best route target (AERO, USDC, or WETH)
     * @return score Route score
     */
    function getOptimalRoute(address token) external view returns (address intermediate, uint256 score) {
        return _getOptimalRoute(token);
    }
    
    /**
     * @notice Preview swap output for a token (full path including second leg)
     * @dev Uses reserve-based constant-product estimate
     * @param token Token to swap
     * @param amount Amount to swap
     * @return aeroOut Expected AERO output
     * @return via Route intermediate (address(0) for direct)
     */
    function previewSwap(address token, uint256 amount) external view returns (uint256 aeroOut, address via) {
        (address intermediate, uint256 score) = _getOptimalRoute(token);
        if (score == 0) return (0, address(0));
        
        if (intermediate == address(AERO)) {
            aeroOut = _estimateOutput(token, address(AERO), amount);
            via = address(0);
        } else {
            uint256 intermediateOut = _estimateOutput(token, intermediate, amount);
            if (intermediateOut > 0) {
                aeroOut = _estimateOutput(intermediate, address(AERO), intermediateOut);
            }
            via = intermediate;
        }
    }
    
    /**
     * @notice Estimate swap output using reserve-based constant-product math
     * @dev expectedOut = amountIn * reserveOut / (reserveIn + amountIn)
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Amount to swap
     * @return expectedOut Estimated output (0 if no pool or zero reserves)
     */
    function _estimateOutput(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256) {
        PoolInfo memory info = _findBestPool(tokenIn, tokenOut);
        if (info.pool == address(0)) return 0;
        
        uint256 reserveIn = _getReserveForPool(info, tokenIn);
        uint256 reserveOut = _getReserveForPool(info, tokenOut);
        
        if (reserveIn == 0 || reserveOut == 0) return 0;
        
        return amountIn * reserveOut / (reserveIn + amountIn);
    }
    
    /**
     * @notice Get pool info for a token pair (for diagnostics)
     * @param tokenA First token
     * @param tokenB Second token
     * @return info Best pool metadata
     * @return reserveA TokenA's active reserve
     * @return reserveB TokenB's active reserve
     */
    function getPoolInfo(address tokenA, address tokenB) external view returns (
        PoolInfo memory info,
        uint256 reserveA,
        uint256 reserveB
    ) {
        info = _findBestPool(tokenA, tokenB);
        if (info.pool != address(0)) {
            reserveA = _getReserveForPool(info, tokenA);
            reserveB = _getReserveForPool(info, tokenB);
        }
    }
}
