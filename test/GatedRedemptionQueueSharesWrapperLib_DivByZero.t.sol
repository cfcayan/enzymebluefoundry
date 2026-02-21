// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "src/GatedRedemptionQueueSharesWrapperLib_e971/contracts/persistent/shares-wrappers/gated-redemption-queue/GatedRedemptionQueueSharesWrapperLib.sol";
import "src/GatedRedemptionQueueSharesWrapperLib_e971/lib/openzeppelin-solc-0.6/contracts/token/ERC20/ERC20.sol";

interface Vm {
    function warp(uint256) external;
}

contract MockVaultShares is ERC20 {
    address private owner;

    constructor(address _owner) public ERC20("Vault", "VLT") {
        owner = _owner;
    }

    function getOwner() external view returns (address) {
        return owner;
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}

contract MockToken is ERC20 {
    constructor(string memory _name, string memory _symbol) public ERC20(_name, _symbol) {}

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}

contract MockDepositTarget {
    function deposit(address _vaultProxy, address _depositAsset, uint256 _depositAmount) external {
        ERC20(_depositAsset).transferFrom(msg.sender, address(this), _depositAmount);
        MockVaultShares(_vaultProxy).mint(msg.sender, _depositAmount);
    }
}

contract MockRedeemTarget {
    function redeem(address, address, address, uint256, bool) external {}
}

contract MockGlobalConfig {
    address private depositTarget;
    address private redeemTarget;

    constructor(address _depositTarget, address _redeemTarget) public {
        depositTarget = _depositTarget;
        redeemTarget = _redeemTarget;
    }

    function formatDepositCall(address _vaultProxy, address _depositAsset, uint256 _depositAssetAmount)
        external
        view
        returns (address target_, bytes memory payload_)
    {
        return (
            depositTarget,
            abi.encodeWithSelector(MockDepositTarget.deposit.selector, _vaultProxy, _depositAsset, _depositAssetAmount)
        );
    }

    function formatSingleAssetRedemptionCall(
        address _vaultProxy,
        address _recipient,
        address _asset,
        uint256 _amount,
        bool _amountIsShares
    )
        external
        view
        returns (address target_, bytes memory payload_)
    {
        return (
            redeemTarget,
            abi.encodeWithSelector(MockRedeemTarget.redeem.selector, _vaultProxy, _recipient, _asset, _amount, _amountIsShares)
        );
    }
}

contract GatedRedemptionQueueSharesWrapperLibDivByZeroTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function test_redeemFromQueueRevertsWhenRelativeSharesAllowedRoundsToZero() external {
        MockDepositTarget depositTarget = new MockDepositTarget();
        MockRedeemTarget redeemTarget = new MockRedeemTarget();
        MockGlobalConfig globalConfig = new MockGlobalConfig(address(depositTarget), address(redeemTarget));

        MockVaultShares vault = new MockVaultShares(address(this));
        MockToken depositAsset = new MockToken("Deposit", "DEP");
        MockToken redemptionAsset = new MockToken("Redeem", "RDM");

        GatedRedemptionQueueSharesWrapperLib wrapper =
            new GatedRedemptionQueueSharesWrapperLib(address(globalConfig), address(0));

        address[] memory managers = new address[](1);
        managers[0] = address(this);

        GatedRedemptionQueueSharesWrapperLibBase1.RedemptionWindowConfig memory windowConfig =
            GatedRedemptionQueueSharesWrapperLibBase1.RedemptionWindowConfig({
                firstWindowStart: 100,
                frequency: 100,
                duration: 50,
                relativeSharesCap: 1
            });

        wrapper.init(address(vault), managers, address(redemptionAsset), false, false, false, 0, windowConfig);

        depositAsset.mint(address(this), 1);
        depositAsset.approve(address(wrapper), type(uint256).max);

        vm.warp(1);
        wrapper.deposit(address(depositAsset), 1, 1);
        wrapper.requestRedeem(1);

        vm.warp(100);

        (bool ok,) = address(wrapper).call(
            abi.encodeWithSelector(wrapper.redeemFromQueue.selector, uint256(0), uint256(0))
        );
        require(!ok, "expected redeemFromQueue to revert when totalSharesRedeemed == 0");
    }
}
