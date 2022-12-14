// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {Owned} from "solmate/auth/Owned.sol";

/**
    @notice Major thanks to the Fei protocol team 💚

    @notice Link to the unmodified source code
    https://raw.githubusercontent.com/fei-protocol/flywheel-v2/dbe3cb81a3dc2e46536bb8af9c2bdc585f63425e/src/FlywheelCore.sol

    @notice Pirex-GMX modifications
        - Replace Solmate Auth with Solmate Owned
        - Removed Flywheel rewards and booster modules
        - Hoist (in code) contract types and variables
*/
contract FeiFlywheelCoreV2 is Owned {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;

    struct RewardsState {
        /// @notice The strategy's last updated index
        uint224 index;
        /// @notice The timestamp the index was last updated at
        uint32 lastUpdatedTimestamp;
    }

    /// @notice the fixed point factor of flywheel
    uint224 public constant ONE = 1e18;

    /// @notice The token to reward
    ERC20 public immutable rewardToken;

    /// @notice append-only list of strategies added
    ERC20[] public allStrategies;

    /// @notice The strategy index and last updated per strategy
    mapping(ERC20 => RewardsState) public strategyState;

    /// @notice user index per strategy
    mapping(ERC20 => mapping(address => uint224)) public userIndex;

    /// @notice The accrued but not yet transferred rewards for each user
    mapping(address => uint256) public rewardsAccrued;

    /**
      @notice Emitted when a user's rewards accrue to a given strategy.
      @param strategy the updated rewards strategy
      @param user the user of the rewards
      @param rewardsDelta how many new rewards accrued to the user
      @param rewardsIndex the market index for rewards per token accrued
    */
    event AccrueRewards(
        ERC20 indexed strategy,
        address indexed user,
        uint256 rewardsDelta,
        uint256 rewardsIndex
    );

    /**
      @notice Emitted when a user claims accrued rewards.
      @param user the user of the rewards
      @param amount the amount of rewards claimed
    */
    event ClaimRewards(address indexed user, uint256 amount);

    /**
      @notice Emitted when a new strategy is added to flywheel by the admin
      @param newStrategy the new added strategy
    */
    event AddStrategy(address indexed newStrategy);

    constructor(ERC20 _rewardToken) Owned(msg.sender) {
        rewardToken = _rewardToken;
    }

    /*///////////////////////////////////////////////////////////////
                        ACCRUE/CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
      @notice accrue rewards for a single user on a strategy
      @param strategy the strategy to accrue a user's rewards on
      @param user the user to be accrued
      @return the cumulative amount of rewards accrued to user (including prior)
    */
    function accrue(
        ERC20 strategy,
        uint256 accruedRewards,
        address user
    ) public returns (uint256) {
        RewardsState memory state = strategyState[strategy];

        if (state.index == 0) return 0;

        state = accrueStrategy(strategy, state, accruedRewards);
        return accrueUser(strategy, user, state);
    }

    /**
      @notice accrue rewards for a two users on a strategy
      @param strategy the strategy to accrue a user's rewards on
      @param user the first user to be accrued
      @param user the second user to be accrued
      @return the cumulative amount of rewards accrued to the first user (including prior)
      @return the cumulative amount of rewards accrued to the second user (including prior)
    */
    function accrue(
        ERC20 strategy,
        uint256 accruedRewards,
        address user,
        address secondUser
    ) public returns (uint256, uint256) {
        RewardsState memory state = strategyState[strategy];

        if (state.index == 0) return (0, 0);

        state = accrueStrategy(strategy, state, accruedRewards);
        return (
            accrueUser(strategy, user, state),
            accrueUser(strategy, secondUser, state)
        );
    }

    /**
      @notice claim rewards for a given user
      @param user the user claiming rewards
      @dev this function is public, and all rewards transfer to the user
    */
    function claimRewards(address user) external {
        uint256 accrued = rewardsAccrued[user];

        if (accrued != 0) {
            rewardsAccrued[user] = 0;

            // TODO: Transfer rewards to user
            // rewardToken.safeTransferFrom(
            //     address(flywheelRewards),
            //     user,
            //     accrued
            // );

            emit ClaimRewards(user, accrued);
        }
    }

    /*///////////////////////////////////////////////////////////////
                          ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice initialize a new strategy
    function addStrategyForRewards(ERC20 strategy) external onlyOwner {
        _addStrategyForRewards(strategy);
    }

    function _addStrategyForRewards(ERC20 strategy) internal {
        require(strategyState[strategy].index == 0, "strategy");
        strategyState[strategy] = RewardsState({
            index: ONE,
            lastUpdatedTimestamp: block.timestamp.safeCastTo32()
        });

        allStrategies.push(strategy);
        emit AddStrategy(address(strategy));
    }

    function getAllStrategies() external view returns (ERC20[] memory) {
        return allStrategies;
    }

    /*///////////////////////////////////////////////////////////////
                    INTERNAL ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice accumulate global rewards on a strategy
    function accrueStrategy(
        ERC20 strategy,
        RewardsState memory state,
        uint256 accruedRewards
    ) private returns (RewardsState memory rewardsState) {
        rewardsState = state;

        if (accruedRewards > 0) {
            // use the booster or token supply to calculate reward index denominator
            uint256 supplyTokens = strategy.totalSupply();

            uint224 deltaIndex;

            if (supplyTokens != 0)
                deltaIndex = ((accruedRewards * ONE) / supplyTokens)
                    .safeCastTo224();

            // accumulate rewards per token onto the index, multiplied by fixed-point factor
            rewardsState = RewardsState({
                index: state.index + deltaIndex,
                lastUpdatedTimestamp: block.timestamp.safeCastTo32()
            });
            strategyState[strategy] = rewardsState;
        }
    }

    /// @notice accumulate rewards on a strategy for a specific user
    function accrueUser(
        ERC20 strategy,
        address user,
        RewardsState memory state
    ) private returns (uint256) {
        // load indices
        uint224 strategyIndex = state.index;
        uint224 supplierIndex = userIndex[strategy][user];

        // sync user index to global
        userIndex[strategy][user] = strategyIndex;

        // if user hasn't yet accrued rewards, grant them interest from the strategy beginning if they have a balance
        // zero balances will have no effect other than syncing to global index
        if (supplierIndex == 0) {
            supplierIndex = ONE;
        }

        uint224 deltaIndex = strategyIndex - supplierIndex;

        // accumulate rewards by multiplying user tokens by rewardsPerToken index and adding on unclaimed
        uint256 supplierDelta = (strategy.balanceOf(user) * deltaIndex) / ONE;
        uint256 supplierAccrued = rewardsAccrued[user] + supplierDelta;

        rewardsAccrued[user] = supplierAccrued;

        emit AccrueRewards(strategy, user, supplierDelta, strategyIndex);

        return supplierAccrued;
    }
}
