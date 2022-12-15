// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexRewards} from "src/PirexRewards.sol";

// Used for testing contract upgrade
contract PirexRewardsMock is PirexRewards {
    // New method used for testing upgradeability
    function getRewardStateMock()
        external
        view
        returns (uint256)
    {
        // Return double the number of strategies from the original implementation
        return allStrategies.length * 2;
    }
}
