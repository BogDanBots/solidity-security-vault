// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVault {
    event Deposited(
        address indexed caller, address indexed receiver, uint256 assets, uint256 shares
    );
    event Withdrawn(
        address indexed caller, address indexed receiver, uint256 assets, uint256 shares
    );
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function asset() external view returns (address);
    function depositCap() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function totalShares() external view returns (uint256);
    function sharesOf(address account) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256 shares);
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
    function deposit(uint256 assets, address receiver, uint256 minShares)
        external
        returns (uint256 shares);
    function withdraw(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver) external returns (uint256 assets);
}
