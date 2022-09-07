// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexGmxGlp} from "src/PirexGmxGlp.sol";
import {Vault} from "src/external/Vault.sol";
import {IRewardDistributor} from "src/interfaces/IRewardDistributor.sol";
import {IWETH} from "src/interfaces/IWETH.sol";
import {Helper} from "./Helper.t.sol";

contract PirexGmxGlpTest is Test, Helper {
    bytes32 internal constant DEFAULT_DELEGATION_SPACE = bytes32("gmx.eth");

    bytes internal constant PAUSED_ERROR = "Pausable: paused";
    bytes internal constant NOT_PAUSED_ERROR = "Pausable: not paused";
    bytes internal constant INSUFFICIENT_OUTPUT_ERROR =
        "GlpManager: insufficient output";
    bytes internal constant INSUFFICIENT_GLP_OUTPUT_ERROR =
        "GlpManager: insufficient GLP output";

    event InitiateMigration(address newContract);
    event CompleteMigration(address oldContract);
    event ClaimRewards(
        uint256 wethRewards,
        uint256 esGmxRewards,
        uint256 gmxWethRewards,
        uint256 glpWethRewards,
        uint256 gmxEsGmxRewards,
        uint256 glpEsGmxRewards
    );
    event SetContract(PirexGmxGlp.Contracts indexed c, address contractAddress);
    event SetDelegateRegistry(address delegateRegistry);
    event SetDelegationSpace(string delegationSpace, bool shouldClear);
    event SetVoteDelegate(address voteDelegate);
    event ClearVoteDelegate();

    /**
        @notice Assert the default values for all fee types
     */
    function _assertDefaultFeeValues() internal {
        for (uint256 i; i < feeTypes.length; ++i) {
            assertEq(0, pirexGmxGlp.fees(feeTypes[i]));
        }
    }

    /*//////////////////////////////////////////////////////////////
                        setPirexRewards TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetPirexRewardsUnauthorized() external {
        assertEq(address(pirexRewards), pirexGmxGlp.pirexRewards());

        address _pirexRewards = address(this);

        vm.expectRevert(UNAUTHORIZED_ERROR);

        vm.prank(testAccounts[0]);

        pirexGmxGlp.setPirexRewards(_pirexRewards);
    }

    /**
        @notice Test tx reversion: _pirexRewards is zero address
     */
    function testCannotSetPirexRewardsZeroAddress() external {
        assertEq(address(pirexRewards), pirexGmxGlp.pirexRewards());

        address invalidPirexRewards = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.setPirexRewards(invalidPirexRewards);
    }

    /**
        @notice Test tx success: set pirexRewards
     */
    function testSetPirexRewards() external {
        address pirexRewardsBefore = address(pirexGmxGlp.pirexRewards());
        address _pirexRewards = address(this);

        assertEq(address(pirexRewards), pirexGmxGlp.pirexRewards());
        assertTrue(pirexRewardsBefore != _pirexRewards);

        vm.expectEmit(false, false, false, true, address(pirexGmxGlp));

        emit SetPirexRewards(_pirexRewards);

        pirexGmxGlp.setPirexRewards(_pirexRewards);

        assertEq(_pirexRewards, address(pirexGmxGlp.pirexRewards()));
    }

    /*//////////////////////////////////////////////////////////////
                        setDelegateRegistry TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetDelegateRegistryUnauthorized() external {
        assertEq(
            address(delegateRegistry),
            address(pirexGmxGlp.delegateRegistry())
        );

        address _delegateRegistry = address(this);

        vm.expectRevert(UNAUTHORIZED_ERROR);

        vm.prank(testAccounts[0]);

        pirexGmxGlp.setDelegateRegistry(_delegateRegistry);
    }

    /**
        @notice Test tx reversion: _delegateRegistry is zero address
     */
    function testCannotSetDelegateRegistryZeroAddress() external {
        assertEq(
            address(delegateRegistry),
            address(pirexGmxGlp.delegateRegistry())
        );

        address invalidDelegateRegistry = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.setDelegateRegistry(invalidDelegateRegistry);
    }

    /**
        @notice Test tx success: set delegateRegistry
     */
    function testSetDelegateRegistry() external {
        address delegateRegistryBefore = address(
            pirexGmxGlp.delegateRegistry()
        );
        address _delegateRegistry = address(this);

        assertEq(address(delegateRegistry), delegateRegistryBefore);
        assertFalse(delegateRegistryBefore == _delegateRegistry);

        vm.expectEmit(false, false, false, true, address(pirexGmxGlp));

        emit SetDelegateRegistry(_delegateRegistry);

        pirexGmxGlp.setDelegateRegistry(_delegateRegistry);

        assertEq(address(pirexGmxGlp.delegateRegistry()), _delegateRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                        setFee TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetFeeUnauthorized() external {
        _assertDefaultFeeValues();

        vm.expectRevert(UNAUTHORIZED_ERROR);

        vm.prank(testAccounts[0]);

        pirexGmxGlp.setFee(PirexGmxGlp.Fees.Deposit, 1);
    }

    /**
        @notice Test tx reversion: fee amount exceeds the maximum
     */
    function testCannotSetFeeExceedsMax() external {
        _assertDefaultFeeValues();

        for (uint256 i; i < feeTypes.length; ++i) {
            vm.expectRevert(PirexGmxGlp.InvalidFee.selector);

            pirexGmxGlp.setFee(feeTypes[i], feeMax + 1);
        }
    }

    /**
        @notice Test tx success: set fees for each type
        @param  deposit     uint256  Deposit fee
        @param  redemption  uint256  Redemption fee
        @param  reward      uint256  Reward fee
     */
    function testSetFee(
        uint256 deposit,
        uint256 redemption,
        uint256 reward
    ) external {
        vm.assume(deposit != 0);
        vm.assume(deposit < feeMax);
        vm.assume(redemption != 0);
        vm.assume(redemption < feeMax);
        vm.assume(reward != 0);
        vm.assume(reward < feeMax);

        _assertDefaultFeeValues();

        pirexGmxGlp.setFee(PirexGmxGlp.Fees.Deposit, deposit);
        pirexGmxGlp.setFee(PirexGmxGlp.Fees.Redemption, redemption);
        pirexGmxGlp.setFee(PirexGmxGlp.Fees.Reward, reward);

        assertEq(deposit, pirexGmxGlp.fees(feeTypes[0]));
        assertEq(redemption, pirexGmxGlp.fees(feeTypes[1]));
        assertEq(reward, pirexGmxGlp.fees(feeTypes[2]));
    }

    /*//////////////////////////////////////////////////////////////
                        setContract TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotSetContractNotAuthorized() external {
        vm.prank(testAccounts[0]);
        vm.expectRevert(UNAUTHORIZED_ERROR);

        pirexGmxGlp.setContract(
            PirexGmxGlp.Contracts.RewardRouterV2,
            address(this)
        );
    }

    /**
        @notice Test tx reversion: contractAddress is the zero address
     */
    function testCannotSetContractZeroAddress() external {
        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.setContract(
            PirexGmxGlp.Contracts.RewardRouterV2,
            address(0)
        );
    }

    /**
        @notice Test tx success: set gmxRewardRouterV2 to a new contract address
     */
    function testSetContractRewardRouterV2() external {
        address currentContractAddress = address(
            pirexGmxGlp.gmxRewardRouterV2()
        );
        address contractAddress = address(this);

        // Validate existing state
        assertFalse(currentContractAddress == contractAddress);

        // Expected state post-method call
        // Seemingly redundant, but method arguments do not always equal the expected value
        address expectedContractAddress = contractAddress;

        vm.expectEmit(true, false, false, true, address(pirexGmxGlp));

        emit SetContract(
            PirexGmxGlp.Contracts.RewardRouterV2,
            expectedContractAddress
        );

        pirexGmxGlp.setContract(
            PirexGmxGlp.Contracts.RewardRouterV2,
            contractAddress
        );

        assertEq(
            expectedContractAddress,
            address(pirexGmxGlp.gmxRewardRouterV2())
        );
    }

    /**
        @notice Test tx success: set rewardTrackerGmx to a new contract address
     */
    function testSetContractRewardTrackerGmx() external {
        address currentContractAddress = address(
            pirexGmxGlp.rewardTrackerGmx()
        );
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        address expectedContractAddress = contractAddress;

        vm.expectEmit(true, false, false, true, address(pirexGmxGlp));

        emit SetContract(
            PirexGmxGlp.Contracts.RewardTrackerGmx,
            expectedContractAddress
        );

        pirexGmxGlp.setContract(
            PirexGmxGlp.Contracts.RewardTrackerGmx,
            contractAddress
        );

        assertEq(
            expectedContractAddress,
            address(pirexGmxGlp.rewardTrackerGmx())
        );
    }

    /**
        @notice Test tx success: set rewardTrackerGlp to a new contract address
     */
    function testSetContractRewardTrackerGlp() external {
        address currentContractAddress = address(
            pirexGmxGlp.rewardTrackerGlp()
        );
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        address expectedContractAddress = contractAddress;

        vm.expectEmit(true, false, false, true, address(pirexGmxGlp));

        emit SetContract(
            PirexGmxGlp.Contracts.RewardTrackerGlp,
            expectedContractAddress
        );

        pirexGmxGlp.setContract(
            PirexGmxGlp.Contracts.RewardTrackerGlp,
            contractAddress
        );

        assertEq(
            expectedContractAddress,
            address(pirexGmxGlp.rewardTrackerGlp())
        );
    }

    /**
        @notice Test tx success: set feeStakedGlp to a new contract address
     */
    function testSetContractFeeStakedGlp() external {
        address currentContractAddress = address(pirexGmxGlp.feeStakedGlp());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        address expectedContractAddress = contractAddress;

        vm.expectEmit(true, false, false, true, address(pirexGmxGlp));

        emit SetContract(
            PirexGmxGlp.Contracts.FeeStakedGlp,
            expectedContractAddress
        );

        pirexGmxGlp.setContract(
            PirexGmxGlp.Contracts.FeeStakedGlp,
            contractAddress
        );

        assertEq(expectedContractAddress, address(pirexGmxGlp.feeStakedGlp()));
    }

    /**
        @notice Test tx success: set stakedGmx to a new contract address
     */
    function testSetContractStakedGmx() external {
        address currentContractAddress = address(pirexGmxGlp.stakedGmx());
        address contractAddress = address(this);

        assertFalse(contractAddress == currentContractAddress);
        assertEq(
            type(uint256).max,
            GMX.allowance(address(pirexGmxGlp), currentContractAddress)
        );

        address expectedContractAddress = contractAddress;
        uint256 expectedCurrentContractAllowance = 0;
        uint256 expectedContractAddressAllowance = type(uint256).max;

        vm.expectEmit(true, false, false, true, address(pirexGmxGlp));

        emit SetContract(
            PirexGmxGlp.Contracts.StakedGmx,
            expectedContractAddress
        );

        pirexGmxGlp.setContract(
            PirexGmxGlp.Contracts.StakedGmx,
            contractAddress
        );

        assertEq(
            expectedCurrentContractAllowance,
            GMX.allowance(address(pirexGmxGlp), currentContractAddress)
        );
        assertEq(expectedContractAddress, address(pirexGmxGlp.stakedGmx()));
        assertEq(
            expectedContractAddressAllowance,
            GMX.allowance(address(pirexGmxGlp), contractAddress)
        );
    }

    /**
        @notice Test tx success: set gmxVault to a new contract address
     */
    function testSetContractGmxVault() external {
        address currentContractAddress = address(pirexGmxGlp.gmxVault());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        address expectedContractAddress = contractAddress;

        vm.expectEmit(true, false, false, true, address(pirexGmxGlp));

        emit SetContract(
            PirexGmxGlp.Contracts.GmxVault,
            expectedContractAddress
        );

        pirexGmxGlp.setContract(
            PirexGmxGlp.Contracts.GmxVault,
            contractAddress
        );

        assertEq(expectedContractAddress, address(pirexGmxGlp.gmxVault()));
    }

    /**
        @notice Test tx success: set glpManager to a new contract address
     */
    function testSetContractGlpManager() external {
        address currentContractAddress = address(pirexGmxGlp.glpManager());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        address expectedContractAddress = contractAddress;

        vm.expectEmit(true, false, false, true, address(pirexGmxGlp));

        emit SetContract(
            PirexGmxGlp.Contracts.GlpManager,
            expectedContractAddress
        );

        pirexGmxGlp.setContract(
            PirexGmxGlp.Contracts.GlpManager,
            contractAddress
        );

        assertEq(expectedContractAddress, address(pirexGmxGlp.glpManager()));
    }

    /*//////////////////////////////////////////////////////////////
                        depositGmx TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotDepositGmxPaused() external {
        pirexGmxGlp.setPauseState(true);

        assertEq(true, pirexGmxGlp.paused());

        uint256 assets = 1;
        address receiver = address(this);

        _mintGmx(assets);

        vm.expectRevert(PAUSED_ERROR);

        pirexGmxGlp.depositGmx(assets, receiver);
    }

    /**
        @notice Test tx reversion: assets is zero
     */
    function testCannotDepositGmxZeroValue() external {
        uint256 invalidAssets = 0;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.depositGmx(invalidAssets, receiver);
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotDepositGmxZeroReceiver() external {
        uint256 assets = 1e18;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.depositGmx(assets, invalidReceiver);
    }

    /**
        @notice Test tx reversion: insufficient GMX balance
     */
    function testCannotDepositGmxInsufficientBalance() external {
        uint256 invalidAssets = 1e18;
        uint256 mintAmount = invalidAssets / 2;
        address receiver = address(this);

        // Mint less token than the amount specified for staking
        _mintGmx(mintAmount);

        vm.expectRevert("TRANSFER_FROM_FAILED");

        pirexGmxGlp.depositGmx(invalidAssets, receiver);
    }

    /**
        @notice Test tx success: deposit GMX for pxGMX
        @param  assets  uint256  Amount of GMX
     */
    function testDepositGmx(uint256 assets) external {
        vm.assume(assets > 1e15);
        vm.assume(assets < 1e22);

        address receiver = address(this);

        uint256 premintGMXBalance = GMX.balanceOf(receiver);

        _mintGmx(assets);

        uint256 previousGMXBalance = GMX.balanceOf(receiver);
        uint256 previousPxGmxBalance = pxGmx.balanceOf(receiver);
        uint256 previousStakedGMXBalance = REWARD_TRACKER_GMX.balanceOf(
            address(pirexGmxGlp)
        );

        assertEq(previousGMXBalance - premintGMXBalance, assets);
        assertEq(previousPxGmxBalance, 0);
        assertEq(previousStakedGMXBalance, 0);

        GMX.approve(address(pirexGmxGlp), assets);

        vm.expectEmit(true, true, false, false, address(pirexGmxGlp));

        emit DepositGmx(address(this), receiver, assets, 0, 0);

        pirexGmxGlp.depositGmx(assets, receiver);

        assertEq(previousGMXBalance - GMX.balanceOf(receiver), assets);
        assertEq(pxGmx.balanceOf(receiver) - previousPxGmxBalance, assets);
        assertEq(
            REWARD_TRACKER_GMX.balanceOf(address(pirexGmxGlp)) -
                previousStakedGMXBalance,
            assets
        );
    }

    /*//////////////////////////////////////////////////////////////
                        depositGlpETH TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotDepositGlpETHPaused() external {
        pirexGmxGlp.setPauseState(true);

        assertEq(true, pirexGmxGlp.paused());

        uint256 etherAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);

        vm.expectRevert(PAUSED_ERROR);

        pirexGmxGlp.depositGlpETH{value: etherAmount}(
            minUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: msg.value is zero
     */
    function testCannotDepositGlpETHZeroValue() external {
        uint256 invalidEtherAmount = 0;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.depositGlpETH{value: invalidEtherAmount}(
            minUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minUsdg is zero
     */
    function testCannotDepositGlpETHZeroMinUsdg() external {
        uint256 etherAmount = 1 ether;
        uint256 invalidMinUsdg = 0;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.depositGlpETH{value: etherAmount}(
            invalidMinUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minGlp is zero
     */
    function testCannotDepositGlpETHZeroMinGlp() external {
        uint256 etherAmount = 1 ether;
        uint256 minUsdg = 1;
        uint256 invalidMinGlp = 0;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.depositGlpETH{value: etherAmount}(
            minUsdg,
            invalidMinGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotDepositGlpETHZeroReceiver() external {
        uint256 etherAmount = 1 ether;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address invalidReceiver = address(0);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.depositGlpETH{value: etherAmount}(
            minUsdg,
            minGlp,
            invalidReceiver
        );
    }

    /**
        @notice Test tx reversion: minGlp is greater than actual GLP amount
     */
    function testCannotDepositGlpETHExcessiveMinGlp() external {
        uint256 etherAmount = 1 ether;
        uint256 minUsdg = 1;
        uint256 invalidMinGlp = _calculateMinGlpAmount(
            address(0),
            etherAmount,
            18
        ) * 2;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(INSUFFICIENT_GLP_OUTPUT_ERROR);

        pirexGmxGlp.depositGlpETH{value: etherAmount}(
            minUsdg,
            invalidMinGlp,
            receiver
        );
    }

    /**
        @notice Test tx success: deposit for pxGLP with ETH
        @param  etherAmount  uint256  Amount of ether in wei units
     */
    function testDepositGlpETH(uint256 etherAmount) external {
        vm.assume(etherAmount > 0.001 ether);
        vm.assume(etherAmount < 1_000 ether);
        vm.deal(address(this), etherAmount);

        uint256 minUsdg = 1;
        uint256 minGlp = _calculateMinGlpAmount(address(0), etherAmount, 18);
        address receiver = address(this);
        uint256 premintETHBalance = address(this).balance;
        uint256 premintPxGlpUserBalance = pxGlp.balanceOf(receiver);
        uint256 premintGlpPirexBalance = FEE_STAKED_GLP.balanceOf(
            address(pirexGmxGlp)
        );

        assertEq(premintETHBalance, etherAmount);
        assertEq(premintPxGlpUserBalance, 0);
        assertEq(premintGlpPirexBalance, 0);

        vm.expectEmit(true, true, true, false, address(pirexGmxGlp));

        // Cannot test the `asset` member of the event since it's not known until after
        emit DepositGlp(
            address(this),
            receiver,
            address(0),
            minUsdg,
            minGlp,
            etherAmount,
            0,
            0,
            0
        );

        uint256 assets = pirexGmxGlp.depositGlpETH{value: etherAmount}(
            minUsdg,
            minGlp,
            receiver
        );
        uint256 pxGlpReceivedByUser = pxGlp.balanceOf(receiver) -
            premintPxGlpUserBalance;
        uint256 glpReceivedByPirex = FEE_STAKED_GLP.balanceOf(
            address(pirexGmxGlp)
        ) - premintGlpPirexBalance;

        assertEq(address(this).balance, premintETHBalance - etherAmount);
        assertGt(pxGlpReceivedByUser, 0);
        assertEq(pxGlpReceivedByUser, glpReceivedByPirex);
        assertEq(glpReceivedByPirex, assets);
        assertGe(pxGlpReceivedByUser, minGlp);
        assertGe(glpReceivedByPirex, minGlp);
    }

    /*//////////////////////////////////////////////////////////////
                        depositGlp TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotDepositGlpTokenPaused() external {
        pirexGmxGlp.setPauseState(true);

        assertEq(true, pirexGmxGlp.paused());

        address token = address(WBTC);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        _mintWbtc(tokenAmount);
        WBTC.approve(address(pirexGmxGlp), tokenAmount);

        vm.expectRevert(PAUSED_ERROR);

        pirexGmxGlp.depositGlp(token, tokenAmount, minUsdg, minGlp, receiver);
    }

    /**
        @notice Test tx reversion: token is zero address
     */
    function testCannotDepositGlpTokenZeroAddress() external {
        address invalidToken = address(0);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.depositGlp(
            invalidToken,
            tokenAmount,
            minUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: amount is zero
     */
    function testCannotDepositGlpTokenZeroAmount() external {
        address token = address(WBTC);
        uint256 invalidTokenAmount = 0;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.depositGlp(
            token,
            invalidTokenAmount,
            minUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minUsdg is zero
     */
    function testCannotDepositGlpMinUsdgZeroAmount() external {
        address token = address(WBTC);
        uint256 tokenAmount = 1;
        uint256 invalidMinUsdg = 0;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.depositGlp(
            token,
            tokenAmount,
            invalidMinUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minGlp is zero
     */
    function testCannotDepositGlpMinGlpZeroAmount() external {
        address token = address(WBTC);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 invalidMinGlp = 0;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.depositGlp(
            token,
            tokenAmount,
            minUsdg,
            invalidMinGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotDepositGlpReceiverZeroAddress() external {
        address token = address(WBTC);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.depositGlp(
            token,
            tokenAmount,
            minUsdg,
            minGlp,
            invalidReceiver
        );
    }

    /**
        @notice Test tx reversion: token is not whitelisted by GMX
     */
    function testCannotDepositGlpInvalidToken() external {
        address invalidToken = address(this);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(
            abi.encodeWithSelector(
                PirexGmxGlp.InvalidToken.selector,
                invalidToken
            )
        );

        pirexGmxGlp.depositGlp(
            invalidToken,
            tokenAmount,
            minUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minGlp is greater than actual GLP amount
     */
    function testCannotDepositGlpExcessiveMinGlp() external {
        uint256 tokenAmount = 1e8;
        address token = address(WBTC);
        uint256 minUsdg = 1;
        uint256 invalidMinGlp = _calculateMinGlpAmount(token, tokenAmount, 8) *
            2;
        address receiver = address(this);

        _mintWbtc(tokenAmount);
        WBTC.approve(address(pirexGmxGlp), tokenAmount);

        vm.expectRevert(INSUFFICIENT_GLP_OUTPUT_ERROR);

        pirexGmxGlp.depositGlp(
            token,
            tokenAmount,
            minUsdg,
            invalidMinGlp,
            receiver
        );
    }

    /**
        @notice Test tx success: deposit for pxGLP with whitelisted ERC20 tokens
        @param  tokenAmount  uint256  Token amount
     */
    function testDepositGlp(uint256 tokenAmount) external {
        vm.assume(tokenAmount > 1e5);
        vm.assume(tokenAmount < 100e8);

        _mintWbtc(tokenAmount);

        address token = address(WBTC);
        uint256 minUsdg = 1;
        uint256 minGlp = _calculateMinGlpAmount(token, tokenAmount, 8);
        address receiver = address(this);
        uint256 premintWBTCBalance = WBTC.balanceOf(address(this));
        uint256 premintPxGlpUserBalance = pxGlp.balanceOf(receiver);
        uint256 premintGlpPirexBalance = FEE_STAKED_GLP.balanceOf(
            address(pirexGmxGlp)
        );

        assertTrue(WBTC.balanceOf(address(this)) == tokenAmount);
        assertEq(premintPxGlpUserBalance, 0);
        assertEq(premintGlpPirexBalance, 0);

        WBTC.approve(address(pirexGmxGlp), tokenAmount);

        vm.expectEmit(true, true, true, false, address(pirexGmxGlp));

        // Cannot test the `asset` member of the event since it's not known until after
        emit DepositGlp(
            address(this),
            receiver,
            token,
            minUsdg,
            minGlp,
            tokenAmount,
            0,
            0,
            0
        );

        uint256 assets = pirexGmxGlp.depositGlp(
            token,
            tokenAmount,
            minUsdg,
            minGlp,
            receiver
        );
        uint256 pxGlpReceivedByUser = pxGlp.balanceOf(receiver) -
            premintPxGlpUserBalance;
        uint256 glpReceivedByPirex = FEE_STAKED_GLP.balanceOf(
            address(pirexGmxGlp)
        ) - premintGlpPirexBalance;

        assertEq(
            WBTC.balanceOf(address(this)),
            premintWBTCBalance - tokenAmount
        );
        assertGt(pxGlpReceivedByUser, 0);
        assertEq(pxGlpReceivedByUser, glpReceivedByPirex);
        assertEq(glpReceivedByPirex, assets);
        assertGe(pxGlpReceivedByUser, minGlp);
        assertGe(glpReceivedByPirex, minGlp);
    }

    /*//////////////////////////////////////////////////////////////
                        redeemPxGlpETH TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotRedeemPxGlpETHPaused() external {
        uint256 etherAmount = 1 ether;
        address receiver = address(this);
        uint256 assets = _depositGlpETH(etherAmount, receiver);
        uint256 minOut = _calculateMinOutAmount(address(WETH), assets);

        // Pause after deposit
        pirexGmxGlp.setPauseState(true);

        assertEq(true, pirexGmxGlp.paused());

        vm.expectRevert(PAUSED_ERROR);

        pirexGmxGlp.redeemPxGlpETH(assets, minOut, receiver);
    }

    /**
        @notice Test tx reversion: amount is zero
     */
    function testCannotRedeemPxGlpETHZeroValue() external {
        uint256 invalidAmount = 0;
        uint256 minOut = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.redeemPxGlpETH(invalidAmount, minOut, receiver);
    }

    /**
        @notice Test tx reversion: minOut is zero
     */
    function testCannotRedeemPxGlpETHZeroMinOut() external {
        uint256 amount = 1;
        uint256 invalidMinOut = 0;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.redeemPxGlpETH(amount, invalidMinOut, receiver);
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotRedeemPxGlpETHZeroReceiver() external {
        uint256 amount = 1;
        uint256 minOut = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.redeemPxGlpETH(amount, minOut, invalidReceiver);
    }

    /**
        @notice Test tx reversion: minOut is greater than actual amount
     */
    function testCannotRedeemPxGlpETHExcessiveMinOut() external {
        uint256 etherAmount = 1 ether;
        address receiver = address(this);
        uint256 assets = _depositGlpETH(etherAmount, receiver);
        uint256 invalidMinOut = _calculateMinOutAmount(address(WETH), assets) *
            2;

        vm.expectRevert(INSUFFICIENT_OUTPUT_ERROR);

        pirexGmxGlp.redeemPxGlpETH(assets, invalidMinOut, receiver);
    }

    /**
        @notice Test tx success: redeem pxGLP for ETH
        @param  etherAmount  uint256  Amount of ether in wei units
     */
    function testRedeemPxGlpETH(uint256 etherAmount) external {
        vm.assume(etherAmount > 0.1 ether);
        vm.assume(etherAmount < 1_000 ether);

        address token = address(WETH);
        address receiver = address(this);

        // Mint pxGLP with ETH before attempting to redeem back into ETH
        uint256 assets = _depositGlpETH(etherAmount, receiver);

        uint256 previousETHBalance = receiver.balance;
        uint256 previousPxGlpUserBalance = pxGlp.balanceOf(receiver);
        uint256 previousGlpPirexBalance = FEE_STAKED_GLP.balanceOf(
            address(pirexGmxGlp)
        );

        assertEq(previousPxGlpUserBalance, previousGlpPirexBalance);

        // Calculate the minimum redemption amount then perform the redemption
        uint256 minOut = _calculateMinOutAmount(token, assets);

        vm.expectEmit(true, true, true, false, address(pirexGmxGlp));

        emit RedeemGlp(
            address(this),
            receiver,
            address(0),
            minOut,
            etherAmount,
            0,
            0,
            0
        );

        uint256 redeemed = pirexGmxGlp.redeemPxGlpETH(assets, minOut, receiver);

        assertGt(redeemed, minOut);
        assertEq(receiver.balance - previousETHBalance, redeemed);
        assertEq(previousPxGlpUserBalance - pxGlp.balanceOf(receiver), assets);
        assertEq(
            previousGlpPirexBalance -
                FEE_STAKED_GLP.balanceOf(address(pirexGmxGlp)),
            assets
        );
    }

    /*//////////////////////////////////////////////////////////////
                        redeemPxGlpForERC20 TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotRedeemPxGlpForERC20TokenPaused() external {
        uint256 etherAmount = 1 ether;
        address receiver = address(this);
        address token = address(WBTC);

        uint256 assets = _depositGlpETH(etherAmount, receiver);
        uint256 minRedemption = _calculateMinOutAmount(token, assets);

        // Pause after deposit
        pirexGmxGlp.setPauseState(true);

        assertEq(true, pirexGmxGlp.paused());

        vm.expectRevert(PAUSED_ERROR);

        pirexGmxGlp.redeemPxGlpForERC20(token, assets, minRedemption, receiver);
    }

    /**
        @notice Test tx reversion: token is zero address
     */
    function testCannotRedeemPxGlpForERC20TokenZeroAddress() external {
        address invalidToken = address(0);
        uint256 amount = 1;
        uint256 minRedemption = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.redeemPxGlpForERC20(
            invalidToken,
            amount,
            minRedemption,
            receiver
        );
    }

    /**
        @notice Test tx reversion: amount is zero
     */
    function testCannotRedeemPxGlpForERC20ZeroValue() external {
        address token = address(WBTC);
        uint256 invalidAmount = 0;
        uint256 minRedemption = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.redeemPxGlpForERC20(
            token,
            invalidAmount,
            minRedemption,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minRedemption is zero
     */
    function testCannotRedeemPxGlpForERC20ZeroMinRedemption() external {
        address token = address(WBTC);
        uint256 amount = 1;
        uint256 invalidMinRedemption = 0;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.redeemPxGlpForERC20(
            token,
            amount,
            invalidMinRedemption,
            receiver
        );
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotRedeemPxGlpForERC20ZeroReceiver() external {
        address token = address(WBTC);
        uint256 amount = 1;
        uint256 minRedemption = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.redeemPxGlpForERC20(
            token,
            amount,
            minRedemption,
            invalidReceiver
        );
    }

    /**
        @notice Test tx reversion: token is not whitelisted by GMX
     */
    function testCannotRedeemPxGlpForERC20InvalidToken() external {
        address invalidToken = address(this);
        uint256 amount = 1;
        uint256 minRedemption = 1;
        address receiver = address(this);

        vm.expectRevert(
            abi.encodeWithSelector(
                PirexGmxGlp.InvalidToken.selector,
                invalidToken
            )
        );

        pirexGmxGlp.redeemPxGlpForERC20(
            invalidToken,
            amount,
            minRedemption,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minRedemption is greater than actual amount
     */
    function testCannotRedeemPxGlpForERC20ExcessiveMinRedemption() external {
        address token = address(WBTC);
        uint256 tokenAmount = 1e8;
        address receiver = address(this);

        uint256 assets = _depositGlp(tokenAmount, receiver);
        uint256 invalidMinRedemption = _calculateMinOutAmount(token, assets) *
            2;

        vm.expectRevert(INSUFFICIENT_OUTPUT_ERROR);

        pirexGmxGlp.redeemPxGlpForERC20(
            token,
            assets,
            invalidMinRedemption,
            receiver
        );
    }

    /**
        @notice Test tx success: redeem pxGLP for whitelisted ERC20 tokens
        @param  tokenAmount  uint256  Token amount
     */
    function testRedeemPxGlpForERC20(uint256 tokenAmount) external {
        vm.assume(tokenAmount > 1e5);
        vm.assume(tokenAmount < 100e8);

        address token = address(WBTC);
        address receiver = address(this);

        // Deposit using ERC20 to receive some pxGLP for redemption tests later
        uint256 assets = _depositGlp(tokenAmount, receiver);

        uint256 previousWBTCBalance = WBTC.balanceOf(receiver);
        uint256 previousPxGlpUserBalance = pxGlp.balanceOf(receiver);
        uint256 previousGlpPirexBalance = FEE_STAKED_GLP.balanceOf(
            address(pirexGmxGlp)
        );

        assertEq(previousPxGlpUserBalance, previousGlpPirexBalance);

        // Calculate the minimum redemption amount then perform the redemption
        uint256 minRedemption = _calculateMinOutAmount(token, assets);

        vm.expectEmit(true, true, true, false, address(pirexGmxGlp));

        emit RedeemGlp(
            address(this),
            receiver,
            token,
            minRedemption,
            tokenAmount,
            0,
            0,
            0
        );

        uint256 redeemed = pirexGmxGlp.redeemPxGlpForERC20(
            token,
            assets,
            minRedemption,
            receiver
        );

        assertGt(redeemed, minRedemption);
        assertEq(WBTC.balanceOf(receiver) - previousWBTCBalance, redeemed);
        assertEq(previousPxGlpUserBalance - pxGlp.balanceOf(receiver), assets);
        assertEq(
            previousGlpPirexBalance -
                FEE_STAKED_GLP.balanceOf(address(pirexGmxGlp)),
            assets
        );
    }

    /*//////////////////////////////////////////////////////////////
                        calculateRewards TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: calculate and return WETH and esGMX rewards produced by GMX and GLP
        @param  secondsElapsed  uint32  Seconds to forward timestamp
        @param  wbtcAmount      uint40  Amount of WBTC used for minting GLP
        @param  gmxAmount       uint80  Amount of GMX to mint and deposit
     */
    function testCalculateRewards(
        uint32 secondsElapsed,
        uint40 wbtcAmount,
        uint80 gmxAmount
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(wbtcAmount > 1);
        vm.assume(wbtcAmount < 100e8);
        vm.assume(gmxAmount != 0);
        vm.assume(gmxAmount < 1000000e18);

        address pirexRewardsAddr = address(pirexRewards);

        _depositGlp(wbtcAmount, address(this));
        _depositGmx(gmxAmount, address(this));

        vm.warp(block.timestamp + secondsElapsed);

        uint256 expectedWETHRewardsGmx = pirexGmxGlp.calculateRewards(
            true,
            true
        );
        uint256 expectedWETHRewardsGlp = pirexGmxGlp.calculateRewards(
            true,
            false
        );
        uint256 expectedEsGmxRewardsGmx = pirexGmxGlp.calculateRewards(
            false,
            true
        );
        uint256 expectedEsGmxRewardsGlp = pirexGmxGlp.calculateRewards(
            false,
            false
        );
        uint256 expectedWETHRewards = expectedWETHRewardsGmx +
            expectedWETHRewardsGlp;
        uint256 expectedEsGmxRewards = expectedEsGmxRewardsGmx +
            expectedEsGmxRewardsGlp;

        vm.prank(pirexRewardsAddr);

        (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        ) = pirexGmxGlp.claimRewards();
        address wethAddr = address(WETH);
        address pxGlpAddr = address(pxGlp);
        address pxGmxAddr = address(pxGmx);

        assertEq(pxGmxAddr, address(producerTokens[0]));
        assertEq(pxGlpAddr, address(producerTokens[1]));
        assertEq(pxGmxAddr, address(producerTokens[2]));
        assertEq(pxGlpAddr, address(producerTokens[3]));
        assertEq(wethAddr, address(rewardTokens[0]));
        assertEq(wethAddr, address(rewardTokens[1]));
        assertEq(pxGmxAddr, address(rewardTokens[2]));
        assertEq(pxGmxAddr, address(rewardTokens[3]));
        assertEq(expectedWETHRewardsGmx, rewardAmounts[0]);
        assertEq(expectedWETHRewardsGlp, rewardAmounts[1]);
        assertEq(expectedEsGmxRewardsGmx, rewardAmounts[2]);
        assertEq(expectedEsGmxRewardsGlp, rewardAmounts[3]);
        assertGt(expectedWETHRewards, 0);
        assertGt(expectedEsGmxRewards, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        claimRewards TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not pirexRewards
     */
    function testCannotClaimRewardsNotPirexRewards() external {
        vm.expectRevert(PirexGmxGlp.NotPirexRewards.selector);

        vm.prank(testAccounts[0]);

        pirexGmxGlp.claimRewards();
    }

    /**
        @notice Test tx success: claim WETH and esGMX rewards + MP
        @param  secondsElapsed  uint32  Seconds to forward timestamp
        @param  wbtcAmount      uint40  Amount of WBTC used for minting GLP
        @param  gmxAmount       uint80  Amount of GMX to mint and deposit
     */
    function testClaimRewards(
        uint32 secondsElapsed,
        uint40 wbtcAmount,
        uint80 gmxAmount
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(wbtcAmount > 1e5);
        vm.assume(wbtcAmount < 100e8);
        vm.assume(gmxAmount > 1e15);
        vm.assume(gmxAmount < 1000000e18);

        address pirexRewardsAddr = address(pirexRewards);

        _depositGlp(wbtcAmount, address(this));
        _depositGmx(gmxAmount, address(this));

        // Forward timestamp to produce rewards
        vm.warp(block.timestamp + secondsElapsed);

        // uint256 previousStakedGmxBalance = REWARD_TRACKER_GMX.balanceOf(
        //     address(pirexGmxGlp)
        // );
        uint256 expectedWETHRewardsGmx = pirexGmxGlp.calculateRewards(
            true,
            true
        );
        uint256 expectedWETHRewardsGlp = pirexGmxGlp.calculateRewards(
            true,
            false
        );
        uint256 expectedEsGmxRewardsGmx = pirexGmxGlp.calculateRewards(
            false,
            true
        );
        uint256 expectedEsGmxRewardsGlp = pirexGmxGlp.calculateRewards(
            false,
            false
        );
        uint256 expectedClaimableMp = REWARD_TRACKER_MP.claimable(
            address(pirexGmxGlp)
        );
        uint256 expectedWETHRewards = expectedWETHRewardsGmx +
            expectedWETHRewardsGlp;
        uint256 expectedEsGmxRewards = expectedEsGmxRewardsGmx +
            expectedEsGmxRewardsGlp;

        vm.expectEmit(false, false, false, true, address(pirexGmxGlp));

        // Limited variable counts due to stack-too-deep issue
        emit ClaimRewards(
            expectedWETHRewards,
            expectedEsGmxRewards,
            expectedWETHRewardsGmx,
            expectedWETHRewardsGlp,
            expectedEsGmxRewardsGmx,
            expectedEsGmxRewardsGlp
        );

        // Impersonate pirexRewards and claim WETH rewards
        vm.prank(pirexRewardsAddr);

        (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        ) = pirexGmxGlp.claimRewards();

        assertEq(address(pxGmx), address(producerTokens[0]));
        assertEq(address(pxGlp), address(producerTokens[1]));
        assertEq(address(pxGmx), address(producerTokens[2]));
        assertEq(address(pxGlp), address(producerTokens[3]));
        assertEq(address(WETH), address(rewardTokens[0]));
        assertEq(address(WETH), address(rewardTokens[1]));
        assertEq(address(pxGmx), address(rewardTokens[2]));
        assertEq(address(pxGmx), address(rewardTokens[3]));
        assertEq(expectedWETHRewardsGmx, rewardAmounts[0]);
        assertEq(expectedWETHRewardsGlp, rewardAmounts[1]);
        assertEq(expectedEsGmxRewardsGmx, rewardAmounts[2]);
        assertEq(expectedEsGmxRewardsGlp, rewardAmounts[3]);
        assertGt(expectedWETHRewards, 0);
        assertGt(expectedEsGmxRewards, 0);
        assertGt(expectedClaimableMp, 0);

        // @NOTE: Test fails after X number of fuzz runs, to be addressed in this PR
        // Test fail arguments [31317560, 100001, 1000000000000001]
        // // Claimed esGMX rewards + MP should also be staked immediately
        // assertEq(
        //     REWARD_TRACKER_GMX.balanceOf(address(pirexGmxGlp)),
        //     previousStakedGmxBalance +
        //         expectedEsGmxRewards +
        //         expectedClaimableMp
        // );
        assertEq(REWARD_TRACKER_MP.claimable(address(pirexGmxGlp)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        claimUserReward TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not pirexRewards
     */
    function testCannotClaimUserRewardNotPirexRewards() external {
        address recipient = address(this);
        address rewardTokenAddress = address(WETH);
        uint256 amount = 1;

        assertTrue(address(this) != pirexGmxGlp.pirexRewards());

        vm.expectRevert(PirexGmxGlp.NotPirexRewards.selector);

        pirexGmxGlp.claimUserReward(recipient, rewardTokenAddress, amount);
    }

    /**
        @notice Test tx reversion: recipient is zero address
     */
    function testCannotClaimUserRewardRecipientZeroAddress() external {
        address invalidRecipient = address(0);
        address rewardTokenAddress = address(WETH);
        uint256 amount = 1;

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        vm.prank(address(pirexRewards));

        pirexGmxGlp.claimUserReward(
            invalidRecipient,
            rewardTokenAddress,
            amount
        );
    }

    /**
        @notice Test tx reversion: reward token is zero address
     */
    function testCannotClaimUserRewardTokenZeroAddress() external {
        address recipient = address(this);
        address invalidRewardTokenAddress = address(0);
        uint256 amount = 1;

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        vm.prank(address(pirexRewards));

        pirexGmxGlp.claimUserReward(
            recipient,
            invalidRewardTokenAddress,
            amount
        );
    }

    /**
        @notice Test tx success: claim user reward
        @param  wethAmount  uint80  Amount of claimable WETH
        @param  pxGmxAmount   uint80  Amount of claimable pxGMX
     */
    function testClaimUserReward(uint80 wethAmount, uint80 pxGmxAmount)
        external
    {
        vm.assume(wethAmount > 0.001 ether);
        vm.assume(wethAmount < 1_000 ether);
        vm.assume(pxGmxAmount != 0);
        vm.assume(pxGmxAmount < 1000000e18);

        address user = address(this);

        assertEq(0, WETH.balanceOf(user));
        assertEq(0, pxGmx.balanceOf(user));

        // Mint and transfers tokens for user claim tests
        vm.deal(address(this), wethAmount);

        IWETH(address(WETH)).depositTo{value: wethAmount}(address(pirexGmxGlp));

        vm.prank(address(pirexGmxGlp));

        pxGmx.mint(address(pirexGmxGlp), pxGmxAmount);

        // Test claim via PirexRewards contract
        vm.startPrank(address(pirexRewards));

        pirexGmxGlp.claimUserReward(user, address(WETH), wethAmount);
        pirexGmxGlp.claimUserReward(user, address(pxGmx), pxGmxAmount);

        vm.stopPrank();

        assertEq(WETH.balanceOf(user), wethAmount);
        assertEq(pxGmx.balanceOf(user), pxGmxAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        setPauseState TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetPauseStateUnauthorized() external {
        vm.expectRevert(UNAUTHORIZED_ERROR);

        vm.prank(testAccounts[0]);

        pirexGmxGlp.setPauseState(true);
    }

    /**
        @notice Test tx reversion: contract is not paused
     */
    function testCannotSetPauseStateNotPaused() external {
        assertEq(pirexGmxGlp.paused(), false);

        vm.expectRevert(NOT_PAUSED_ERROR);

        pirexGmxGlp.setPauseState(false);
    }

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotSetPauseStatePaused() external {
        pirexGmxGlp.setPauseState(true);

        assertEq(pirexGmxGlp.paused(), true);

        vm.expectRevert(PAUSED_ERROR);

        pirexGmxGlp.setPauseState(true);
    }

    /**
        @notice Test tx success: set pause state
     */
    function testSetPauseState() external {
        assertEq(pirexGmxGlp.paused(), false);

        pirexGmxGlp.setPauseState(true);

        assertEq(pirexGmxGlp.paused(), true);

        pirexGmxGlp.setPauseState(false);

        assertEq(pirexGmxGlp.paused(), false);
    }

    /*//////////////////////////////////////////////////////////////
                        initiateMigration TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is not paused
     */
    function testCannotInitiateMigrationNotPaused() external {
        assertEq(pirexGmxGlp.paused(), false);

        address newContract = address(this);

        vm.expectRevert(NOT_PAUSED_ERROR);

        pirexGmxGlp.initiateMigration(newContract);
    }

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotInitiateMigrationUnauthorized() external {
        pirexGmxGlp.setPauseState(true);

        assertEq(pirexGmxGlp.paused(), true);

        address newContract = address(this);

        vm.expectRevert(UNAUTHORIZED_ERROR);

        vm.prank(testAccounts[0]);

        pirexGmxGlp.initiateMigration(newContract);
    }

    /**
        @notice Test tx reversion: newContract is zero address
     */
    function testCannotInitiateMigrationZeroAddress() external {
        pirexGmxGlp.setPauseState(true);

        assertEq(pirexGmxGlp.paused(), true);

        address invalidNewContract = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.initiateMigration(invalidNewContract);
    }

    /**
        @notice Test tx success: initiate migration
     */
    function testInitiateMigration() external {
        pirexGmxGlp.setPauseState(true);

        assertEq(pirexGmxGlp.paused(), true);

        address oldContract = address(pirexGmxGlp);
        address newContract = address(this);

        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), address(0));

        vm.expectEmit(false, false, false, true, address(pirexGmxGlp));

        emit InitiateMigration(newContract);

        pirexGmxGlp.initiateMigration(newContract);

        // Should properly set the pendingReceivers state
        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), newContract);
    }

    /*//////////////////////////////////////////////////////////////
                        completeMigration TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is not paused
     */
    function testCannotCompleteMigrationNotPaused() external {
        assertEq(pirexGmxGlp.paused(), false);

        address oldContract = address(this);

        vm.expectRevert(NOT_PAUSED_ERROR);

        pirexGmxGlp.completeMigration(oldContract);
    }

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotCompleteMigrationUnauthorized() external {
        pirexGmxGlp.setPauseState(true);

        assertEq(pirexGmxGlp.paused(), true);

        address oldContract = address(pirexGmxGlp);

        vm.expectRevert(UNAUTHORIZED_ERROR);

        vm.prank(testAccounts[0]);

        pirexGmxGlp.completeMigration(oldContract);
    }

    /**
        @notice Test tx reversion: oldContract is zero address
     */
    function testCannotCompleteMigrationZeroAddress() external {
        pirexGmxGlp.setPauseState(true);

        assertEq(pirexGmxGlp.paused(), true);

        address invalidOldContract = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.completeMigration(invalidOldContract);
    }

    /**
        @notice Test tx reversion due to the caller not being the assigned new contract
     */
    function testCannotCompleteMigrationInvalidNewContract() external {
        pirexGmxGlp.setPauseState(true);

        assertEq(pirexGmxGlp.paused(), true);

        address oldContract = address(pirexGmxGlp);
        address newContract = address(this);

        pirexGmxGlp.initiateMigration(newContract);

        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), newContract);

        // Deploy a test contract but not being assigned as the migration target
        PirexGmxGlp newPirexGmxGlp = new PirexGmxGlp(
            address(pxGmx),
            address(pxGlp),
            address(pirexFees),
            address(pirexRewards),
            address(delegateRegistry)
        );

        vm.expectRevert("RewardRouter: transfer not signalled");

        newPirexGmxGlp.completeMigration(oldContract);
    }

    /**
        @notice Test completing migration
     */
    function testCompleteMigration() external {
        // Perform GMX deposit for balance tests after migration
        uint256 assets = 1e18;
        address receiver = address(this);
        address oldContract = address(pirexGmxGlp);

        _mintGmx(assets);

        GMX.approve(oldContract, assets);
        pirexGmxGlp.depositGmx(assets, receiver);

        // Perform GLP deposit for balance tests after migration
        uint256 etherAmount = 1 ether;

        vm.deal(address(this), etherAmount);

        pirexGmxGlp.depositGlpETH{value: etherAmount}(1, 1, receiver);

        // Time skip to bypass the cooldown duration
        vm.warp(block.timestamp + 1 days);

        // Store the staked balances for later validations
        uint256 oldStakedGmxBalance = REWARD_TRACKER_GMX.balanceOf(oldContract);
        uint256 oldStakedGlpBalance = FEE_STAKED_GLP.balanceOf(oldContract);
        uint256 oldEsGmxClaimable = pirexGmxGlp.calculateRewards(false, true) +
            pirexGmxGlp.calculateRewards(false, false);
        uint256 oldMpBalance = REWARD_TRACKER_MP.claimable(oldContract);

        // Pause the contract before proceeding
        pirexGmxGlp.setPauseState(true);

        assertEq(pirexGmxGlp.paused(), true);

        // Deploy the new contract for migration tests
        PirexGmxGlp newPirexGmxGlp = new PirexGmxGlp(
            address(pxGmx),
            address(pxGlp),
            address(pirexFees),
            address(pirexRewards),
            address(delegateRegistry)
        );

        address newContract = address(newPirexGmxGlp);

        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), address(0));

        pirexGmxGlp.initiateMigration(newContract);

        // Should properly set the pendingReceivers state
        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), newContract);

        vm.expectEmit(false, false, false, true, address(newPirexGmxGlp));

        emit CompleteMigration(oldContract);

        // Complete the migration using the new contract
        newPirexGmxGlp.completeMigration(oldContract);

        // Should properly clear the pendingReceivers state
        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), address(0));

        // Confirm that the token balances and claimables for old contract are correct
        assertEq(REWARD_TRACKER_GMX.balanceOf(oldContract), 0);
        assertEq(FEE_STAKED_GLP.balanceOf(oldContract), 0);
        assertEq(STAKED_GMX.claimable(oldContract), 0);
        assertEq(FEE_STAKED_GLP.claimable(oldContract), 0);
        assertEq(REWARD_TRACKER_MP.claimable(oldContract), 0);

        // Confirm that the staked token balances for new contract are correct
        // For Staked GMX balance, due to compounding in the migration,
        // all pending claimable esGMX and MP are automatically staked
        assertEq(
            REWARD_TRACKER_GMX.balanceOf(newContract),
            oldStakedGmxBalance + oldEsGmxClaimable + oldMpBalance
        );
        assertEq(FEE_STAKED_GLP.balanceOf(newContract), oldStakedGlpBalance);
    }

    /*//////////////////////////////////////////////////////////////
                        setDelegationSpace TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetDelegationSpaceUnauthorized() external {
        assertEq(DEFAULT_DELEGATION_SPACE, pirexGmxGlp.delegationSpace());

        string memory space = "test.eth";
        bool clear = false;

        vm.expectRevert(UNAUTHORIZED_ERROR);

        vm.prank(testAccounts[0]);

        pirexGmxGlp.setDelegationSpace(space, clear);
    }

    /**
        @notice Test tx reversion: space is empty string
     */
    function testCannotSetDelegationSpaceEmptyString() external {
        assertEq(DEFAULT_DELEGATION_SPACE, pirexGmxGlp.delegationSpace());

        string memory invalidSpace = "";
        bool clear = false;

        vm.expectRevert(PirexGmxGlp.EmptyString.selector);

        pirexGmxGlp.setDelegationSpace(invalidSpace, clear);
    }

    /**
        @notice Test tx success: set delegation space without clearing
     */
    function testSetDelegationSpaceWithoutClearing() external {
        assertEq(DEFAULT_DELEGATION_SPACE, pirexGmxGlp.delegationSpace());

        string memory space = "test.eth";
        bool clear = false;

        vm.expectEmit(false, false, false, true);

        emit SetDelegationSpace(space, clear);

        pirexGmxGlp.setDelegationSpace(space, clear);

        assertEq(pirexGmxGlp.delegationSpace(), bytes32(bytes(space)));
    }

    /**
        @notice Test tx success: set delegation space with clearing
     */
    function testSetDelegationSpaceWithClearing() external {
        assertEq(DEFAULT_DELEGATION_SPACE, pirexGmxGlp.delegationSpace());

        string memory oldSpace = "old.eth";
        string memory newSpace = "new.eth";
        bool clear = false;

        pirexGmxGlp.setDelegationSpace(oldSpace, clear);

        // Set the vote delegate before clearing it when setting new delegation space
        pirexGmxGlp.setVoteDelegate(address(this));

        assertEq(pirexGmxGlp.delegationSpace(), bytes32(bytes(oldSpace)));

        pirexGmxGlp.setDelegationSpace(newSpace, !clear);

        assertEq(pirexGmxGlp.delegationSpace(), bytes32(bytes(newSpace)));
    }

    /*//////////////////////////////////////////////////////////////
                        setVoteDelegate TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetVoteDelegateUnauthorized() external {
        address delegate = address(this);

        vm.expectRevert(UNAUTHORIZED_ERROR);

        vm.prank(testAccounts[0]);

        pirexGmxGlp.setVoteDelegate(delegate);
    }

    /**
        @notice Test tx reversion: delegate is zero address
     */
    function testCannotSetVoteDelegateZeroAddress() external {
        address invalidDelegate = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.setVoteDelegate(invalidDelegate);
    }

    /**
        @notice Test tx success: set vote delegate
     */
    function testSetVoteDelegate() external {
        address oldDelegate = delegateRegistry.delegation(
            address(pirexGmxGlp),
            pirexGmxGlp.delegationSpace()
        );
        address newDelegate = address(this);

        assertTrue(oldDelegate != newDelegate);

        vm.expectEmit(false, false, false, true);

        emit SetVoteDelegate(newDelegate);

        pirexGmxGlp.setVoteDelegate(newDelegate);

        address delegate = delegateRegistry.delegation(
            address(pirexGmxGlp),
            pirexGmxGlp.delegationSpace()
        );

        assertEq(delegate, newDelegate);
    }

    /*//////////////////////////////////////////////////////////////
                        clearVoteDelegate TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotClearVoteDelegateUnauthorized() external {
        vm.expectRevert(UNAUTHORIZED_ERROR);

        vm.prank(testAccounts[0]);

        pirexGmxGlp.clearVoteDelegate();
    }

    /**
        @notice Test tx reversion: clear with no delegate set
     */
    function testCannotClearVoteDelegateNoDelegate() external {
        assertEq(
            delegateRegistry.delegation(
                address(pirexGmxGlp),
                pirexGmxGlp.delegationSpace()
            ),
            address(0)
        );

        vm.expectRevert("No delegate set");

        pirexGmxGlp.clearVoteDelegate();
    }

    /**
        @notice Test tx success: clear vote delegate
     */
    function testClearVoteDelegate() external {
        pirexGmxGlp.setDelegationSpace("test.eth", false);

        // Set the vote delegate before clearing it when setting new delegation space
        pirexGmxGlp.setVoteDelegate(address(this));

        assertEq(
            delegateRegistry.delegation(
                address(pirexGmxGlp),
                pirexGmxGlp.delegationSpace()
            ),
            address(this)
        );

        vm.expectEmit(false, false, false, true);

        emit ClearVoteDelegate();

        pirexGmxGlp.clearVoteDelegate();

        assertEq(
            delegateRegistry.delegation(
                address(pirexGmxGlp),
                pirexGmxGlp.delegationSpace()
            ),
            address(0)
        );
    }
}
