// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IVault } from "./interfaces/IVault.sol";
import { IERC20Minimal } from "./interfaces/IERC20Minimal.sol";

/// @title SecureVault
/// @notice A compact, single-asset vault with non-transferable internal shares.
/// @dev This is intentionally not an ERC-4626 implementation. Keeping shares
///      non-transferable makes the ownership and accounting surface reviewable.
contract SecureVault is IVault {
    error ZeroAddress();
    error ZeroAmount();
    error ZeroShares();
    error ZeroMinShares();
    error ZeroAssetsOut();
    error SlippageExceeded();
    error DepositCapExceeded();
    error InsufficientShares();
    error InsufficientAssets();
    error Insolvent();
    error PausedError();
    error NotOwner();
    error NotPendingOwner();
    error AssetRecoveryForbidden();
    error TransferFailed();
    error Reentrancy();

    address public immutable override asset;
    uint256 public immutable override depositCap;

    address public owner;
    address public pendingOwner;
    bool public paused;

    uint256 public override totalShares;
    mapping(address account => uint256 shares) public override sharesOf;
    /// @dev Assets accepted by the vault and represented by internal shares.
    uint256 public managedAssets;

    uint256 private _entered;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert PausedError();
        _;
    }

    modifier nonReentrant() {
        if (_entered == 1) revert Reentrancy();
        _entered = 1;
        _;
        _entered = 0;
    }

    constructor(address asset_, uint256 depositCap_, address owner_) {
        if (asset_ == address(0) || owner_ == address(0)) revert ZeroAddress();
        asset = asset_;
        depositCap = depositCap_;
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    function totalAssets() public view override returns (uint256) {
        return managedAssets;
    }

    /// @notice Raw ERC-20 balance, including direct transfers not represented by shares.
    function rawAssetBalance() public view returns (uint256) {
        return IERC20Minimal(asset).balanceOf(address(this));
    }

    /// @notice Assets sent directly to the vault and intentionally excluded from pricing.
    function unaccountedAssets() public view returns (uint256) {
        uint256 rawBalance = rawAssetBalance();
        return rawBalance > managedAssets ? rawBalance - managedAssets : 0;
    }

    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        if (assets == 0) return 0;
        uint256 currentAssets = totalAssets();
        if (totalShares == 0) return assets;
        if (currentAssets == 0) revert Insolvent();
        return (assets * totalShares) / currentAssets;
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        if (assets == 0) return 0;
        uint256 currentAssets = totalAssets();
        if (currentAssets == 0 || totalShares == 0) revert Insolvent();
        return _ceilDiv(assets * totalShares, currentAssets);
    }

    function previewRedeem(uint256 shares) public view override returns (uint256 assets) {
        if (shares == 0) return 0;
        if (totalShares == 0) revert Insolvent();
        return (shares * totalAssets()) / totalShares;
    }

    function deposit(uint256 assets, address receiver, uint256 minShares)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (minShares == 0) revert ZeroMinShares();

        uint256 beforeRawBalance = rawAssetBalance();
        uint256 currentAssets = managedAssets;
        if (beforeRawBalance < currentAssets) revert Insolvent();
        _safeTransferFrom(msg.sender, address(this), assets);
        uint256 afterRawBalance = rawAssetBalance();
        if (afterRawBalance < beforeRawBalance) revert Insolvent();
        uint256 received = afterRawBalance - beforeRawBalance;
        if (received == 0) revert ZeroAmount();
        if (currentAssets > depositCap || received > depositCap - currentAssets) {
            revert DepositCapExceeded();
        }

        shares = _calculateDepositShares(received, currentAssets, minShares);

        sharesOf[receiver] += shares;
        totalShares += shares;
        managedAssets = currentAssets + received;
        emit Deposited(msg.sender, receiver, received, shares);
    }

    function withdraw(uint256 assets, address receiver)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        uint256 currentAssets = managedAssets;
        if (rawAssetBalance() < currentAssets) revert Insolvent();
        if (assets > currentAssets) revert InsufficientAssets();
        shares = previewWithdraw(assets);
        if (shares > sharesOf[msg.sender]) revert InsufficientShares();

        sharesOf[msg.sender] -= shares;
        totalShares -= shares;
        managedAssets = currentAssets - assets;
        _safeTransfer(receiver, assets);
        emit Withdrawn(msg.sender, receiver, assets, shares);
    }

    function redeem(uint256 shares, address receiver)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (shares > sharesOf[msg.sender]) revert InsufficientShares();

        uint256 currentAssets = managedAssets;
        if (rawAssetBalance() < currentAssets) revert Insolvent();
        assets = previewRedeem(shares);
        if (assets == 0) revert ZeroAssetsOut();
        if (assets > currentAssets) revert InsufficientAssets();

        sharesOf[msg.sender] -= shares;
        totalShares -= shares;
        managedAssets = currentAssets - assets;
        _safeTransfer(receiver, assets);
        emit Withdrawn(msg.sender, receiver, assets, shares);
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        address previousOwner = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, msg.sender);
    }

    function recoverNonAssetToken(address token, address receiver, uint256 amount)
        external
        nonReentrant
        onlyOwner
    {
        if (token == asset) revert AssetRecoveryForbidden();
        if (receiver == address(0)) revert ZeroAddress();
        _safeExternalTransfer(token, receiver, amount);
    }

    function _safeTransfer(address receiver, uint256 amount) internal {
        uint256 beforeReceiverBalance = IERC20Minimal(asset).balanceOf(receiver);
        _safeExternalTransfer(asset, receiver, amount);
        uint256 afterReceiverBalance = IERC20Minimal(asset).balanceOf(receiver);
        if (
            afterReceiverBalance < beforeReceiverBalance
                || afterReceiverBalance - beforeReceiverBalance != amount
        ) {
            revert TransferFailed();
        }
    }

    function _safeTransferFrom(address from, address receiver, uint256 amount) internal {
        (bool success, bytes memory data) = asset.call(
            abi.encodeWithSelector(IERC20Minimal.transferFrom.selector, from, receiver, amount)
        );
        if (!success || (data.length != 0 && (data.length < 32 || !abi.decode(data, (bool))))) {
            revert TransferFailed();
        }
    }

    function _calculateDepositShares(uint256 received, uint256 currentAssets, uint256 minShares)
        private
        view
        returns (uint256 shares)
    {
        if (totalShares == 0) {
            shares = received;
        } else {
            if (currentAssets == 0) revert Insolvent();
            shares = (received * totalShares) / currentAssets;
        }
        if (shares == 0) revert ZeroShares();
        if (shares < minShares) revert SlippageExceeded();
    }

    function _safeExternalTransfer(address token, address receiver, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, receiver, amount));
        if (!success || (data.length != 0 && (data.length < 32 || !abi.decode(data, (bool))))) {
            revert TransferFailed();
        }
    }

    function _ceilDiv(uint256 numerator, uint256 denominator) private pure returns (uint256) {
        return numerator == 0 ? 0 : ((numerator - 1) / denominator) + 1;
    }
}
