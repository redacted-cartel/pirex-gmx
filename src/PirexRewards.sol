// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IProducer} from "src/interfaces/IProducer.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/**
    Originally inspired by and utilizes Fei Protocol's Flywheel V2 accrual logic (thank you Tribe team):
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/FlywheelCore.sol
*/
contract PirexRewards is OwnableUpgradeable {
    using FixedPointMathLib for uint256;

    struct User {
        // User indexes by strategy
        mapping(bytes => uint256) index;
        // Accrued but not yet transferred rewards
        mapping(ERC20 => uint256) rewardsAccrued;
        // Accounts which users are forwarding their rewards to
        mapping(ERC20 => address) rewardRecipients;
    }

    // The fixed point factor
    uint256 public constant ONE = 1e18;

    // Core reward-producing Pirex contract
    IProducer public producer;

    // Strategies by producer token
    mapping(ERC20 => bytes[]) public strategies;

    // Strategy indexes
    mapping(bytes => uint256) public strategyIndexes;

    // User data
    mapping(address => User) internal users;

    event SetProducer(address producer);
    event AddStrategy(bytes indexed newStrategy);
    event Claim(
        ERC20 indexed rewardToken,
        address indexed user,
        address indexed recipient,
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

    error StrategyAlreadySet();
    error ZeroAddress();
    error EmptyArray();
    error NotContract();

    function initialize() public initializer {
        __Ownable_init();
    }

    /**
      @notice Decode strategy
      @param  strategy       bytes  The abi-encoded strategy to accrue a user's rewards on
      @return producerToken  ERC20  The producer token contract
      @return rewardToken    ERC20  The reward token contract
    */
    function _decodeStrategy(bytes memory strategy)
        internal
        pure
        returns (ERC20 producerToken, ERC20 rewardToken)
    {
        return abi.decode(strategy, (ERC20, ERC20));
    }

    /**
      @notice Sync strategy index with the rewards
      @param  strategy        bytes    The strategy to accrue a user's rewards on
      @param  accruedRewards  uint256  The rewards amount accrued by the strategy
      @return                 uint256  The updated strategy index value
    */
    function _accrueStrategy(bytes memory strategy, uint256 accruedRewards)
        internal
        returns (uint256)
    {
        emit AccrueStrategy(strategy, accruedRewards);

        if (accruedRewards == 0) return strategyIndexes[strategy];

        (ERC20 producerToken, ) = _decodeStrategy(strategy);

        // Use the booster or token supply to calculate reward index denominator
        uint256 supplyTokens = producerToken.totalSupply();

        uint256 deltaIndex;

        if (supplyTokens != 0)
            deltaIndex = accruedRewards.mulDivDown(ONE, supplyTokens);

        // Accumulate rewards per token onto the index, multiplied by fixed-point factor
        strategyIndexes[strategy] += deltaIndex;

        return strategyIndexes[strategy];
    }

    /**
      @notice Sync user state with strategy
      @param  strategy  bytes    The strategy to accrue a user's rewards on
      @param  user      address  The user to accrue rewards for
    */
    function _accrueUser(bytes memory strategy, address user)
        internal
        returns (uint256)
    {
        User storage u = users[user];

        // Load indices
        uint256 strategyIndex = strategyIndexes[strategy];
        uint256 supplierIndex = u.index[strategy];

        // Sync user index to global
        u.index[strategy] = strategyIndex;

        // If user hasn't yet accrued rewards, grant them interest from the strategy beginning if they have a balance
        // Zero balances will have no effect other than syncing to global index
        if (supplierIndex == 0) {
            supplierIndex = ONE;
        }

        uint256 deltaIndex = strategyIndex - supplierIndex;
        (ERC20 producerToken, ERC20 rewardToken) = _decodeStrategy(strategy);

        // Accumulate rewards by multiplying user tokens by rewardsPerToken index and adding on unclaimed
        uint256 supplierDelta = producerToken.balanceOf(user).mulDivDown(
            deltaIndex,
            ONE
        );
        uint256 supplierAccrued = u.rewardsAccrued[rewardToken] + supplierDelta;

        u.rewardsAccrued[rewardToken] = supplierAccrued;

        emit AccrueRewards(strategy, user, supplierDelta, strategyIndex);

        return supplierAccrued;
    }

    /**
        @notice Get strategies for a producer token
        @param  producerToken  ERC20    Producer token contract
        @return                bytes[]  Strategies list
     */
    function getStrategies(ERC20 producerToken)
        external
        view
        returns (bytes[] memory)
    {
        return strategies[producerToken];
    }

    /**
        @notice Get a strategy index for a user
        @param  user      address  User
        @param  strategy  bytes    Strategy (abi-encoded producer and reward tokens)
     */
    function getUserIndex(address user, bytes memory strategy)
        external
        view
        returns (uint256)
    {
        return users[user].index[strategy];
    }

    /**
        @notice Get the rewards accrued for a user
        @param  user         address  User
        @param  rewardToken  ERC20    Reward token contract
     */
    function getUserRewardsAccrued(address user, ERC20 rewardToken)
        external
        view
        returns (uint256)
    {
        return users[user].rewardsAccrued[rewardToken];
    }

    /**
        @notice Set producer
        @param  _producer  address  Producer contract address
     */
    function setProducer(address _producer) external onlyOwner {
        if (_producer == address(0)) revert ZeroAddress();

        producer = IProducer(_producer);

        emit SetProducer(_producer);
    }

    /**
        @notice Add a strategy comprised of a producer and reward token
        @param  producerToken  ERC20  Producer token contract
        @param  rewardToken    ERC20  Reward token contract
        @return strategy       bytes  Strategy
    */
    function addStrategyForRewards(ERC20 producerToken, ERC20 rewardToken)
        external
        onlyOwner
        returns (bytes memory)
    {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        bytes memory strategy = abi.encode(producerToken, rewardToken);

        if (strategyIndexes[strategy] != 0) revert StrategyAlreadySet();

        strategies[producerToken].push(strategy);

        strategyIndexes[strategy] = ONE;

        emit AddStrategy(strategy);

        return strategy;
    }

    /**
        @notice Accrue strategy rewards
        @return producerTokens  ERC20[]  Producer token contracts
        @return rewardTokens    ERC20[]  Reward token contracts
        @return rewardAmounts   ERC20[]  Reward token amounts
    */
    function accrueStrategy()
        public
        returns (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        )
    {
        // pxGMX and pxGLP rewards must be claimed all at once since PirexGmx is
        // the sole token holder
        (producerTokens, rewardTokens, rewardAmounts) = producer.claimRewards();

        uint256 pLen = producerTokens.length;

        // Iterate over the producer tokens and accrue strategy
        for (uint256 i; i < pLen; ++i) {
            uint256 r = rewardAmounts[i];

            if (r != 0) {
                _accrueStrategy(
                    abi.encode(producerTokens[i], rewardTokens[i]),
                    r
                );
            }
        }
    }

    /**
        @notice Accrue user rewards for each strategy (producer and reward token pair)
        @param  producerToken  ERC20      Producer token contract
        @param  user           address    User
        @return userAccrued    uint256[]  Accrued user rewards
    */
    function accrueUser(ERC20 producerToken, address user)
        public
        returns (uint256[] memory userAccrued)
    {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (user == address(0)) revert ZeroAddress();

        bytes[] memory s = strategies[producerToken];
        uint256 sLen = s.length;
        userAccrued = new uint256[](sLen);

        // Accrue user rewards for each strategy (producer and reward token pair)
        for (uint256 i; i < sLen; ++i) {
            userAccrued[i] = _accrueUser(s[i], user);
        }
    }

    /**
      @notice Claim rewards for a given user
      @param  rewardTokens  ERC20[]  Reward token contracts
      @param  user          address  The user claiming rewards
    */
    function claim(ERC20[] calldata rewardTokens, address user) public {
        uint256 rLen = rewardTokens.length;

        if (rLen == 0) revert EmptyArray();
        if (user == address(0)) revert ZeroAddress();

        User storage u = users[user];

        for (uint256 i; i < rLen; ++i) {
            ERC20 r = rewardTokens[i];
            uint256 accrued = u.rewardsAccrued[r];

            if (accrued != 0) {
                u.rewardsAccrued[r] = 0;

                // Forward rewards if a rewardRecipient is set
                address rewardRecipient = users[user].rewardRecipients[r];
                address recipient = rewardRecipient == address(0)
                    ? user
                    : rewardRecipient;

                producer.claimUserReward(address(r), accrued, recipient);

                emit Claim(r, user, recipient, accrued);
            }
        }
    }

    /**
      @notice Accrue rewards and claim them for a given user
      @param  producerTokens  ERC20[]  Producer token contracts
      @param  rewardTokens    ERC20[]  Reward token contracts
      @param  user            address  The user claiming rewards
    */
    function accrueAndClaim(
        ERC20[] calldata producerTokens,
        ERC20[] calldata rewardTokens,
        address user
    ) external {
        uint256 pLen = producerTokens.length;

        // The only check necessary since the `claim` method validates the remaining parameters
        if (pLen == 0) revert EmptyArray();

        // Harvest and accrue strategy indexes to ensure the rewards are up-to-date
        accrueStrategy();

        for (uint256 i; i < pLen; ++i) {
            // Accrue rewards for every producer token in preparation for the claim
            accrueUser(producerTokens[i], user);
        }

        claim(rewardTokens, user);
    }

    /**
        @notice Get the reward recipient for a user by producer and reward token
        @param  user         address  User
        @param  rewardToken  ERC20    Reward token contract
        @return              address  Reward recipient
    */
    function getRewardRecipient(address user, ERC20 rewardToken)
        external
        view
        returns (address)
    {
        return users[user].rewardRecipients[rewardToken];
    }

    /**
        @notice Set reward recipient for a reward token
        @param  rewardToken  ERC20    Reward token contract
        @param  recipient    address  Rewards recipient
    */
    function setRewardRecipient(ERC20 rewardToken, address recipient) external {
        if (address(rewardToken) == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();

        users[msg.sender].rewardRecipients[rewardToken] = recipient;

        emit SetRewardRecipient(msg.sender, rewardToken, recipient);
    }

    /**
        @notice Unset reward recipient for a reward token
        @param  rewardToken  ERC20  Reward token contract
    */
    function unsetRewardRecipient(ERC20 rewardToken) external {
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        delete users[msg.sender].rewardRecipients[rewardToken];

        emit UnsetRewardRecipient(msg.sender, rewardToken);
    }

    /*//////////////////////////////////////////////////////////////
                    ⚠️ NOTABLE PRIVILEGED METHODS ⚠️
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Privileged method for setting the reward recipient of a contract
        @notice This should ONLY be used to forward rewards for Pirex-GMX LP contracts
        @notice In production, we will have a 2nd multisig which reduces risk of abuse
        @param  lpContract   address  Pirex-GMX LP contract
        @param  rewardToken  ERC20    Reward token contract
        @param  recipient    address  Rewards recipient
    */
    function setRewardRecipientPrivileged(
        address lpContract,
        ERC20 rewardToken,
        address recipient
    ) external onlyOwner {
        if (lpContract.code.length == 0) revert NotContract();
        if (address(rewardToken) == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();

        users[lpContract].rewardRecipients[rewardToken] = recipient;

        emit SetRewardRecipient(lpContract, rewardToken, recipient);
    }

    /**
        @notice Privileged method for unsetting the reward recipient of a contract
        @param  lpContract   address  Pirex-GMX LP contract
        @param  rewardToken  ERC20    Reward token contract
    */
    function unsetRewardRecipientPrivileged(
        address lpContract,
        ERC20 rewardToken
    ) external onlyOwner {
        if (lpContract.code.length == 0) revert NotContract();
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        delete users[lpContract].rewardRecipients[rewardToken];

        emit UnsetRewardRecipient(lpContract, rewardToken);
    }
}
