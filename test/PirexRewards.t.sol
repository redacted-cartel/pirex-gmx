// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PirexRewards} from "src/PirexRewards.sol";
import {PirexRewardsMock} from "src/mocks/PirexRewardsMock.sol";
import {FeiFlywheelCoreV2} from "src/modified/FeiFlywheelCoreV2.sol";
import {PirexGmx} from "src/PirexGmx.sol";
import {Helper} from "test/Helper.sol";

contract PirexRewardsTest is Helper {
    /*//////////////////////////////////////////////////////////////
                        setProducer TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotSetProducerNotAuthorized() external {
        assertEq(address(pirexGmx), address(pirexRewards.producer()));

        address _producer = address(this);

        vm.prank(testAccounts[0]);
        vm.expectRevert(NOT_OWNER_ERROR);

        pirexRewards.setProducer(_producer);
    }

    /**
        @notice Test tx reversion: _producer is zero address
     */
    function testCannotSetProducerZeroAddress() external {
        assertEq(address(pirexGmx), address(pirexRewards.producer()));

        address invalidProducer = address(0);

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.setProducer(invalidProducer);
    }

    /**
        @notice Test tx success: set producer
     */
    function testSetProducer() external {
        assertEq(address(pirexGmx), address(pirexRewards.producer()));

        address producerBefore = address(pirexRewards.producer());
        address _producer = address(this);

        assertTrue(producerBefore != _producer);

        vm.expectEmit(false, false, false, true, address(pirexRewards));

        emit SetProducer(_producer);

        pirexRewards.setProducer(_producer);

        assertEq(_producer, address(pirexRewards.producer()));
    }

    /*//////////////////////////////////////////////////////////////
                        setRewardRecipient TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: rewardToken is zero address
     */
    function testCannotSetRewardRecipientRewardTokenZeroAddress() external {
        ERC20 invalidRewardToken = ERC20(address(0));
        address recipient = address(this);

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(invalidRewardToken, recipient);
    }

    /**
        @notice Test tx reversion: recipient is zero address
     */
    function testCannotSetRewardRecipientRecipientZeroAddress() external {
        ERC20 rewardToken = weth;
        address invalidRecipient = address(0);

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(rewardToken, invalidRecipient);
    }

    /**
        @notice Test tx success: set reward recipient
     */
    function testSetRewardRecipient() external {
        ERC20 rewardToken = weth;
        address recipient = address(this);
        address oldRecipient = pirexRewards.getRewardRecipient(
            address(this),
            rewardToken
        );

        assertEq(address(0), oldRecipient);
        assertTrue(recipient != oldRecipient);

        vm.expectEmit(true, true, true, true, address(pirexRewards));

        emit SetRewardRecipient(address(this), rewardToken, recipient);

        pirexRewards.setRewardRecipient(rewardToken, recipient);

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(address(this), rewardToken)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        unsetRewardRecipient TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: rewardToken is zero address
     */
    function testCannotUnsetRewardRecipientRewardTokenZeroAddress() external {
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipient(invalidRewardToken);
    }

    /**
        @notice Test tx success: unset reward recipient
     */
    function testUnsetRewardRecipient() external {
        ERC20 rewardToken = weth;
        address recipient = address(this);

        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(address(this), rewardToken)
        );

        // Set reward recipient in order to unset
        pirexRewards.setRewardRecipient(rewardToken, recipient);

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(address(this), rewardToken)
        );

        vm.expectEmit(true, true, false, true, address(pirexRewards));

        emit UnsetRewardRecipient(address(this), rewardToken);

        pirexRewards.unsetRewardRecipient(rewardToken);

        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(address(this), rewardToken)
        );
    }

    /*//////////////////////////////////////////////////////////////
                    setRewardRecipientPrivileged TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotSetRewardRecipientPrivilegedNotAuthorized() external {
        address lpContract = address(this);
        ERC20 rewardToken = weth;
        address recipient = address(this);

        vm.expectRevert(NOT_OWNER_ERROR);
        vm.prank(testAccounts[0]);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: lpContract is not a contract
     */
    function testCannotSetRewardRecipientPrivilegedLpContractNotContract()
        external
    {
        // Any address w/o code works (even non-EOA, contract addresses not on Arbi)
        address invalidLpContract = testAccounts[0];

        ERC20 rewardToken = weth;
        address recipient = address(this);

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.setRewardRecipientPrivileged(
            invalidLpContract,
            rewardToken,
            recipient
        );

        // Covers zero addresses
        invalidLpContract = address(0);

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.setRewardRecipientPrivileged(
            invalidLpContract,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: rewardToken is zero address
     */
    function testCannotSetRewardRecipientPrivilegedRewardTokenZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 invalidRewardToken = ERC20(address(0));
        address recipient = address(this);

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            invalidRewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: recipient is zero address
     */
    function testCannotSetRewardRecipientPrivilegedRecipientZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 rewardToken = weth;
        address invalidRecipient = address(0);

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            rewardToken,
            invalidRecipient
        );
    }

    /**
        @notice Test tx success: set the reward recipient as the contract owner
     */
    function testSetRewardRecipientPrivileged() external {
        address lpContract = address(this);
        ERC20 rewardToken = weth;
        address recipient = address(this);

        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(lpContract, rewardToken)
        );

        vm.expectEmit(true, true, true, true, address(pirexRewards));

        emit SetRewardRecipient(lpContract, rewardToken, recipient);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            rewardToken,
            recipient
        );

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(lpContract, rewardToken)
        );
    }

    /*//////////////////////////////////////////////////////////////
                    unsetRewardRecipientPrivileged TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotUnsetRewardRecipientPrivilegedNotAuthorized() external {
        address lpContract = address(this);
        ERC20 rewardToken = weth;

        vm.expectRevert(NOT_OWNER_ERROR);
        vm.prank(testAccounts[0]);

        pirexRewards.unsetRewardRecipientPrivileged(lpContract, rewardToken);
    }

    /**
        @notice Test tx reversion: lpContract is not a contract
     */
    function testCannotUnsetRewardRecipientPrivilegedLpContractNotContract()
        external
    {
        address invalidLpContract = testAccounts[0];
        ERC20 rewardToken = weth;

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.unsetRewardRecipientPrivileged(
            invalidLpContract,
            rewardToken
        );

        invalidLpContract = address(0);

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.unsetRewardRecipientPrivileged(
            invalidLpContract,
            rewardToken
        );
    }

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotUnsetRewardRecipientPrivilegedProducerTokenZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = weth;

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipientPrivileged(
            lpContract,
            invalidProducerToken,
            rewardToken
        );
    }

    /**
        @notice Test tx reversion: rewardToken is zero address
     */
    function testCannotUnsetRewardRecipientPrivilegedRewardTokenZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipientPrivileged(
            lpContract,
            invalidRewardToken
        );
    }

    /**
        @notice Test tx success: unset a reward recipient as the contract owner
     */
    function testUnsetRewardRecipientPrivileged() external {
        address lpContract = address(this);
        ERC20 rewardToken = weth;

        // Assert initial recipient
        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(lpContract, rewardToken)
        );

        // Set reward recipient in order to unset
        address recipient = address(this);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            rewardToken,
            recipient
        );

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(lpContract, rewardToken)
        );

        vm.expectEmit(true, true, false, true, address(pirexRewards));

        emit UnsetRewardRecipient(lpContract, rewardToken);

        pirexRewards.unsetRewardRecipientPrivileged(lpContract, rewardToken);

        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(lpContract, rewardToken)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        upgrade TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: upgrade the PirexRewards contract
     */
    function testUpgrade() external {
        // Must be a payable-address due to the existence of fallback method on the base proxy
        address payable proxyAddress = payable(address(pirexRewards));
        TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(
            proxyAddress
        );

        vm.prank(PROXY_ADMIN);

        // Store the old (pre-upgrade) implementation address before upgrading
        address oldImplementation = proxy.implementation();

        assertEq(proxyAddress, pirexGmx.pirexRewards());

        // Simulate deposit to accrue rewards in which the reward data
        // will be used later to test upgraded implementation
        address receiver = address(this);
        uint256 gmxAmount = 100e18;

        _depositGmx(gmxAmount, receiver);

        vm.warp(block.timestamp + 1 days);

        pirexRewards.setProducer(address(pirexGmx));
        pirexRewards.accrueStrategy();

        uint256 oldMethodResult = pirexRewards.getRewardState(
            ERC20(address(pxGmx)),
            weth
        );

        assertGt(oldMethodResult, 0);

        // Deploy and set a new implementation to the proxy as the admin
        PirexRewardsMock newImplementation = new PirexRewardsMock();

        vm.startPrank(PROXY_ADMIN);

        proxy.upgradeTo(address(newImplementation));

        assertEq(address(newImplementation), proxy.implementation());
        assertTrue(oldImplementation != proxy.implementation());

        vm.stopPrank();

        // Confirm that the proxy implementation has been updated
        // by attempting to call a new method only available in the new instance
        // and also assert the returned value
        assertEq(
            oldMethodResult * 2,
            PirexRewardsMock(proxyAddress).getRewardStateMock(ERC20(pxGmx))
        );

        // Confirm that the address of the proxy doesn't change, only the implementation
        assertEq(proxyAddress, pirexGmx.pirexRewards());
    }
}
