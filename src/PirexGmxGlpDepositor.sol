// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IRewardRouterV2} from "src/interfaces/IRewardRouterV2.sol";
import {IStakedGlp} from "src/interfaces/IStakedGlp.sol";
import {IPirexGmx} from "src/interfaces/IPirexGmx.sol";

contract PirexGmxGlpDepositor {
    using SafeTransferLib for ERC20;

    /**
        @notice Deposit GLP (minted with ETH) on behalf of a user and deposit into PirexGmx
        @param  rewardRouter  IRewardRouterV2  GLP Reward Router interface instance
        @param  stakedGlp     IStakedGlp       StakedGlp interface instance
        @param  minUsdg       uint256          Minimum USDG purchased and used to mint GLP
        @param  minGlp        uint256          Minimum GLP amount minted from ETH
        @param  receiver      address          pxGLP receiver
        @return               uint256          GLP deposited
        @return               uint256          pxGLP minted for the receiver
        @return               uint256          pxGLP distributed as fees
     */
    function depositGlpETH(
        IRewardRouterV2 rewardRouter,
        IStakedGlp stakedGlp,
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
        uint256 deposited = rewardRouter.mintAndStakeGlpETH{value: msg.value}(
            minUsdg,
            minGlp
        );

        stakedGlp.approve(msg.sender, deposited);

        return IPirexGmx(msg.sender).depositFsGlp(deposited, receiver);
    }

    /**
        @notice Deposit GLP (minted with ERC20 tokens) on behalf of a user and deposit into PirexGmx
        @param  rewardRouter  IRewardRouterV2  GLP Reward Router interface instance
        @param  glpManager    address          GlpManager contract address
        @param  stakedGlp     IStakedGlp       StakedGlp interface instance
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
        address glpManager,
        IStakedGlp stakedGlp,
        address token,
        uint256 tokenAmount,
        uint256 minUsdg,
        uint256 minGlp,
        address receiver
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        ERC20(token).safeApprove(glpManager, tokenAmount);

        uint256 deposited = rewardRouter.mintAndStakeGlp(
            token,
            tokenAmount,
            minUsdg,
            minGlp
        );

        stakedGlp.approve(msg.sender, deposited);

        return IPirexGmx(msg.sender).depositFsGlp(deposited, receiver);
    }
}
