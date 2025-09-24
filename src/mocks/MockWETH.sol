// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockWETH
 * @dev Mock Wrapped ETH contract for testing
 * Allows deposit/withdraw of ETH and acts as ERC20 token
 */
contract MockWETH is ERC20 {
    event Deposit(address indexed account, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);

    constructor() ERC20("Wrapped Ether", "WETH") { }

    /**
     * @dev Deposit ETH and mint WETH tokens
     */
    function deposit() external payable {
        require(msg.value > 0, "Must send ETH to deposit");
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev Withdraw ETH by burning WETH tokens
     */
    function withdraw(uint256 amount) external {
        require(balanceOf(msg.sender) >= amount, "Insufficient WETH balance");
        _burn(msg.sender, amount);

        (bool success,) = payable(msg.sender).call{ value: amount }("");
        require(success, "ETH transfer failed");

        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @dev Fallback function to allow direct ETH deposits
     */
    receive() external payable {
        require(msg.value > 0, "Must send ETH to deposit");
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev Allow contract to receive ETH
     */
    fallback() external payable {
        require(msg.value > 0, "Must send ETH to deposit");
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev Mint WETH tokens directly (for testing purposes)
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @dev Get contract's ETH balance
     */
    function getETHBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
