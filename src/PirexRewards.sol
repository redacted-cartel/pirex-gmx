// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IProducer} from "src/interfaces/IProducer.sol";
import {GlobalState, UserState} from "src/Common.sol";
import {FeiFlywheelCoreV2} from "src/modified/FeiFlywheelCoreV2.sol";

/**
    Originally inspired by Flywheel V2 (thank you Tribe team):
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/FlywheelCore.sol
*/
contract PirexRewards is OwnableUpgradeable, FeiFlywheelCoreV2 {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;

    struct ProducerToken {
        ERC20[] rewardTokens;
        GlobalState globalState;
        mapping(address => UserState) userStates;
        mapping(ERC20 => uint256) rewardStates;
        mapping(address => mapping(ERC20 => address)) rewardRecipients;
    }

    // Pirex contract which produces rewards
    IProducer public producer;

    // Producer tokens mapped to their data
    mapping(ERC20 => ProducerToken) public producerTokens;

    // Producer tokens mapped to its list of strategies
    mapping(ERC20 => bytes[]) public strategies;

    event SetProducer(address producer);
    event SetRewardRecipient(
        address indexed user,
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken,
        address recipient
    );
    event UnsetRewardRecipient(
        address indexed user,
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken
    );
    event GlobalAccrue(
        ERC20 indexed producerToken,
        uint256 lastUpdate,
        uint256 lastSupply,
        uint256 rewards
    );
    event UserAccrue(
        ERC20 indexed producerToken,
        address indexed user,
        uint256 lastUpdate,
        uint256 lastBalance,
        uint256 rewards
    );
    event Harvest(
        ERC20[] producerTokens,
        ERC20[] rewardTokens,
        uint256[] rewardAmounts
    );
    event Claim(
        ERC20 indexed rewardToken,
        address indexed user,
        uint256 amount
    );
    event SetRewardRecipientPrivileged(
        address indexed lpContract,
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken,
        address recipient
    );
    event UnsetRewardRecipientPrivileged(
        address indexed lpContract,
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken
    );

    error NotContract();
    error TokenAlreadyAdded();
    error EmptyArray();

    function initialize() public initializer {
        __Ownable_init();
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
        @notice Set reward recipient for a reward token
        @param  producerToken  ERC20    Producer token contract
        @param  rewardToken    ERC20    Reward token contract
        @param  recipient      address  Rewards recipient
    */
    function setRewardRecipient(
        ERC20 producerToken,
        ERC20 rewardToken,
        address recipient
    ) external {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();

        producerTokens[producerToken].rewardRecipients[msg.sender][
            rewardToken
        ] = recipient;

        emit SetRewardRecipient(
            msg.sender,
            producerToken,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Unset reward recipient for a reward token
        @param  producerToken  ERC20  Producer token contract
        @param  rewardToken    ERC20  Reward token contract
    */
    function unsetRewardRecipient(ERC20 producerToken, ERC20 rewardToken)
        external
    {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        delete producerTokens[producerToken].rewardRecipients[msg.sender][
            rewardToken
        ];

        emit UnsetRewardRecipient(msg.sender, producerToken, rewardToken);
    }

    /**
        @notice Add a strategy comprised of a producer and reward token
        @param  producerToken  ERC20  Producer token contract
        @param  rewardToken    ERC20  Reward token contract
    */
    function addStrategyForRewards(ERC20 producerToken, ERC20 rewardToken)
        external
        onlyOwner
    {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        bytes memory strategy = abi.encode(producerToken, rewardToken);

        strategies[producerToken].push(strategy);

        _addStrategyForRewards(strategy);
    }

    /**
        @notice Get the reward recipient for a user by producer and reward token
        @param  user           address  User
        @param  producerToken  ERC20    Producer token contract
        @param  rewardToken    ERC20    Reward token contract
        @return                address  Reward recipient
    */
    function getRewardRecipient(
        address user,
        ERC20 producerToken,
        ERC20 rewardToken
    ) external view returns (address) {
        return
            producerTokens[producerToken].rewardRecipients[user][rewardToken];
    }

    /**
        @notice Accrue strategy rewards
        @return _producerTokens  ERC20[]  Producer token contracts
        @return rewardTokens     ERC20[]  Reward token contracts
        @return rewardAmounts    ERC20[]  Reward token amounts
    */
    function accrueStrategy()
        public
        returns (
            ERC20[] memory _producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        )
    {
        // pxGMX and pxGLP rewards must be claimed all at once since PirexGmx is
        // the sole token holder
        (_producerTokens, rewardTokens, rewardAmounts) = producer
            .claimRewards();
        uint256 pLen = _producerTokens.length;

        // Iterate over the producer tokens and accrue strategy
        for (uint256 i; i < pLen; ++i) {
            uint256 r = rewardAmounts[i];

            if (r != 0) {
                _accrueStrategy(
                    abi.encode(_producerTokens[i], rewardTokens[i]),
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
    function claim(ERC20[] calldata rewardTokens, address user) internal {
        uint256 rLen = rewardTokens.length;

        if (rLen == 0) revert EmptyArray();
        if (user == address(0)) revert ZeroAddress();

        for (uint256 i; i < rLen; ++i) {
            ERC20 r = rewardTokens[i];
            uint256 accrued = rewardsAccrued[user][r];

            if (accrued != 0) {
                rewardsAccrued[user][r] = 0;

                producer.claimUserReward(address(r), accrued, user);

                emit Claim(r, user, accrued);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    ⚠️ NOTABLE PRIVILEGED METHODS ⚠️
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Privileged method for setting the reward recipient of a contract
        @notice This should ONLY be used to forward rewards for Pirex-GMX LP contracts
        @notice In production, we will have a 2nd multisig which reduces risk of abuse
        @param  lpContract     address  Pirex-GMX LP contract
        @param  producerToken  ERC20    Producer token contract
        @param  rewardToken    ERC20    Reward token contract
        @param  recipient      address  Rewards recipient
    */
    function setRewardRecipientPrivileged(
        address lpContract,
        ERC20 producerToken,
        ERC20 rewardToken,
        address recipient
    ) external onlyOwner {
        if (lpContract.code.length == 0) revert NotContract();
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();

        producerTokens[producerToken].rewardRecipients[lpContract][
            rewardToken
        ] = recipient;

        emit SetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Privileged method for unsetting the reward recipient of a contract
        @param  lpContract     address  Pirex-GMX LP contract
        @param  producerToken  ERC20    Producer token contract
        @param  rewardToken    ERC20    Reward token contract
    */
    function unsetRewardRecipientPrivileged(
        address lpContract,
        ERC20 producerToken,
        ERC20 rewardToken
    ) external onlyOwner {
        if (lpContract.code.length == 0) revert NotContract();
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        delete producerTokens[producerToken].rewardRecipients[lpContract][
            rewardToken
        ];

        emit UnsetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken
        );
    }
}
