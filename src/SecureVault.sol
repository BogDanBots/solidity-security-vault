// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVault} from "./interfaces/IVault.sol";

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title SecureVault
/// @notice A compact, single-asset vault with non-transferable internal shares.
/// @dev This is intentionally not an ERC-4626 implementation. Keeping shares
///      non-transferable makes the ownership and accounting surface reviewable.
contract SecureVault is IVault {
    error ZeroAddress();
    error ZeroAmount();
    error ZeroShares();
    error ZeroAssetsOut();
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
        return IERC20Minimal(asset).balanceOf(address(this));
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

    function deposit(uint256 assets, address receiver)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        uint256 beforeAssets = totalAssets();
        _safeTransferFrom(msg.sender, address(this), assets);
        uint256 received = totalAssets() - beforeAssets;
        if (received == 0) revert ZeroAmount();
        if (beforeAssets > depositCap || received > depositCap - beforeAssets) {
            revert DepositCapExceeded();
        }

        if (totalShares == 0) {
            shares = received;
        } else {
            if (beforeAssets == 0) revert Insolvent();
            shares = (received * totalShares) / beforeAssets;
        }
        if (shares == 0) revert ZeroShares();

        sharesOf[receiver] += shares;
        totalShares += shares;
        emit Deposited(msg.sender, receiver, received, shares);
    }

    function withdraw(uint256 assets, address receiver)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        uint256 beforeAssets = totalAssets();
        if (assets > beforeAssets) revert InsufficientAssets();
        shares = previewWithdraw(assets);
        if (shares > sharesOf[msg.sender]) revert InsufficientShares();

        sharesOf[msg.sender] -= shares;
        totalShares -= shares;
        _safeTransfer(receiver, assets);
        emit Withdrawn(msg.sender, receiver, assets, shares);
    }

    function redeem(uint256 shares, address receiver)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (shares > sharesOf[msg.sender]) revert InsufficientShares();

        assets = previewRedeem(shares);
        if (assets == 0) revert ZeroAssetsOut();
        if (assets > totalAssets()) revert InsufficientAssets();

        sharesOf[msg.sender] -= shares;
        totalShares -= shares;
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

    function recoverNonAssetToken(address token, address receiver, uint256 amount) external onlyOwner {
        if (token == asset) revert AssetRecoveryForbidden();
        if (receiver == address(0)) revert ZeroAddress();
        _safeExternalTransfer(token, receiver, amount);
    }

    function _safeTransfer(address receiver, uint256 amount) internal {
        _safeExternalTransfer(asset, receiver, amount);
    }

    function _safeTransferFrom(address from, address receiver, uint256 amount) internal {
        (bool success, bytes memory data) = asset.call(
            abi.encodeWithSelector(IERC20Minimal.transferFrom.selector, from, receiver, amount)
        );
        if (!success || (data.length != 0 && (data.length < 32 || !abi.decode(data, (bool))))) {
            revert TransferFailed();
        }
    }

    function _safeExternalTransfer(address token, address receiver, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Minimal.transfer.selector, receiver, amount)
        );
        if (!success || (data.length != 0 && (data.length < 32 || !abi.decode(data, (bool))))) {
            revert TransferFailed();
        }
    }

    function _ceilDiv(uint256 numerator, uint256 denominator) private pure returns (uint256) {
        return numerator == 0 ? 0 : ((numerator - 1) / denominator) + 1;
    }
}
