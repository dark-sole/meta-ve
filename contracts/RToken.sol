// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RToken (R-AERO) V.BETA.1
 * @notice Liquidation receipt token - represents claim on underlying veAERO
 */
contract RToken is ERC20, Ownable {
    
    // ═══════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════
    
    address public splitter;
    
    // ═══════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════
    
    event SplitterSet(address indexed splitter);
    
    // ═══════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════
    
    error OnlySplitter();
    error SplitterAlreadySet();
    error ZeroAddress();
    
    // ═══════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════
    
    constructor() ERC20("Receipt AERO", "R-AERO") Ownable(msg.sender) {}
    
    // ═══════════════════════════════════════════════════════════════
    // DECIMALS OVERRIDE - 18 DECIMALS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Returns 18 decimals (consistent with V-AERO and C-AERO)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Set the splitter contract (one-time)
     * @param _splitter Address of VeAeroSplitter
     */
    function setSplitter(address _splitter) external onlyOwner {
        if (_splitter == address(0)) revert ZeroAddress();
        if (splitter != address(0)) revert SplitterAlreadySet();
        splitter = _splitter;
        emit SplitterSet(_splitter);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // SPLITTER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    modifier onlySplitter() {
        if (msg.sender != splitter) revert OnlySplitter();
        _;
    }
    
    /**
     * @notice Mint R-AERO tokens (only callable by splitter during liquidation)
     * @param to Recipient address
     * @param amount Amount to mint (18 decimals)
     */
    function mint(address to, uint256 amount) external onlySplitter {
        _mint(to, amount);
    }
}
