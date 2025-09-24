// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";

import { BaseScript } from "./base/BaseScript.sol";
import { TaxStrategyHook } from "../src/hooks/TaxStrategyHook.sol";

/// @notice Mines the address and deploys the TaxStrategyHook.sol Hook contract
contract DeployHookScript is BaseScript {
    function run() public {
        IPoolManager poolManager = IPoolManager((vm.envAddress("POOL_MANAGER")));
        address feeTreasuryAddr = vm.envAddress("FEE_TREASURY_ADDRESS");

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(poolManager, feeTreasuryAddr);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(TaxStrategyHook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.startBroadcast();
        TaxStrategyHook taxStrategyHook = new TaxStrategyHook{ salt: salt }(poolManager, feeTreasuryAddr);
        vm.stopBroadcast();

        require(address(taxStrategyHook) == hookAddress, "DeployHookScript: Hook Address Mismatch");
    }
}
