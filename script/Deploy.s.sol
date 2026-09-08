// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { SecureVault } from "../src/SecureVault.sol";

contract Deploy is Script {
    function run(address asset, uint256 cap) external returns (SecureVault vault) {
        vm.startBroadcast();
        vault = new SecureVault(asset, cap, msg.sender);
        vm.stopBroadcast();
    }
}
