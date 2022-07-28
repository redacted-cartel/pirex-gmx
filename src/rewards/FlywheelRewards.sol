// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {FlywheelCore} from "./FlywheelCore.sol";

/**
    Original source code:
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/rewards/FlywheelStaticRewards.sol

    Modifications:
    - Pin pragma to 0.8.13
    - Modify code formatting and comment descriptions to be consistent with Pirex
    - Merge FlywheelRewards-related contract logic
*/
contract FlywheelRewards is AccessControl {
    using SafeTransferLib for ERC20;

    struct RewardsInfo {
        // Rewards per second
        uint224 rewardsPerSecond;
        // The timestamp the rewards end at (0 = no end)
        uint32 rewardsEndTimestamp;
    }

    // The reward token paid
    ERC20 public immutable rewardToken;

    // The flywheel core contract
    FlywheelCore public immutable flywheel;

    // Rewards info per strategy
    mapping(ERC20 => RewardsInfo) public rewardsInfo;

    event RewardsInfoUpdate(
        ERC20 indexed strategy,
        uint224 rewardsPerSecond,
        uint32 rewardsEndTimestamp
    );

    error FlywheelError();
    error ZeroAddress();

    /**
        @param  _flywheel  FlywheelCore  FlywheelCore contract
        @param  _owner     address       Owner address
    */
    constructor(FlywheelCore _flywheel, address _owner) {
        if (address(_flywheel) == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();

        flywheel = _flywheel;
        rewardToken = _flywheel.rewardToken();

        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        rewardToken.safeApprove(address(_flywheel), type(uint256).max);
    }

    modifier onlyFlywheel() {
        if (msg.sender != address(flywheel)) revert FlywheelError();

        _;
    }

    /**
        @notice Set rewards per second and rewards end time for Fei Rewards
        @param  strategy  ERC20        The strategy to accrue rewards for
        @param  rewards   RewardsInfo  The rewards info for the strategy
     */
    function setRewardsInfo(ERC20 strategy, RewardsInfo calldata rewards)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        rewardsInfo[strategy] = rewards;

        emit RewardsInfoUpdate(
            strategy,
            rewards.rewardsPerSecond,
            rewards.rewardsEndTimestamp
        );
    }

    /**
        @notice Calculate and transfer accrued rewards to flywheel core
        @param  strategy              ERC20    The strategy to accrue rewards for
        @param  lastUpdatedTimestamp  uint32   The last updated time for strategy
        @return amount                uint256  Amount of tokens accrued and transferred
     */
    function getAccruedRewards(ERC20 strategy, uint32 lastUpdatedTimestamp)
        external
        view
        onlyFlywheel
        returns (uint256 amount)
    {
        RewardsInfo memory rewards = rewardsInfo[strategy];
        uint256 elapsed;

        if (
            rewards.rewardsEndTimestamp == 0 ||
            rewards.rewardsEndTimestamp > block.timestamp
        ) {
            elapsed = block.timestamp - lastUpdatedTimestamp;
        } else if (rewards.rewardsEndTimestamp > lastUpdatedTimestamp) {
            elapsed = rewards.rewardsEndTimestamp - lastUpdatedTimestamp;
        }

        amount = rewards.rewardsPerSecond * elapsed;
    }
}