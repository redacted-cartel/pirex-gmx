// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {PirexRewards} from "src/PirexRewards.sol";

contract PxERC20 is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    PirexRewards public immutable pirexRewards;

    error ZeroAddress();
    error ZeroAmount();
    error EmptyString();

    /**
        @param  _pirexRewards  address  PirexRewards contract address
        @param  _name          string   Token name (e.g. Pirex GLP)
        @param  _symbol        string   Token symbol (e.g. pxGLP)
        @param  _decimals      uint8    Token decimals (e.g. 18)
    */
    constructor(
        address _pirexRewards,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {
        if (_pirexRewards == address(0)) revert ZeroAddress();
        if (bytes(_name).length == 0) revert EmptyString();
        if (bytes(_symbol).length == 0) revert EmptyString();
        if (_decimals == 0) revert ZeroAmount();

        pirexRewards = PirexRewards(_pirexRewards);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
        @notice Mint tokens
        @param  to      address  Token recipient
        @param  amount  uint256  Token mint amount
    */
    function mint(address to, uint256 amount)
        external
        virtual
        onlyRole(MINTER_ROLE)
    {
        // Update delta for strategies prior to supply change
        pirexRewards.accrueStrategy();

        // Update delta for strategies prior to balance change
        pirexRewards.accrueUser(this, to);

        _mint(to, amount);
    }

    /**
        @notice Burn tokens
        @param  from    address  Token owner
        @param  amount  uint256  Token burn amount
    */
    function burn(address from, uint256 amount)
        external
        virtual
        onlyRole(BURNER_ROLE)
    {
        pirexRewards.accrueStrategy();
        pirexRewards.accrueUser(this, from);

        _burn(from, amount);
    }

    /**
        @notice Transfer tokens (called by token owner)
        @param  to      address  Token recipient
        @param  amount  uint256  Token transfer amount
        @return         bool     Token transfer status
    */
    function transfer(address to, uint256 amount)
        public
        override
        returns (bool)
    {
        // Update delta for strategies so that users receive all rewards up to the transfers
        // Accrue users prior to balance changes to ensure that they receive their entitled rewards
        pirexRewards.accrueStrategy();
        pirexRewards.accrueUser(this, msg.sender);
        pirexRewards.accrueUser(this, to);

        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    /**
        @notice Transfer tokens (called by account with allowance)
        @param  from    address  Token owner
        @param  to      address  Token recipient
        @param  amount  uint256  Token transfer amount
        @return         bool     Token transfer status
    */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max)
            allowance[from][msg.sender] = allowed - amount;

        pirexRewards.accrueStrategy();
        pirexRewards.accrueUser(this, from);
        pirexRewards.accrueUser(this, to);

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }
}
