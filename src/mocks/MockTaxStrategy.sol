// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

interface ITaxStrategy {
    function addFees() external payable;
}

/**
 * @title MockTaxStrategy
 * @dev Mock implementation for testing purposes
 */
contract MockTaxStrategy is Ownable, ITaxStrategy {
    bool public midSwap;

    constructor() Ownable(msg.sender) {
        midSwap = false;
    }

    function addFees() external payable override {
        // Accept ETH fees for testing
    }
}
