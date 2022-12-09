// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IRewardRouterV2} from "src/interfaces/IRewardRouterV2.sol";
import {IStakedGlp} from "src/interfaces/IStakedGlp.sol";
import {IPirexGmx} from "src/interfaces/IPirexGmx.sol";

contract PirexGmxCooldownHandler {
    using SafeTransferLib for ERC20;

    IPirexGmx public immutable pirexGmx;

    constructor() {
        pirexGmx = IPirexGmx(msg.sender);
    }

    /**
        @notice Mint + stake GLP and deposit them into PirexGmx on behalf of a user
        @param  rewardRouter  IRewardRouterV2  GLP Reward Router interface instance
        @param  stakedGlp     IStakedGlp       StakedGlp interface instance
        @param  glpManager    address          GlpManager contract address
        @param  token         address          GMX-whitelisted token for minting GLP
        @param  tokenAmount   uint256          Whitelisted token amount
        @param  minUsdg       uint256          Minimum USDG purchased and used to mint GLP
        @param  minGlp        uint256          Minimum GLP amount minted from ERC20 tokens
        @param  receiver      address          pxGLP receiver
        @return               uint256          GLP deposited
        @return               uint256          pxGLP minted for the receiver
        @return               uint256          pxGLP distributed as fees
     */
    function depositGlp(
        IRewardRouterV2 rewardRouter,
        IStakedGlp stakedGlp,
        address glpManager,
        address token,
        uint256 tokenAmount,
        uint256 minUsdg,
        uint256 minGlp,
        address receiver
    )
        external
        payable
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        ERC20(token).safeApprove(glpManager, tokenAmount);

        uint256 deposited = token == address(0)
            ? rewardRouter.mintAndStakeGlpETH{value: msg.value}(minUsdg, minGlp)
            : rewardRouter.mintAndStakeGlp(token, tokenAmount, minUsdg, minGlp);

        // Handling stakedGLP approvals for each call in case its updated on PirexGmx
        stakedGlp.approve(address(pirexGmx), deposited);

        return pirexGmx.depositFsGlp(deposited, receiver);
    }
}
