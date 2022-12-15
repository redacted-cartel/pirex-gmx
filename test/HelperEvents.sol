// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexGmx} from "src/PirexGmx.sol";
import {PirexFees} from "src/PirexFees.sol";
import {RewardTracker} from "src/external/RewardTracker.sol";
import {IVault} from "src/external/GlpManager.sol";

contract HelperEvents {
    // PirexGmx events
    event InitializeGmxState(
        address indexed caller,
        RewardTracker rewardTrackerGmx,
        RewardTracker rewardTrackerGlp,
        RewardTracker feeStakedGlp,
        RewardTracker stakedGmx,
        address glpManager,
        IVault gmxVault
    );
    event SetFee(PirexGmx.Fees indexed f, uint256 fee);
    event SetContract(PirexGmx.Contracts indexed c, address contractAddress);
    event DepositGmx(
        address indexed caller,
        address indexed receiver,
        uint256 deposited,
        uint256 postFeeAmount,
        uint256 feeAmount
    );
    event DepositGlp(
        address indexed receiver,
        uint256 deposited,
        uint256 postFeeAmount,
        uint256 feeAmount
    );
    event RedeemGlp(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        uint256 assets,
        uint256 minOut,
        uint256 redemption,
        uint256 postFeeAmount,
        uint256 feeAmount
    );
    event ClaimRewards(
        uint256 wethRewards,
        uint256 esGmxRewards,
        uint256 gmxWethRewards,
        uint256 glpWethRewards,
        uint256 gmxEsGmxRewards,
        uint256 glpEsGmxRewards
    );
    event ClaimUserReward(
        address indexed receiver,
        address indexed token,
        uint256 amount,
        uint256 rewardAmount,
        uint256 feeAmount
    );
    event InitiateMigration(address newContract);
    event CompleteMigration(address oldContract);
    event SetDelegationSpace(string delegationSpace, bool shouldClear);
    event SetVoteDelegate(address voteDelegate);
    event ClearVoteDelegate();

    // PirexRewards events
    event SetProducer(address producer);
    event Claim(
        ERC20 indexed rewardToken,
        address indexed user,
        uint256 amount
    );
    event SetRewardRecipient(
        address indexed user,
        ERC20 indexed rewardToken,
        address indexed recipient
    );
    event UnsetRewardRecipient(address indexed user, ERC20 indexed rewardToken);
    event AccrueStrategy(bytes indexed strategy, uint256 accruedRewards);
    event AccrueRewards(
        bytes indexed strategy,
        address indexed user,
        uint256 rewardsDelta,
        uint256 rewardsIndex
    );
    event AddStrategy(bytes indexed newStrategy);

    // PirexFees events
    event SetFeeRecipient(PirexFees.FeeRecipient f, address recipient);
    event SetTreasuryFeePercent(uint8 _treasuryFeePercent);
    event DistributeFees(
        ERC20 indexed token,
        uint256 distribution,
        uint256 treasuryDistribution,
        uint256 contributorsDistribution
    );

    // PxERC20 events
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    // Shared Vault events
    event WithdrawalPenaltyUpdated(uint256 penalty);
    event PlatformFeeUpdated(uint256 fee);
    event CompoundIncentiveUpdated(uint256 incentive);
    event PlatformUpdated(address _platform);
}
