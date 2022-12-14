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
        - Remove access control and remove public-facing privileged methods
        - Removed Flywheel rewards and booster modules
        - Hoist (in code) contract types and variables
        - Update styling to conform with Pirex practices
        - Add function parameter validation and associated errors
        - Update strategy type to bytes (abi-encoded producer and reward ERC20-type contracts)
*/
contract FeiFlywheelCoreV2 {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;

    struct RewardsState {
        // The strategy's last updated index
        uint224 index;
        // The timestamp the index was last updated at
        uint32 lastUpdatedTimestamp;
    }

    // The fixed point factor of flywheel
    uint224 public constant ONE = 1e18;

    // Append-only list of strategies added
    bytes[] public allStrategies;

    // The strategy index and last updated per strategy
    mapping(bytes => RewardsState) public strategyState;

    // User index per strategy
    mapping(bytes => mapping(address => uint224)) public userIndex;

    // The accrued but not yet transferred rewards for each user
    mapping(address => uint256) public rewardsAccrued;

    /**
      @notice Emitted when a user's rewards accrue to a given strategy.
      @param  strategy      bytes    The updated rewards strategy
      @param  user          address  The user of the rewards
      @param  rewardsDelta  uint256  How many new rewards accrued to the user
      @param  rewardsIndex  uint256  The market index for rewards per token accrued
    */
    event AccrueRewards(
        bytes indexed strategy,
        address indexed user,
        uint256 rewardsDelta,
        uint256 rewardsIndex
    );

    /**
      @notice Emitted when a user claims accrued rewards.
      @param  user    address  The user of the rewards
      @param  amount  uint256  The amount of rewards claimed
    */
    event ClaimRewards(address indexed user, uint256 amount);

    /**
      @notice Emitted when a new strategy is added to flywheel by the admin
      @param  newStrategy  bytes  The new added strategy
    */
    event AddStrategy(bytes indexed newStrategy);

    error InvalidStrategy();
    error ZeroAddress();
    error StrategyAlreadySet();

    /*///////////////////////////////////////////////////////////////
                        ACCRUE/CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
      @notice Accrue rewards for a single user on a strategy
      @param  strategy        bytes    The strategy to accrue a user's rewards on
      @param  accruedRewards  uint256  The rewards amount accrued by the strategy
      @param  user            address  The user to be accrued
      @return                 uint256  The cumulative amount of rewards accrued to user (including prior)
    */
    function accrue(
        bytes memory strategy,
        uint256 accruedRewards,
        address user
    ) public returns (uint256) {
        // Only strategy needs to be validated since accruedRewards and user can be zero values
        if (strategy.length == 0) revert InvalidStrategy();

        RewardsState memory state = strategyState[strategy];

        if (state.index == 0) return 0;

        state = accrueStrategy(strategy, state, accruedRewards);
        return accrueUser(strategy, user, state);
    }

    /**
      @notice Accrue rewards for a two users on a strategy
      @param  strategy        bytes    The strategy to accrue a user's rewards on
      @param  accruedRewards  uint256  The rewards amount accrued by the strategy
      @param  user            address  The first user to be accrued
      @param  secondUser      address  The second user to be accrued
      @return                 uint256  The cumulative amount of rewards accrued to the first user (including prior)
      @return                 uint256  The cumulative amount of rewards accrued to the second user (including prior)
    */
    function accrue(
        bytes memory strategy,
        uint256 accruedRewards,
        address user,
        address secondUser
    ) public returns (uint256, uint256) {
        if (strategy.length == 0) revert InvalidStrategy();

        // Users are validated since there's no reason to call this variant of accrue if either are zero addresses
        if (user == address(0)) revert ZeroAddress();
        if (secondUser == address(0)) revert ZeroAddress();

        RewardsState memory state = strategyState[strategy];

        if (state.index == 0) return (0, 0);

        state = accrueStrategy(strategy, state, accruedRewards);
        return (
            accrueUser(strategy, user, state),
            accrueUser(strategy, secondUser, state)
        );
    }

    /**
      @notice Claim rewards for a given user
      @param  user  address  The user claiming rewards
    */
    function claimRewards(address user) external {
        if (user == address(0)) revert ZeroAddress();

        uint256 accrued = rewardsAccrued[user];

        if (accrued != 0) {
            rewardsAccrued[user] = 0;

            // TODO: Transfer rewards to user

            emit ClaimRewards(user, accrued);
        }
    }

    /*///////////////////////////////////////////////////////////////
                          ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
      @notice Initialize a new strategy
      @param  strategy  bytes  The strategy to accrue a user's rewards on
    */
    function _addStrategyForRewards(bytes memory strategy) internal {
        if (strategyState[strategy].index != 0) revert StrategyAlreadySet();

        strategyState[strategy] = RewardsState({
            index: ONE,
            lastUpdatedTimestamp: block.timestamp.safeCastTo32()
        });

        allStrategies.push(strategy);

        emit AddStrategy(strategy);
    }

    /**
      @notice Get strategies
      @return bytes[]  The list of strategies
    */
    function getAllStrategies() external view returns (bytes[] memory) {
        return allStrategies;
    }

    /**
      @notice Decode strategy
      @param  strategy  bytes  The abi-encoded strategy to accrue a user's rewards on
      @return producer  ERC20  The producer contract (produces rewards)
      @return reward    ERC20  The producer reward contract
    */
    function _decodeStrategy(bytes memory strategy)
        internal
        pure
        returns (ERC20 producer, ERC20 reward)
    {
        return abi.decode(strategy, (ERC20, ERC20));
    }

    /*///////////////////////////////////////////////////////////////
                    INTERNAL ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
      @notice Sync strategy state with rewards
      @param  strategy        bytes         The strategy to accrue a user's rewards on
      @param  state           RewardsState  The strategy rewards state
      @param  accruedRewards  uint256       The rewards amount accrued by the strategy
    */
    function accrueStrategy(
        bytes memory strategy,
        RewardsState memory state,
        uint256 accruedRewards
    ) internal returns (RewardsState memory rewardsState) {
        rewardsState = state;

        if (accruedRewards > 0) {
            (ERC20 producer, ) = _decodeStrategy(strategy);

            // Use the booster or token supply to calculate reward index denominator
            uint256 supplyTokens = producer.totalSupply();

            uint224 deltaIndex;

            if (supplyTokens != 0)
                deltaIndex = ((accruedRewards * ONE) / supplyTokens)
                    .safeCastTo224();

            // Accumulate rewards per token onto the index, multiplied by fixed-point factor
            rewardsState = RewardsState({
                index: state.index + deltaIndex,
                lastUpdatedTimestamp: block.timestamp.safeCastTo32()
            });
            strategyState[strategy] = rewardsState;
        }
    }

    /**
      @notice Sync user state with strategy
      @param  strategy  bytes         The strategy to accrue a user's rewards on
      @param  user      address       The user to
      @param  state     RewardsState  The strategy rewards state
    */
    function accrueUser(
        bytes memory strategy,
        address user,
        RewardsState memory state
    ) private returns (uint256) {
        // Load indices
        uint224 strategyIndex = state.index;
        uint224 supplierIndex = userIndex[strategy][user];

        // Sync user index to global
        userIndex[strategy][user] = strategyIndex;

        // If user hasn't yet accrued rewards, grant them interest from the strategy beginning if they have a balance
        // Zero balances will have no effect other than syncing to global index
        if (supplierIndex == 0) {
            supplierIndex = ONE;
        }

        uint224 deltaIndex = strategyIndex - supplierIndex;
        (ERC20 producer, ) = _decodeStrategy(strategy);

        // Accumulate rewards by multiplying user tokens by rewardsPerToken index and adding on unclaimed
        uint256 supplierDelta = (producer.balanceOf(user) * deltaIndex) / ONE;
        uint256 supplierAccrued = rewardsAccrued[user] + supplierDelta;

        rewardsAccrued[user] = supplierAccrued;

        emit AccrueRewards(strategy, user, supplierDelta, strategyIndex);

        return supplierAccrued;
    }
}
