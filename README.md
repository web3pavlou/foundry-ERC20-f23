# foundry-erc20-f23

 *This repo contains two implementations of ERC-20 tokens built with **Foundry** and a full Foundry workflow (unit, forked, and staging tests), broadcast scripts, and optional zkSync deployment via Makefile.*

---

##  Overview

This project ships **two ERC-20 tokens**:

- **`OurToken.sol`** – OpenZeppelin-based ERC-20 (audited reference implementation).
- **`ManualToken.sol`** – Hand-crafted ERC-20 focused on clarity and gas efficiency.


### Key differences
- **ManualToken**:
  - Uses **custom errors** instead of revert strings (smaller bytecode).
  - Includes **`burn`** and **`burnFrom`** (and emits `Transfer(to=0)`).
  - Provides **`approveAndCall`** (approve + callback) with checks (`spender != 0`, `spender.code.length > 0`).
  - **Infinite allowance fast-path**: if `allowance == type(uint256).max`, `transferFrom`/`burnFrom` skip the SSTORE.
  - `decimals()` returns a compile-time **constant** (18).
  - **Constructor expects _whole tokens_** and multiplies internally by `10**decimals`.

- **OurToken**:
  - Inherits from **OpenZeppelin ERC-20** library directly.

---

##  Requirements

- **git**
- **Foundry** (forge, cast, anvil)  
  Install or update:
```bash
  curl -L https://foundry.paradigm.xyz | bash
  foundryup
```
---

##  Quickstart
```bash
# Clone
git clone https://github.com/web3pavlou/foundry-erc20-f23
cd foundry-erc20-f23

# Build
forge build 

# Run all tests
forge test -vv
```
---

##  Deployment

### With Foundry script (local Anvil)

**ManualToken**:
```bash
# Terminal 1
anvil
# Terminal 2 (new shell)
forge script script/DeployManualToken.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  -vv
```
**OurToken**:

```bash
# Terminal 1
anvil
# Terminal 2 (new shell)
forge script script/DeployOurToken.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  -vv
```
### With Makefile (examples)

This project includes Make targets for **zkSync**. Minimal commonly used targets:

Run:
```bash
make deploy-zk
# or
make deploy-zk-manualToken
```
> The repo also contains examples for zkSync Sepolia targets; use them if you have the required env vars (see **Environment**).


---

##  Testing

Includes **three** categories of tests:

1. **Unit tests** – run entirely on a local Anvil VM.
```bash
   forge test --match-contract ManualTokenTest -vv
``` 
2. **Forked tests** – run against a live network state via RPC.
```bash
   forge test --rpc-url $SEPOLIA_RPC_URL --match-contract <YourForkTest> -vv
```
3. **Staging tests** – execute the actual deploy scripts inside a fork and assert post-deploy state (e.g., initial mint, allowances, `approveAndCall` behavior).
```bash
   forge test --rpc-url $SEPOLIA_RPC_URL --match-contract ManualTokenStagingTest -vv
````  
---
## Coverage

```bash
forge coverage
# For staging coverage, run with a fork URL:
forge coverage --rpc-url $SEPOLIA_RPC_URL --match-contract ManualTokenStagingTest
```
---

##  Formatting
```bash
  forge fmt
```
---

##  Environment & Verification

Create a `.env` file in the project root:
dotenv

---

## zkSync (optional)
```
DEFAULT_ZKSYNC_LOCAL_KEY=0xabc123...deadbeef
ZKSYNC_SEPOLIA_RPC_URL=https://sepolia.era.zksync.dev
ZKSYNC_VERIFIER_URL=https://api-sepolia-era.zksync.network/api
ACCOUNT=your_foundry_account_name   # if using account abstraction in scripts
SENDER=0xYourEOA
```
---

## License

This project is licensed under the [MIT License](LICENSE).

---

## Acknowledgements

* **Cyfrin Updraft** – Thanks to [@patrickalphaC](https://github.com/patrickalphaC) for the educational material
* **Foundry** – For the dev tools

---
