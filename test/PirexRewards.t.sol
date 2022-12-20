// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PirexRewards} from "src/PirexRewards.sol";
import {PirexRewardsMock} from "src/mocks/PirexRewardsMock.sol";
import {PirexGmx} from "src/PirexGmx.sol";
import {Helper} from "test/Helper.sol";

contract PirexRewardsTest is Helper {
    /**
        @notice Set all of the Pirex-GMX strategies
     */
    function _setStrategies() internal {
        ERC20[] memory producerTokens = new ERC20[](2);
        ERC20[] memory rewardTokens = new ERC20[](2);
        producerTokens[0] = pxGmx;
        producerTokens[1] = pxGlp;
        rewardTokens[0] = weth;
        rewardTokens[1] = pxGmx;

        uint256 one = pirexRewards.ONE();

        for (uint256 i; i < producerTokens.length; ++i) {
            for (uint256 j; j < rewardTokens.length; ++j) {
                pirexRewards.addStrategyForRewards(
                    producerTokens[i],
                    rewardTokens[j]
                );

                uint256 index = pirexRewards.strategyState(
                    abi.encode(producerTokens[i], rewardTokens[j])
                );

                assertEq(one, index);
            }
        }
    }

    /**
        @notice Mock-up reward accrual state for the pxGMX-WETH strategy
        @param  iterations           uint256  Number of iterations to accrue rewards
        @param  secondsElapsed       uint256  Seconds elapsed between each reward accrual iteration
        @param  aliceDeposit         uint256  Alice pxGMX deposit amount
        @param  bobDeposit           uint256  Bob pxGMX deposit amount
        @param  bobDepositIteration  uint256  Iteration at which Bob deposits pxGMX
     */
    function _mockStrategyRewardAccrual(
        uint256 iterations,
        uint256 secondsElapsed,
        uint256 aliceDeposit,
        uint256 bobDeposit,
        uint256 bobDepositIteration
    )
        internal
        returns (
            uint256[] memory rewards,
            uint256[] memory aliceRewards,
            uint256[] memory bobRewards
        )
    {
        // Bob must deposit before the number of reward accrual iterations is over
        assert(iterations > bobDepositIteration);

        _setStrategies();

        // Mint GMX ahead of actual tests due to timestamp forwarding (to bypass GMX lock)
        // This provides us with a measure of predictability when testing reward accrual
        _mintApproveGmx(
            aliceDeposit + bobDeposit,
            address(this),
            address(pirexGmx),
            aliceDeposit + bobDeposit
        );

        address alice = testAccounts[0];
        address bob = testAccounts[1];

        pirexGmx.depositGmx(aliceDeposit, alice);

        rewards = new uint256[](iterations);
        aliceRewards = new uint256[](iterations);
        bobRewards = new uint256[](iterations);

        for (uint256 i; i < iterations; ++i) {
            // Used to calculate the exact amount of rewards accrued for an iteration
            uint256 aliceTotalRewards = pirexRewards.getUserRewardsAccrued(
                alice,
                weth
            );
            uint256 bobTotalRewards = pirexRewards.getUserRewardsAccrued(
                bob,
                weth
            );

            vm.warp(block.timestamp + secondsElapsed);

            (, , uint256[] memory rewardAmounts) = pirexRewards
                .accrueStrategy();

            rewards[i] = rewardAmounts[0];

            // Accrue user rewards
            pirexRewards.accrueUser(pxGmx, alice);
            pirexRewards.accrueUser(pxGmx, bob);

            // Deduct the previous accrued amounts to get the amounts accrued for this iteration
            aliceRewards[i] =
                pirexRewards.getUserRewardsAccrued(alice, weth) -
                aliceTotalRewards;
            bobRewards[i] =
                pirexRewards.getUserRewardsAccrued(bob, weth) -
                bobTotalRewards;

            if (i == bobDepositIteration) {
                pirexGmx.depositGmx(bobDeposit, bob);

                // Bob should have 0 rewards accrued since he is a new token holder
                assertEq(0, pirexRewards.getUserRewardsAccrued(bob, weth));

                // Alice should have all of the rewards accrued so far
                assertEq(
                    pirexRewards.strategyState(abi.encode(pxGmx, weth)) -
                        pirexRewards.ONE(),
                    pirexRewards.getUserRewardsAccrued(alice, weth)
                );
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        setProducer TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
    */
    function testCannotSetProducerNotAuthorized() external {
        address producer = address(this);

        vm.prank(_getUnauthorizedCaller(pirexRewards.owner()));
        vm.expectRevert(NOT_OWNER_ERROR);

        pirexRewards.setProducer(producer);
    }

    /**
        @notice Test tx reversion: producer is zero address
     */
    function testCannotSetProducerZeroAddress() external {
        address invalidProducer = address(0);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setProducer(invalidProducer);
    }

    /**
        @notice Test tx success: set producer
     */
    function testSetProducer() external {
        address producerBefore = address(pirexRewards.producer());
        address producer = address(this);

        assertTrue(producerBefore != producer);

        vm.expectEmit(false, false, false, true, address(pirexRewards));

        emit SetProducer(producer);

        pirexRewards.setProducer(producer);

        assertEq(producer, address(pirexRewards.producer()));
    }

    /*//////////////////////////////////////////////////////////////
                        addStrategyForRewards TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotAddStrategyForRewardsProducerTokenZeroAddress()
        external
    {
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = weth;

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.addStrategyForRewards(invalidProducerToken, rewardToken);
    }

    /**
        @notice Test tx reversion: rewardToken is zero address
     */
    function testCannotAddStrategyForRewardsRewardTokenZeroAddress() external {
        ERC20 producerToken = pxGmx;
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.addStrategyForRewards(producerToken, invalidRewardToken);
    }

    /**
        @notice Test tx reversion: strategy is already set
     */
    function testCannotAddStrategyForRewardsAlreadySet() external {
        ERC20 producerToken = pxGmx;
        ERC20 rewardToken = weth;

        pirexRewards.addStrategyForRewards(producerToken, rewardToken);

        vm.expectRevert(PirexRewards.StrategyAlreadySet.selector);

        pirexRewards.addStrategyForRewards(producerToken, rewardToken);
    }

    /**
        @notice Test tx success: add strategy
     */
    function testAddStrategyForRewards() external {
        ERC20[] memory producerTokens = new ERC20[](2);
        ERC20[] memory rewardTokens = new ERC20[](2);
        producerTokens[0] = pxGmx;
        producerTokens[1] = pxGlp;
        rewardTokens[0] = weth;
        rewardTokens[1] = pxGmx;

        for (uint256 i; i < producerTokens.length; ++i) {
            for (uint256 j; j < rewardTokens.length; ++j) {
                bytes memory strategy = abi.encode(
                    producerTokens[i],
                    rewardTokens[j]
                );

                vm.expectEmit(true, false, false, true, address(pirexRewards));

                emit AddStrategy(strategy);

                assertEq(
                    strategy,
                    pirexRewards.addStrategyForRewards(
                        producerTokens[i],
                        rewardTokens[j]
                    )
                );
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        accrueStrategy TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice  Test tx success: accrue strategy
     */
    function testAccrueStrategy() external {
        _setStrategies();

        // Deposit GMX and GLP to accrue GMX rewards
        _depositGmx(1e18, address(this));
        _depositGlp(1e18, address(this));

        vm.warp(block.timestamp + 10_000);

        // Sync PirexRewards strategy state with accrued rewards
        (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        ) = pirexRewards.accrueStrategy();

        // First time accruing strategies, they should all be ONE previously
        uint256 startingStrategyIndex = pirexRewards.ONE();

        for (uint256 i; i < producerTokens.length; ++i) {
            uint256 expectedRewardDelta = (rewardAmounts[i] * 1e18) /
                producerTokens[i].totalSupply();

            assertEq(
                startingStrategyIndex + expectedRewardDelta,
                pirexRewards.strategyState(
                    abi.encode(producerTokens[i], rewardTokens[i])
                )
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        accrueUser TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotAccrueUserProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        address user = address(this);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(invalidProducerToken, user);
    }

    /**
        @notice Test tx reversion: user is zero address
     */
    function testCannotAccrueUserUserZeroAddress() external {
        ERC20 producerToken = pxGmx;
        address invalidUser = address(0);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(producerToken, invalidUser);
    }

    /**
        @notice Test tx success: user accrued upon depositing the first time
     */
    function testAccrueUser() external {
        _setStrategies();

        uint256 tLen = testAccounts.length;
        bytes[] memory pxGmxStrategies = pirexRewards.getStrategies(pxGmx);
        bytes[] memory pxGlpStrategies = pirexRewards.getStrategies(pxGlp);

        for (uint256 i; i < tLen; ++i) {
            address testAccount = testAccounts[i];

            // Mint pxGMX and pxGLP, which results in the accrueUser hook being called
            _depositGmx(1e18, testAccount);
            _depositGlp(1e18, testAccount);

            for (uint256 j; j < pxGmxStrategies.length; ++j) {
                bytes memory strategy = pxGmxStrategies[j];

                // Upon their 1st accrual, each user's index should equal the strategy (i.e. no rewards accrued yet)
                assertEq(
                    pirexRewards.strategyState(strategy),
                    pirexRewards.getUserStrategyIndex(testAccount, strategy)
                );
            }

            for (uint256 k; k < pxGlpStrategies.length; ++k) {
                bytes memory strategy = pxGlpStrategies[k];

                // Upon their 1st accrual, each user's index should equal the strategy (i.e. no rewards accrued yet)
                assertEq(
                    pirexRewards.strategyState(strategy),
                    pirexRewards.getUserStrategyIndex(testAccount, strategy)
                );
            }
        }
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

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(invalidRewardToken, recipient);
    }

    /**
        @notice Test tx reversion: recipient is zero address
     */
    function testCannotSetRewardRecipientRecipientZeroAddress() external {
        ERC20 rewardToken = weth;
        address invalidRecipient = address(0);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

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

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipient(invalidRewardToken);
    }

    /**
        @notice Test tx success: unset reward recipient
     */
    function testUnsetRewardRecipient() external {
        ERC20 rewardToken = weth;
        address recipient = address(this);

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

        vm.prank(_getUnauthorizedCaller(pirexRewards.owner()));
        vm.expectRevert(NOT_OWNER_ERROR);

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
        // Any address w/o code works for this test
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

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

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

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

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
        @notice Test tx reversion: rewardToken is zero address
     */
    function testCannotUnsetRewardRecipientPrivilegedRewardTokenZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

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

        _setStrategies();

        ERC20 producerToken = pxGmx;
        uint256 previousGmxStrategies = (
            pirexRewards.getStrategies(producerToken)
        ).length;

        assertGt(previousGmxStrategies, 0);

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
            previousGmxStrategies * 2,
            PirexRewardsMock(proxyAddress).getRewardStateMock(producerToken)
        );

        // Confirm that the address of the proxy doesn't change, only the implementation
        assertEq(proxyAddress, pirexGmx.pirexRewards());
    }
}
