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
    /**
        @notice Perform assertions for global state
    */
    function _assertGlobalState(
        ERC20 producerToken,
        uint256 expectedLastUpdate,
        uint256 expectedLastSupply,
        uint256 expectedRewards
    ) internal {
        (
            uint256 lastUpdate,
            uint256 lastSupply,
            uint256 rewards
        ) = _getGlobalState(producerToken);

        assertEq(expectedLastUpdate, lastUpdate);
        assertEq(expectedLastSupply, lastSupply);
        assertEq(expectedRewards, rewards);
    }

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
                        userAccrue TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotUserAccrueProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        address user = address(this);

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.userAccrue(invalidProducerToken, user);
    }

    /**
        @notice Test tx reversion: user is zero address
     */
    function testCannotUserAccrueUserZeroAddress() external {
        ERC20 producerToken = pxGlp;
        address invalidUser = address(0);

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.userAccrue(producerToken, invalidUser);
    }

    /**
        @notice Test tx success: user rewards accrual
        @param  secondsElapsed    uint32  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  multiplier        uint8   Multiplied with fixed token amounts for randomness
        @param  useETH            bool    Whether or not to use ETH as the source asset for minting GLP
        @param  hasCooldown       bool    Whether or not to enable GLP cooldown duration
        @param  testAccountIndex  uint8   Index of test account
        @param  useGmx            bool    Whether to use pxGMX
     */
    function testUserAccrue(
        uint32 secondsElapsed,
        uint8 multiplier,
        bool useETH,
        bool hasCooldown,
        uint8 testAccountIndex,
        bool useGmx
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);
        vm.assume(testAccountIndex < 3);

        ERC20 producerToken = useGmx
            ? ERC20(address(pxGmx))
            : ERC20(address(pxGlp));

        _depositForTestAccounts(useGmx, multiplier, useETH, hasCooldown);

        address user = testAccounts[testAccountIndex];
        uint256 pxBalance = producerToken.balanceOf(user);
        (
            uint256 lastUpdateBefore,
            uint256 lastBalanceBefore,
            uint256 rewardsBefore
        ) = pirexRewards.getUserState(producerToken, user);
        uint256 warpTimestamp = block.timestamp + secondsElapsed;

        // GMX minting warps timestamp (timelock) so we will test for a non-zero value
        assertTrue(lastUpdateBefore != 0);

        // The recently minted balance amount should be what is stored in state
        assertEq(lastBalanceBefore, pxBalance);

        // User should not accrue rewards until time has passed
        assertEq(0, rewardsBefore);

        vm.warp(warpTimestamp);

        uint256 expectedUserRewards = _calculateUserRewards(
            producerToken,
            user
        );

        vm.expectEmit(true, true, false, true, address(pirexRewards));

        emit UserAccrue(
            producerToken,
            user,
            block.timestamp,
            pxBalance,
            expectedUserRewards
        );

        pirexRewards.userAccrue(producerToken, user);

        (
            uint256 lastUpdateAfter,
            uint256 lastBalanceAfter,
            uint256 rewardsAfter
        ) = pirexRewards.getUserState(producerToken, user);

        assertEq(warpTimestamp, lastUpdateAfter);
        assertEq(pxBalance, lastBalanceAfter);
        assertEq(expectedUserRewards, rewardsAfter);
        assertTrue(rewardsAfter != 0);
    }

    /*//////////////////////////////////////////////////////////////
                        setRewardRecipient TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotSetRewardRecipientProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = weth;
        address recipient = address(this);

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(
            invalidProducerToken,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: rewardToken is zero address
     */
    function testCannotSetRewardRecipientRewardTokenZeroAddress() external {
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));
        address recipient = address(this);

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(
            producerToken,
            invalidRewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: recipient is zero address
     */
    function testCannotSetRewardRecipientRecipientZeroAddress() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        address invalidRecipient = address(0);

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(
            producerToken,
            rewardToken,
            invalidRecipient
        );
    }

    /**
        @notice Test tx success: set reward recipient
     */
    function testSetRewardRecipient() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        address recipient = address(this);
        address oldRecipient = pirexRewards.getRewardRecipient(
            address(this),
            producerToken,
            rewardToken
        );

        assertEq(address(0), oldRecipient);
        assertTrue(recipient != oldRecipient);

        vm.expectEmit(true, true, true, true, address(pirexRewards));

        emit SetRewardRecipient(
            address(this),
            producerToken,
            rewardToken,
            recipient
        );

        pirexRewards.setRewardRecipient(producerToken, rewardToken, recipient);

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(
                address(this),
                producerToken,
                rewardToken
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                        unsetRewardRecipient TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotUnsetRewardRecipientProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = weth;

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipient(invalidProducerToken, rewardToken);
    }

    /**
        @notice Test tx reversion: rewardToken is zero address
     */
    function testCannotUnsetRewardRecipientRewardTokenZeroAddress() external {
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipient(producerToken, invalidRewardToken);
    }

    /**
        @notice Test tx success: unset reward recipient
     */
    function testUnsetRewardRecipient() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        address recipient = address(this);

        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(
                address(this),
                producerToken,
                rewardToken
            )
        );

        // Set reward recipient in order to unset
        pirexRewards.setRewardRecipient(pxGlp, rewardToken, recipient);

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(
                address(this),
                producerToken,
                rewardToken
            )
        );

        vm.expectEmit(true, true, true, true, address(pirexRewards));

        emit UnsetRewardRecipient(address(this), producerToken, rewardToken);

        pirexRewards.unsetRewardRecipient(producerToken, rewardToken);

        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(
                address(this),
                producerToken,
                rewardToken
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                        addRewardToken TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotAddStrategyForRewardsNotAuthorized() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;

        vm.expectRevert(NOT_OWNER_ERROR);
        vm.prank(testAccounts[0]);

        pirexRewards.addStrategyForRewards(producerToken, rewardToken);
    }

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotAddStrategyForRewardsProducerTokenZeroAddress()
        external
    {
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = ERC20(address(0));

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.addStrategyForRewards(invalidProducerToken, rewardToken);
    }

    /**
        @notice Test tx reversion: rewardToken is zero address
     */
    function testCannotAddStrategyForRewardsRewardTokenZeroAddress() external {
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.addStrategyForRewards(producerToken, invalidRewardToken);
    }

    /**
        @notice Test tx success: add a strategy
     */
    function testAddStrategyForRewards() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        bytes memory strategy = abi.encode(producerToken, rewardToken);

        vm.expectEmit(true, false, false, true, address(pirexRewards));

        emit AddStrategy(strategy);

        pirexRewards.addStrategyForRewards(producerToken, rewardToken);

        bytes[] memory strategies = pirexRewards.getAllStrategies();
        (uint224 index, uint32 lastUpdatedTimestamp) = pirexRewards.strategyState(strategy);

        assertEq(strategy, strategies[strategies.length - 1]);
        assertEq(index, pirexRewards.ONE());
        assertEq(block.timestamp, lastUpdatedTimestamp);
    }

    /*//////////////////////////////////////////////////////////////
                            claim TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotClaimProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        address user = address(this);

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.claim(invalidProducerToken, user);
    }

    /**
        @notice Test tx reversion: user is zero address
     */
    function testCannotClaimUserZeroAddress() external {
        ERC20 producerToken = pxGlp;
        address invalidUser = address(0);

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.claim(producerToken, invalidUser);
    }

    /**
        @notice Test tx success: claim
        @param  secondsElapsed  uint32  Seconds to forward timestamp
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  useETH          bool    Whether to use ETH when minting
        @param  hasCooldown     bool    Whether or not to enable GLP cooldown duration
        @param  forwardRewards  bool    Whether to forward rewards
     */
    function testClaim(
        uint32 secondsElapsed,
        uint8 multiplier,
        bool useETH,
        bool hasCooldown,
        bool forwardRewards
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        _depositGmxForTestAccounts(true, address(this), multiplier);
        _depositGlpForTestAccounts(
            true,
            address(this),
            multiplier,
            useETH,
            hasCooldown
        );

        vm.warp(block.timestamp + secondsElapsed);

        // Add reward token and accrue strategy rewards from PirexGmx contract
        pirexRewards.addStrategyForRewards(pxGmx, weth);
        pirexRewards.addStrategyForRewards(pxGlp, weth);
        pirexRewards.accrueStrategy();

        for (uint256 i; i < testAccounts.length; ++i) {
            address recipient = forwardRewards
                ? address(this)
                : testAccounts[i];

            if (forwardRewards) {
                vm.startPrank(testAccounts[i]);

                pirexRewards.setRewardRecipient(pxGmx, weth, address(this));
                pirexRewards.setRewardRecipient(pxGlp, weth, address(this));

                vm.stopPrank();
            } else {
                assertEq(0, weth.balanceOf(testAccounts[i]));
            }

            pirexRewards.userAccrue(pxGmx, testAccounts[i]);
            pirexRewards.userAccrue(pxGlp, testAccounts[i]);

            (, , uint256 globalRewardsBeforeClaimPxGmx) = _getGlobalState(
                pxGmx
            );
            (, , uint256 globalRewardsBeforeClaimPxGlp) = _getGlobalState(
                pxGlp
            );
            (, , uint256 userRewardsBeforeClaimPxGmx) = pirexRewards
                .getUserState(pxGmx, testAccounts[i]);
            (, , uint256 userRewardsBeforeClaimPxGlp) = pirexRewards
                .getUserState(pxGlp, testAccounts[i]);

            // Sum of reward amounts that the user/recipient is entitled to
            uint256 expectedClaimAmount = ((pirexRewards.getRewardState(
                pxGmx,
                weth
            ) * _calculateUserRewards(pxGmx, testAccounts[i])) /
                _calculateGlobalRewards(pxGmx)) +
                ((pirexRewards.getRewardState(pxGlp, weth) *
                    _calculateUserRewards(pxGlp, testAccounts[i])) /
                    _calculateGlobalRewards(pxGlp));

            // Deduct previous balance if rewards are forwarded
            uint256 recipientBalanceDeduction = forwardRewards
                ? weth.balanceOf(recipient)
                : 0;

            vm.expectEmit(true, true, false, true, address(pirexRewards));

            emit Claim(pxGmx, testAccounts[i]);

            pirexRewards.claim(pxGmx, testAccounts[i]);

            vm.expectEmit(true, true, false, true, address(pirexRewards));

            emit Claim(pxGlp, testAccounts[i]);

            pirexRewards.claim(pxGlp, testAccounts[i]);

            (, , uint256 globalRewardsAfterClaimPxGmx) = _getGlobalState(pxGmx);
            (, , uint256 globalRewardsAfterClaimPxGlp) = _getGlobalState(pxGlp);
            (, , uint256 userRewardsAfterClaimPxGmx) = pirexRewards
                .getUserState(pxGmx, testAccounts[i]);
            (, , uint256 userRewardsAfterClaimPxGlp) = pirexRewards
                .getUserState(pxGlp, testAccounts[i]);

            assertEq(
                globalRewardsBeforeClaimPxGmx - userRewardsBeforeClaimPxGmx,
                globalRewardsAfterClaimPxGmx
            );
            assertEq(
                globalRewardsBeforeClaimPxGlp - userRewardsBeforeClaimPxGlp,
                globalRewardsAfterClaimPxGlp
            );
            assertEq(0, userRewardsAfterClaimPxGmx);
            assertEq(0, userRewardsAfterClaimPxGlp);
            assertEq(
                expectedClaimAmount,
                weth.balanceOf(recipient) - recipientBalanceDeduction
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                    setRewardRecipientPrivileged TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotSetRewardRecipientPrivilegedNotAuthorized() external {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        address recipient = address(this);

        vm.expectRevert(NOT_OWNER_ERROR);

        vm.prank(testAccounts[0]);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            producerToken,
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

        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        address recipient = address(this);

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.setRewardRecipientPrivileged(
            invalidLpContract,
            producerToken,
            rewardToken,
            recipient
        );

        // Covers zero addresses
        invalidLpContract = address(0);

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.setRewardRecipientPrivileged(
            invalidLpContract,
            producerToken,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotSetRewardRecipientPrivilegedProducerTokenZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = weth;
        address recipient = address(this);

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            invalidProducerToken,
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
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));
        address recipient = address(this);

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            producerToken,
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
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        address invalidRecipient = address(0);

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            invalidRecipient
        );
    }

    /**
        @notice Test tx success: set the reward recipient as the contract owner
     */
    function testSetRewardRecipientPrivileged() external {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        address recipient = address(this);

        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(
                lpContract,
                producerToken,
                rewardToken
            )
        );

        vm.expectEmit(true, true, true, true, address(pirexRewards));

        emit SetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            recipient
        );

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            recipient
        );

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(
                lpContract,
                producerToken,
                rewardToken
            )
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
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;

        vm.expectRevert(NOT_OWNER_ERROR);

        vm.prank(testAccounts[0]);

        pirexRewards.unsetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken
        );
    }

    /**
        @notice Test tx reversion: lpContract is not a contract
     */
    function testCannotUnsetRewardRecipientPrivilegedLpContractNotContract()
        external
    {
        address invalidLpContract = testAccounts[0];
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.unsetRewardRecipientPrivileged(
            invalidLpContract,
            producerToken,
            rewardToken
        );

        invalidLpContract = address(0);

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.unsetRewardRecipientPrivileged(
            invalidLpContract,
            producerToken,
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
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(FeiFlywheelCoreV2.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            invalidRewardToken
        );
    }

    /**
        @notice Test tx success: unset a reward recipient as the contract owner
     */
    function testUnsetRewardRecipientPrivileged() external {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;

        // Assert initial recipient
        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(
                lpContract,
                producerToken,
                rewardToken
            )
        );

        // Set reward recipient in order to unset
        address recipient = address(this);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            recipient
        );

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(
                lpContract,
                producerToken,
                rewardToken
            )
        );

        vm.expectEmit(true, true, false, true, address(pirexRewards));

        emit UnsetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken
        );

        pirexRewards.unsetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken
        );

        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(
                lpContract,
                producerToken,
                rewardToken
            )
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
            PirexRewardsMock(proxyAddress).getRewardStateMock(
                ERC20(address(pxGmx)),
                weth
            )
        );

        // Confirm that the address of the proxy doesn't change, only the implementation
        assertEq(proxyAddress, pirexGmx.pirexRewards());
    }
}
