// SPDX-License-Identifier: UNLICENSED
// © 2026 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FeeSwapper v.DELTA
 * @notice Swaps fee tokens to AERO via MSIG-configured routes
 * @dev 
 * FLOW:
 *   1. Splitter.collectFees() pushes all tokens here
 *   2. Anyone calls swap()
 *   3. FeeSwapper swaps non-AERO via Router using configured routes
 *   4. All AERO returned to Splitter
 *
 * ROUTE CONFIG:
 *   - MSIG sets route per token via setRoute()
 *   - Routes can be single-hop (USDC → AERO) or multi-hop (TOKEN → WETH → AERO)
 *   - Unmapped tokens cannot be swapped (skip)
 *   - Can be replaced later with automated optimizer
 *
 * SECURITY:
 *   - Only enabled tokens can swap
 *   - Slippage protection via TWAP quote
 *   - Max 10 tokens per swap call
 */

interface IPool {
    function quote(address tokenIn, uint256 amountIn, uint256 granularity) external view returns (uint256);
}

interface IPoolFactory {
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address);
}

interface ICLFactory {
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address);
}

interface ISplitter {
    function processSwappedFees(uint256 amount) external;
    function epochEndTime() external view returns (uint256);
}

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

contract FeeSwapper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════
    
    address public constant CL_FACTORY = 0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A;
    address public constant CL_FACTORY_2 = 0xaDe65c38CD4849aDBA595a4323a8C7DdfE89716a;

    uint256 public constant MAX_TOKENS_PER_SWAP = 10;
    uint256 public constant TWAP_GRANULARITY = 4;        // ~2hr TWAP
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 200;  // 2%
    uint256 public constant MAX_SLIPPAGE_BPS = 1000;     // 10%
    uint256 public constant MIN_SWAP_AMOUNT = 1e6;       // Dust threshold
    
    // ═══════════════════════════════════════════════════════════════════════
    // IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════
    
    IAerodromeRouter public immutable ROUTER;
    IERC20 public immutable AERO;
    
    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════
    
    address public splitter;
    uint256 public slippageBps;
    
    // Token config
    mapping(address => bool) public tokenEnabled;
    mapping(address => IAerodromeRouter.Route[]) internal _tokenRoutes;
    address[] public enabledTokens;  // For enumeration
    uint256 public swapStartIndex;   // Rotation index for fair processing


    
    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════
    
    event Swapped(address indexed token, uint256 amountIn, uint256 aeroOut);
    event RouteSet(address indexed token, uint256 hops);
    event TokenDisabled(address indexed token);
    event SlippageSet(uint256 bps);
    event SplitterSet(address indexed splitter);
    event SwapSkipped(address indexed token, uint256 balance, string reason);
    event AeroReturned(address indexed to, uint256 amount);
    event DustSwept(address indexed token, address indexed to, uint256 amount);
    
    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════
    
    error ZeroAddress();
    error InvalidRoute();
    error SlippageTooHigh();
    error NoSplitter();
    error TokenNotEnabled();
    error SweepWindowClosed();
    
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════
    
    constructor(
        address _router,
        address _aero
    ) Ownable(msg.sender) {
        if (_router == address(0) || _aero == address(0)) {   
             revert ZeroAddress();
        }
        
        ROUTER = IAerodromeRouter(_router);
        AERO = IERC20(_aero);
        slippageBps = DEFAULT_SLIPPAGE_BPS;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // CORE: SWAP
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
    * @notice Swap all enabled tokens to AERO and return to Splitter
    * @dev Anyone can call. Processes up to MAX_TOKENS_PER_SWAP.
    *      Uses rotation to ensure fair processing when >10 tokens.
    * @return totalAero Total AERO returned to Splitter
    */
    function swap() external nonReentrant returns (uint256 totalAero) {
        if (splitter == address(0)) revert NoSplitter();
        
        uint256 len = enabledTokens.length;
        uint256 processed = 0;
        
        // First, count AERO balance (no swap needed)
        uint256 aeroBalance = AERO.balanceOf(address(this));
        totalAero = aeroBalance;
        
        // Start from rotated index
        uint256 startIdx = swapStartIndex;
        
        // Swap other tokens
        for (uint256 i = 0; i < len && processed < MAX_TOKENS_PER_SWAP; ) {
            uint256 idx = (startIdx + i) % len;
            address token = enabledTokens[idx];
            
            // Skip AERO
            if (token == address(AERO)) {
                unchecked { ++i; }
                continue;
            }
            
            uint256 balance = IERC20(token).balanceOf(address(this));
            
            if (balance >= MIN_SWAP_AMOUNT && tokenEnabled[token]) {
                uint256 aeroOut = _swapToken(token, balance);
                if (aeroOut > 0) {
                    totalAero += aeroOut;
                    processed++;
                }
            }
            
            unchecked { ++i; }
        }
        
        // Rotate start index for next call
        if (len > 0) {
            swapStartIndex = (startIdx + 1) % len;
        }
        
        // Return all AERO to Splitter
        if (totalAero > 0) {
            AERO.safeTransfer(splitter, totalAero);
            ISplitter(splitter).processSwappedFees(totalAero);
            emit AeroReturned(splitter, totalAero);
        }
    }
        
    /**
     * @notice Swap a single token (for testing/manual operation)
     * @param token Token to swap
     * @return aeroOut AERO received
     */
    function swapSingle(address token) external nonReentrant returns (uint256 aeroOut) {
        if (splitter == address(0)) revert NoSplitter();
        if (!tokenEnabled[token]) revert TokenNotEnabled();
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        
        if (token == address(AERO)) {
            aeroOut = balance;
        } else if (balance >= MIN_SWAP_AMOUNT) {
            aeroOut = _swapToken(token, balance);
        }
        
        if (aeroOut > 0) {
            AERO.safeTransfer(splitter, aeroOut);
            ISplitter(splitter).processSwappedFees(aeroOut);
            emit AeroReturned(splitter, aeroOut);
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════
    
    function _swapToken(address token, uint256 amount) internal returns (uint256 aeroOut) {
        IAerodromeRouter.Route[] storage routes = _tokenRoutes[token];
        
        if (routes.length == 0) {
            emit SwapSkipped(token, amount, "no route");
            return 0;
        }
        
        // Get expected output via TWAP on first hop pool
        uint256 expectedOut = _getExpectedOut(token, amount, routes);
        if (expectedOut == 0) {
            emit SwapSkipped(token, amount, "zero quote");
            return 0;
        }
        
        // Apply slippage
        uint256 minOut = (expectedOut * (10000 - slippageBps)) / 10000;
        
        // Build calldata routes array
        IAerodromeRouter.Route[] memory routesMemory = new IAerodromeRouter.Route[](routes.length);
        for (uint256 i = 0; i < routes.length; ) {
            routesMemory[i] = routes[i];
            unchecked { ++i; }
        }
        
        // Approve and swap
        IERC20(token).forceApprove(address(ROUTER), amount);
        
        try ROUTER.swapExactTokensForTokens(
            amount,
            minOut,
            routesMemory,
            address(this),
            block.timestamp
        ) returns (uint256[] memory amounts) {
            aeroOut = amounts[amounts.length - 1];
            emit Swapped(token, amount, aeroOut);
        } catch {
            emit SwapSkipped(token, amount, "swap failed");
            return 0;
        }
    }
    
    function _getExpectedOut(
        address token,
        uint256 amount,
        IAerodromeRouter.Route[] storage routes
    ) internal view returns (uint256) {
        // For single-hop, use pool TWAP directly
        if (routes.length == 1) {
            address pool = _getPoolForRoute(routes[0]);
            if (pool == address(0)) return 0;
            
            try IPool(pool).quote(token, amount, TWAP_GRANULARITY) returns (uint256 out) {
                return out;
            } catch {
                return 0;
            }
        }
        
        // For multi-hop, chain the quotes
        uint256 currentAmount = amount;
        for (uint256 i = 0; i < routes.length; ) {
            address pool = _getPoolForRoute(routes[i]);
            if (pool == address(0)) return 0;
            
            try IPool(pool).quote(routes[i].from, currentAmount, TWAP_GRANULARITY) returns (uint256 out) {
                currentAmount = out;
            } catch {
                return 0;
            }
            
            unchecked { ++i; }
        }
        
        return currentAmount;
    }

    function _getPoolForRoute(IAerodromeRouter.Route memory route) internal view returns (address pool) {
         if (route.factory == CL_FACTORY || route.factory == CL_FACTORY_2) {
            // Try common tick spacings for CL pools
            int24[4] memory tickSpacings = [int24(1), int24(50), int24(100), int24(200)];
            for (uint256 j = 0; j < 4; ) {
                pool = ICLFactory(route.factory).getPool(route.from, route.to, tickSpacings[j]);
                if (pool != address(0)) return pool;
                unchecked { ++j; }
            }
            return address(0);
        } else {
            return IPoolFactory(route.factory).getPool(route.from, route.to, route.stable);
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // VIEW
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Get route for a token
     */
    function getRoute(address token) external view returns (IAerodromeRouter.Route[] memory) {
        return _tokenRoutes[token];
    }
    
    /**
     * @notice Preview swap output for a token
     */
    function previewSwap(address token, uint256 amount) external view returns (uint256 expectedOut, uint256 minOut) {
        if (!tokenEnabled[token] || amount < MIN_SWAP_AMOUNT) return (0, 0);
        
        IAerodromeRouter.Route[] storage routes = _tokenRoutes[token];
        if (routes.length == 0) return (0, 0);
        
        expectedOut = _getExpectedOut(token, amount, routes);
        minOut = (expectedOut * (10000 - slippageBps)) / 10000;
    }
    
    /**
     * @notice Get all pending balances
     */
    function getPendingBalances() external view returns (
        address[] memory tokens,
        uint256[] memory balances,
        uint256[] memory expectedOuts
    ) {
        uint256 len = enabledTokens.length;
        tokens = new address[](len);
        balances = new uint256[](len);
        expectedOuts = new uint256[](len);
        
        for (uint256 i = 0; i < len; ) {
            address token = enabledTokens[i];
            tokens[i] = token;
            balances[i] = IERC20(token).balanceOf(address(this));
            
            if (token == address(AERO)) {
                expectedOuts[i] = balances[i];
            } else if (balances[i] >= MIN_SWAP_AMOUNT && _tokenRoutes[token].length > 0) {
                expectedOuts[i] = _getExpectedOut(token, balances[i], _tokenRoutes[token]);
            }
            
            unchecked { ++i; }
        }
    }
    
    /**
     * @notice Get enabled token count
     */
    function enabledTokenCount() external view returns (uint256) {
        return enabledTokens.length;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN: ROUTES
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Set swap route for a token
     * @dev Route must end in AERO. First hop must start with token.
     * @param token Token to configure
     * @param routes Route array (can be multi-hop)
     */
    function setRoute(
        address token,
        IAerodromeRouter.Route[] calldata routes
    ) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (routes.length == 0) revert InvalidRoute();
        if (routes[0].from != token) revert InvalidRoute();
        if (routes[routes.length - 1].to != address(AERO)) revert InvalidRoute();
        if (token == address(AERO)) revert InvalidRoute();  // AERO doesn't need route
        
        // Validate each hop has a pool
        for (uint256 i = 0; i < routes.length; ) {
            address pool = _getPoolForRoute(routes[i]);
            if (pool == address(0)) revert InvalidRoute();
            
            // Validate route continuity
            if (i > 0 && routes[i].from != routes[i - 1].to) revert InvalidRoute();
            
            unchecked { ++i; }
        }
        
        // Clear existing route
        delete _tokenRoutes[token];
        
        // Store new route
        for (uint256 i = 0; i < routes.length; ) {
            _tokenRoutes[token].push(routes[i]);
            unchecked { ++i; }
        }
        
        // Enable token if not already
        if (!tokenEnabled[token]) {
            tokenEnabled[token] = true;
            enabledTokens.push(token);
        }
        
        emit RouteSet(token, routes.length);
    }
    
    /**
     * @notice Disable a token (keeps route for re-enable)
     */
    function disableToken(address token) external onlyOwner {
        tokenEnabled[token] = false;
        emit TokenDisabled(token);
    }
    
    /**
     * @notice Re-enable a previously configured token
     */
    function enableToken(address token) external onlyOwner {
        if (_tokenRoutes[token].length == 0) revert InvalidRoute();
        tokenEnabled[token] = true;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN: CONFIG
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Set Splitter address
     */
    function setSplitter(address _splitter) external onlyOwner {
        if (_splitter == address(0)) revert ZeroAddress();
        splitter = _splitter;
        emit SplitterSet(_splitter);
    }
    
    /**
     * @notice Set slippage tolerance
     */
    function setSlippage(uint256 _slippageBps) external onlyOwner {
        if (_slippageBps > MAX_SLIPPAGE_BPS) revert SlippageTooHigh();
        slippageBps = _slippageBps;
        emit SlippageSet(_slippageBps);
    }
    /**
        * @notice Sweep dust or stuck tokens to treasury
        * @dev Only owner (MSIG). Only in last hour of epoch.
        *      Only sweeps tokens that cannot be swapped:
        *      - No route configured, OR
        *      - Token disabled, OR  
        *      - Balance below MIN_SWAP_AMOUNT
        * @param tokens Array of token addresses to sweep
        * @param to Recipient (address(0) defaults to owner)
        */
    function sweepDust(address[] calldata tokens, address to) external onlyOwner {
        // Only in last hour of epoch
        uint256 epochEnd = ISplitter(splitter).epochEndTime();
        if (block.timestamp < epochEnd - 1 hours) revert SweepWindowClosed();
        if (block.timestamp >= epochEnd) revert SweepWindowClosed();
        
        address recipient = to == address(0) ? owner() : to;
        
        for (uint256 i = 0; i < tokens.length; ) {
            address token = tokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
                
            // Never sweep AERO - use swap() instead
            if (token == address(AERO))  {
                unchecked { ++i; }
                continue;
            }
            
            if (balance > 0) {
                bool noRoute = _tokenRoutes[token].length == 0;
                bool disabled = !tokenEnabled[token];
                bool belowMin = balance < MIN_SWAP_AMOUNT;
                
                // Sweep if: no route OR disabled OR below minimum
                if (noRoute || disabled || belowMin) {
                    IERC20(token).safeTransfer(recipient, balance);
                    emit DustSwept(token, recipient, balance);
                }
            }
            
            unchecked { ++i; }
        }
    }
}
