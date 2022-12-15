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
        - Add AccrueStrategy event and emit in accrueStrategy
        - Return function if accruedRewards is zero in accrueStrategy
        - Change visibility to internal and add a leading unscore (to denote internal method)
            - accrueStrategy
            - accrueUser
            - claimRewards
        - Remove state parameter from accrueUser and read strategy index in function body
        - Modify rewardsAccrued to support multiple rewards for each user
        - Change claimRewards visibility to internal
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
    mapping(address => mapping(ERC20 => uint256)) public rewardsAccrued;

    /**
      @notice Emitted when a strategy has its rewards accrued
      @param  strategy        bytes    The updated rewards strategy
      @param  accruedRewards  uint256  The amount of accrued rewards
    */
    event AccrueStrategy(bytes indexed strategy, uint256 accruedRewards);

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
      @notice Claim rewards for a given user
      @param  user    address  The user claiming rewards
      @param  reward  ERC20    The reward token contract
    */
    function _claimRewards(address user, ERC20 reward) internal {
        if (user == address(0)) revert ZeroAddress();

        uint256 accrued = rewardsAccrued[user][reward];

        if (accrued != 0) {
            rewardsAccrued[user][reward] = 0;

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
      @param  strategy        bytes    The strategy to accrue a user's rewards on
      @param  accruedRewards  uint256  The rewards amount accrued by the strategy
    */
    function _accrueStrategy(bytes memory strategy, uint256 accruedRewards)
        internal
        returns (RewardsState memory rewardsState)
    {
        emit AccrueStrategy(strategy, accruedRewards);

        if (accruedRewards == 0) return strategyState[strategy];

        (ERC20 producer, ) = _decodeStrategy(strategy);

        // Use the booster or token supply to calculate reward index denominator
        uint256 supplyTokens = producer.totalSupply();

        uint224 deltaIndex;

        if (supplyTokens != 0)
            deltaIndex = ((accruedRewards * ONE) / supplyTokens)
                .safeCastTo224();

        // Accumulate rewards per token onto the index, multiplied by fixed-point factor
        rewardsState = RewardsState({
            index: strategyState[strategy].index + deltaIndex,
            lastUpdatedTimestamp: block.timestamp.safeCastTo32()
        });
        strategyState[strategy] = rewardsState;
    }

    /**
      @notice Sync user state with strategy
      @param  strategy  bytes         The strategy to accrue a user's rewards on
      @param  user      address       The user to accrue rewards for
    */
    function _accrueUser(bytes memory strategy, address user)
        internal
        returns (uint256)
    {
        // Load indices
        uint224 strategyIndex = strategyState[strategy].index;
        uint224 supplierIndex = userIndex[strategy][user];

        // Sync user index to global
        userIndex[strategy][user] = strategyIndex;

        // If user hasn't yet accrued rewards, grant them interest from the strategy beginning if they have a balance
        // Zero balances will have no effect other than syncing to global index
        if (supplierIndex == 0) {
            supplierIndex = ONE;
        }

        uint224 deltaIndex = strategyIndex - supplierIndex;
        (ERC20 producer, ERC20 reward) = _decodeStrategy(strategy);

        // Accumulate rewards by multiplying user tokens by rewardsPerToken index and adding on unclaimed
        uint256 supplierDelta = (producer.balanceOf(user) * deltaIndex) / ONE;
        uint256 supplierAccrued = rewardsAccrued[user][reward] + supplierDelta;

        rewardsAccrued[user][reward] = supplierAccrued;

        emit AccrueRewards(strategy, user, supplierDelta, strategyIndex);

        return supplierAccrued;
    }
}
