# Pirex-GMX

### Setup

IDE: VSCode 1.73.0 (Universal)

Forge: 0.2.0

From inside the project directory:

1. Install contract dependencies `forge i`
2. Compile contracts `forge build`
3. Set up and run tests
   - Create the test variables helper script `cp scripts/loadEnv.example.sh scripts/loadEnv.sh`
   - Define the values within the newly-created file
   - Run the test helper script `scripts/forgeTest.sh` (along with any `forge test` arguments, flags, options, etc.)

### Overview

Pirex provides GMX token holders with a streamlined and convenient solution for maximizing the productivity of their GMX and GLP tokens. As a user of Pirex, you can benefit in the following ways:

- Boosted yield as a result of frequent and continuous multiplier point compounding
- Efficient, autonomous compounding of rewards into pxGMX or pxGLP (if using "Easy Mode")
- Mint tokens backed by your future GMX rewards and sell them on our decentralized futures marketplace (if using "Hard Mode" - coming soon)

And more. We're continuously improving our products and adding value to our users, and will make announcements as additional utility is available for our tokens. Please follow us on Twitter ([@redactedcartel](https://twitter.com/redactedcartel)) to stay in the loop ❤️.

### How Does It Work?

**_Tokens_**

pxGMX: The Pirex-wrapped version of staked GMX and \*esGMX, handled in a way to maximize yield for the protocol's users (e.g. continuous, automatic, socialized multiplier point compounding). pxGMX token holders will be able to claim rewards and vote in GMX governance proposals (coming soon, after launch), just as they would with staked GMX. pxGMX cannot be redeemed for the underlying assets (those assets are essentially "blackholed" and will never resurface on the market), but can be sold for GMX, via a liquidity pool which we will seed (i.e. add initial pxGMX and GMX liquidity).

\*esGMX rewards are distributed as pxGMX, which are minted at the time of an individual user's reward claim. When unclaimed/unminted, the rewards earned by esGMX-backed pxGMX will be distributed amongst existing pxGMX token holders, boosting their rewards even further!

pxGLP: The Pirex-wrapped version of staked GLP, handled in the same way as pxGMX to maximize yield. pxGLP token holders can claim rewards, just as they would with staked GLP, and also redeem them for any GLP constituent asset ([check the GMX app for a complete list](https://app.gmx.io/#/buy_glp#redeem)).

**_Modes_**

Easy Mode: Sit back, relax, and we will autocompound the pxGMX and pxGLP rewards into more of those assets for you.

Standard Mode: Manually handle your pxGMX or pxGLP by claiming rewards and other actions (e.g. vote in GMX governance with pxGMX), while still enjoying the benefits of Pirex-GMX's multiplier point auto-compounding.

Hard Mode (Coming Soon): Stake your pxGMX or pxGLP and mint tokens representing their future rewards (e.g. you can stake pxGMX for 1 year and receive the equivalent of 1 year's worth of rewards - after 1 year, you can unstake your pxGMX), and sell it on our decentralized futures marketplace.

### Core Contract Overview

**PirexGmx.sol**

- Intakes GMX-based tokens (GMX and GLP) and mints their synthetic counterparts in return (pxGMX and pxGLP)
- Allows users to redeem their pxGLP for GLP constituent assets (same assets which GMX allows GLP to be traded for, e.g. USDC, WBTC, etc.)
- Interacts with the GMX contracts to stake and mint assets, claim rewards, perform asset migrations (only if necessary, as a result of a contract upgrade), and more
- Custodies GMX rewards until they are claimed and distributed via a call from the PirexRewards contract

**PirexRewards.sol**

- Tracks perpetually accrued/continuously streamed GMX rewards across multiple scopes: global, different reward tokens, and individual users
- Has permission to call various reward-related methods on the PirexGmx contract for claiming and distributing rewards to users
- Enables reward forwarding, and can also set a reward recipient on behalf of contract accounts (permissioned, used to direct rewards accrued from tokens in LP contracts - those rewards would otherwise be wasted)

**PirexFees.sol**

- Custodies protocol fees and distributes them to the Redacted treasury and Pirex contributor multisig
- Allows its owner, a Redacted multisig, to modify various contract state variables (i.e. fee percent and fee recipient addresses)

**PxERC20.sol**

- Modifies standard ERC20 methods with calls to PirexRewards's reward accrual methods to ensure that asset ownership and reward distribution can be properly accounted for

**PxGmx.sol**

- Is a derivative of the PxERC20 contract
- Represents GMX and esGMX tokens (calls the PxERC20 constructor, which it is derived from, with fixed values that is consistent with this goal)
- Overwrites the `burn` method of PxERC20 (pxGMX cannot be redeemed for GMX or esGMX)

**AutoPxGmx.sol**

- Accepts GMX\* and pxGMX deposits, and issues share tokens (apxGMX) against them
- Compounds pxGMX rewards into more pxGMX: Swaps WETH rewards into GMX via Uniswap V3 and deposits it into PirexGmx to acquire pxGMX, and claims/mints esGMX-backed pxGMX rewards
- Provides a series of permissioned methods that enables the Pirex multisig to configure fees, incentives, and Uniswap V3 pool fee

\*NOTE: GMX is converted into pxGMX.

**AutoPxGlp.sol**

- Accepts GLP, GLP constituent assets, and pxGLP deposits, and issues share tokens (apxGLP) against them
- Compounds pxGLP WETH rewards into more pxGLP, and tracks esGMX-backed pxGMX rewards earned by vault users
- Provides a series of permissioned methods that enables the Pirex multisig to configure fees and incentives

### Contract Diagram

Below are visualizations of how Pirex-GMX contracts interact with one another as well as with external contracts (e.g. GMX's contracts) as a result of different user interactions. Please note that the diagrams do not cover every single user action for the purpose of avoiding redundancy (e.g. the diagram for depositing GMX and acquiring pxGMX is more or less the same as depositing GLP or GLP constituent assets and acquiring pxGLP).

### Contract Diagram: Deposit GMX, Receive pxGMX

![Contract Diagram: Deposit GMX, Receive pxGMX](https://i.imgur.com/5qEKj8q.png)

### Contract Diagram: Claim pxGMX/pxGLP Rewards

![Contract Diagram: Claim pxGMX/pxGLP Rewards](https://i.imgur.com/NqaxI2P.png)

### Contract Diagram: Auto-compound pxGMX Rewards

![Contract Diagram: Auto-compound pxGMX Rewards](https://i.imgur.com/raWbR1z.png)
