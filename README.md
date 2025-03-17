# Polystream Smart Contracts

This repository contains the smart contracts for Polystream, a DeFi protocol designed to optimize yield generation through automated strategies across multiple lending and yield farming platforms. The repository is structured into several categories:

## Contracts Overview

### Adapters

Adapters serve as intermediaries between the Polystream vault and external DeFi protocols, implementing a standard interface (`IProtocolAdapter`) for interacting with various lending and yield farming platforms.

- `AaveAdapter.sol`: Interacts with the Aave V3 protocol for asset deposits, withdrawals, and yield harvesting.
- `LayerBankAdapter.sol`: Connects to the LayerBank protocol, supporting deposits, withdrawals, yield calculations, and interest harvesting.
- `IProtocolAdapter.sol`: Defines the standard interface for all protocol adapters, ensuring consistency across interactions.

### Core

The core contracts handle fundamental vault operations, asset management, and protocol integrations:

- `CombinedVault.sol`: Manages user deposits, withdrawals, and epoch-based yield harvesting. Implements advanced time-weighted accounting for accurate reward distribution.
- `ProtocolRegistry.sol`: Maintains a registry of supported protocols and their respective adapters, allowing dynamic integration and management of different yield sources.
- `IVault.sol`, `IRegistry.sol`: Interfaces defining required functionalities for vault and registry contracts.

### Rewards

The rewards contracts handle distribution of yield harvested from integrated protocols back to vault participants:

- `RewardManager.sol`: Tracks and manages the calculation and distribution of rewards based on users' time-weighted contributions to the vault.
- `IRewardManager.sol`: Defines the interface for reward management functionalities.

### Strategy

The strategy contracts automate and optimize yield farming strategies:

- `YieldOptimizer.sol`: Automatically selects the best-performing protocol (highest APY) for depositing assets at each epoch, leveraging Chainlink automation for regular updates.

## Key Features

- **Automated Yield Optimization**: Dynamically shifts assets between protocols based on real-time APY comparisons.
- **Epoch-based Reward Distribution**: Rewards are calculated and distributed based on epoch intervals to accurately reflect user contributions.
- **Protocol Flexibility**: Modular adapter design allows easy integration of additional DeFi protocols.
- **Account Abstraction (ERC-4337)**: Provides users with seamless interactions and improved UX through smart accounts and gasless transactions.

## Contract Addresses

### Scroll Sepolia Contracts

| Contract | Address |
|---|---|
| MockUSDC | [0x1d089e4b7697e2ae810731740d1ce005a04a631e](https://sepolia.scrollscan.dev/address/0x1d089e4b7697e2ae810731740d1ce005a04a631e) |
| ProtocolRegistry | [0x753d1Bb295c5543f15500C020C2981515918eBb5](https://sepolia.scrollscan.dev/address/0x753d1Bb295c5543f15500C020C2981515918eBb5) |
| CombinedVault | [0x4b935D786C207Ee20152893B67cA5a92cc146B78](https://sepolia.scrollscan.dev/address/0x4b935D786C207Ee20152893B67cA5a92cc146B78) |
| YieldOptimizer | [0x9dfD058D3a332dAaA46fc0cFacFC857472902032](https://sepolia.scrollscan.dev/address/0x9dfD058D3a332dAaA46fc0cFacFC857472902032) |
| MockAaveAdapter | [0x17c25D7A3c8B3e79ff7C488D140635DB8a62b5F4](https://sepolia.scrollscan.dev/address/0x17c25D7A3c8B3e79ff7C488D140635DB8a62b5F4) |
| MockCompoundAdapter | [0x989b87198D66A8df5c7901752e4241f212413F00](https://sepolia.scrollscan.dev/address/0x989b87198D66A8df5c7901752e4241f212413F00) |
| MockLayerBankAdapter | [0x00EE29eA9177F05DB670AF7493D91c00e204A38B](https://sepolia.scrollscan.dev/address/0x00EE29eA9177F05DB670AF7493D91c00e204A38B) |

## Mainnet-Compatible Adapters
| Contract | Address |
|---|---|
| AaveAdapter | [0xBBb91b3d5B8a9cbd653efC42b3C08358E75A1b90](https://scrollscan.com/address/0xBBb91b3d5B8a9cbd653efC42b3C08358E75A1b90) |
| LayerBankAdapter | [0x3599C2CB151D7D8CE4242B2E19dF0Ba6b474EeBA](https://scrollscan.com/address/0x3599C2CB151D7D8CE4242B2E19dF0Ba6b474EeBA) |
| SyncSwapAdapter | [0x21B021ea2925a43025A783976D64Ee3B8015E6F6](https://scrollscan.com/address/0x21B021ea2925a43025A783976D64Ee3B8015E6F6) |
| CompoundAdapter | [0xE0420B6EAf66cb13B94a8942058b59a15c38e356](https://scrollscan.com/address/0xE0420B6EAf66cb13B94a8942058b59a15c38e356) |

## Base Sepolia Contracts

### ERC-4337 Implementations
| Contract | Address |
|---|---|
| K1ValidatorFactory | [0x2828A0E0f36d8d8BeAE95F00E2BbF235e4230fAc](https://sepolia.basescan.org/address/0x2828A0E0f36d8d8BeAE95F00E2BbF235e4230fAc) |
| Entrypoint (v0.7.0) | [0x0000000071727De22E5E9d8BAf0edAc6f37da032](https://sepolia.basescan.org/address/0x0000000071727De22E5E9d8BAf0edAc6f37da032) |
| Paymasters | [0x00000072a5f551d6e80b2f6ad4fb256a27841bbc](https://sepolia.basescan.org/address/0x00000072a5f551d6e80b2f6ad4fb256a27841bbc) |

## Vault Contracts

### High Risk

- MockUSDC: [0x78bD59b3d9DAbDab8A39958E32dA04CCe9E2E6e8](https://sepolia.basescan.org/address/0x78bD59b3d9DAbDab8A39958E32dA04CCe9E2E6e8)
- ProtocolRegistry: [0xC16F0f7A9e8F7C4E08B317B184d69e21129A9Ba4](https://sepolia.basescan.org/address/0xC16F0f7A9e8F7C4E08B317B184d69e21129A9Ba4)
- MockAaveAdapter: [0xa95783A0AdE0D8f95b1E42c46d7E64A289E81e80](https://sepolia.basescan.org/address/0xa95783A0AdE0D8f95b1E42c46d7E64A289E81e80)
- MockLayerBankAdapter: [0xA668fe5a33422D616484B030E0b568D769A62BF4](https://sepolia.basescan.org/address/0xA668fe5a33422D616484B030E0b568D769A62BF4)
- CombinedVault: [0xB309Ae62D176bDa6DfE469f1406292a7543fBF49](https://sepolia.basescan.org/address/0xB309Ae62D176bDa6DfE469f1406292a7543fBF49)
- YieldOptimizer: [0x888C7a03e25Cb398F6f848419eEc36af458f153A](https://sepolia.basescan.org/address/0x888C7a03e25Cb398F6f848419eEc36af458f153A)

### Medium Risk

- ProtocolRegistry: [0x16c321aE69165a1903Cbb47C563113575881A322](https://sepolia.basescan.org/address/0x16c321aE69165a1903Cbb47C563113575881A322)
- MockAaveAdapter: [0x3A63fb5CD3f1A05eB6179E5ac50b3B1B3F637993](https://sepolia.basescan.org/address/0x3A63fb5CD3f1A05eB6179E5ac50b3B1B3F637993)
- MockLayerBankAdapter: [0xe6870e61765a26e4fb1E922318C9F08Ac4E0B09E](https://sepolia.basescan.org/address/0xe6870e61765a26e4fb1E922318C9F08Ac4E0B09E)
- CombinedVault: [0x1FB4128dAac9EFf5c10A3f1De2C2365e8636885a](https://sepolia.basescan.org/address/0x1FB4128dAac9EFf5c10A3f1De2C2365e8636885a)
- YieldOptimizer: [0x3F3B713c0Fe6e37feCB9E471451be4e5De77dDCd](https://sepolia.basescan.org/address/0x3F3B713c0Fe6e37feCB9E471451be4e5De77dDCd)

### Low Risk

- ProtocolRegistry: [0x32c7978865C87def85029307Db05129C33103f8C](https://sepolia.basescan.org/address/0x32c7978865C87def85029307Db05129C33103f8C)
- MockAaveAdapter: [0x200FE13eB88aa53Be3671dc49573b4eeDD4DB9F2](https://sepolia.basescan.org/address/0x200FE13eB88aa53Be3671dc49573b4eeDD4DB9F2)
- MockLayerBankAdapter: [0xEFF624A3E34e2EaC412ba734244B5fB220633e7c](https://sepolia.basescan.org/address/0xEFF624A3E34e2EaC412ba734244B5fB220633e7c)
- CombinedVault: [0xb36881666A9f886Aee2C21e5490983782C76D8F8](https://sepolia.basescan.org/address/0xb36881666A9f886Aee2C21e5490983782C76D8F8)
- YieldOptimizer: [0x288936D022EcCA9d48354C691B16B12e3aea351C](https://sepolia.basescan.org/address/0x288936D022EcCA9d48354C691B16B12e3aea351C)

### Base Mainnet Production-Ready (Non-mock)
- CompoundAdapter: [0x03a1E7f27cF9FDC3b391f9cbAdA38867C8542B1C](https://basescan.org/address/0x03a1E7f27cF9FDC3b391f9cbAdA38867C8542B1C)


## 🔗 Chainlink Automation Upkeeps

**Yield Optimizer and Check & Harvest automation details**
### Low Risk

- [Yield Optimizer](https://automation.chain.link/base-sepolia/19592633126236891682666043125258171533116166520941179685825646141645925432339)
- [Check & Harvest](https://automation.chain.link/base-sepolia/87721494756957191100234032125401142591208032377220498353673678292683728673730)

### Medium Risk

- [Yield Optimizer](https://automation.chain.link/base-sepolia/98314516364213539040790969844350770599744547289741055073636813964628480151061)
- [Check & Harvest](https://automation.chain.link/base-sepolia/111354042029573592214927345359678256484228151768938293740336212040373641721436)

### High Risk

- [Yield Optimizer](https://automation.chain.link/base-sepolia/5722856465140387540441604925408038381342243203718227198244158903361646393851)
- [Check & Harvest](https://automation.chain.link/base-sepolia/9221094301717693037134162986003226806540908205494210047742633189647059819185)


# Running Foundry Test Scripts

This guide explains how to set up Foundry, configure dependencies, and run test scripts for Compound, Aave, and LayerBank integrations.

---

## 1. Install Foundry

Foundry is a Rust-based Ethereum development framework providing tools like `forge`, `cast`, and `anvil` for compiling, deploying, and testing smart contracts.

### Install Foundry (Linux/Mac)

```sh
curl -L https://foundry.paradigm.xyz | bash
```

After installation, reload your shell:
```sh
foundryup
```

Verify installation:
```sh
forge --version
```

### Install Foundry (Windows)
Option 1: Using Windows Subsystem for Linux (WSL)
1. Install WSL and Ubuntu from the Microsoft Store.
2. Open WSL and follow the Linux installation steps above.

Option 2: Using PowerShell
Run the following command in PowerShell:
```sh
iwr -useb https://foundry.paradigm.xyz | iex
```

Restart the terminal and run:
```sh
foundryup
```

Verify installation:
```sh
forge --version
```

## 2. Clone and Configure the Repository
After installing Foundry, clone the repository:
```sh
git clone https://github.com/polystream-core/polystream-contracts
cd polystream-contracts
```

### Install Dependencies
Foundry requires external libraries (Compound, Aave, LayerBank). Install them using `forge install`:

```sh
forge install --no-git "@openzeppelin=openzeppelin/openzeppelin-contracts"
forge install --no-git "@compound=compound-finance/comet"
forge install --no-git "@aave=aave/aave-v3-core"
forge install --no-git "@layerbank-contracts=layerbank/layerbank-core"
forge install --no-git "@forge-std=foundry-rs/forge-std"
forge install --no-git "@account-abstraction=account-abstraction/contracts"
```
This command ensures all dependencies are placed in the `lib/` directory.

#### Update Foundry Configuration
Modify the `foundry.toml` file to include the following settings:
```sh
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
via_ir = true
optimizer = true
optimizer_runs = 200
remappings = [
    "@syncswapcontracts/=lib/core-contracts/contracts/",
    "@layerbank-contracts/=lib/contracts/",
    "@openzeppelin/=lib/openzeppelin-contracts/",
    "@aave/=lib/aave-v3-origin/src/",
    "@forge-std/=lib/forge-std/src/",
    "@account-abstraction/=lib/account-abstraction/contracts/",
    "@compound/=lib/comet/contracts/"
]

# See more config options https://github.com/foundry-rs/foundry/blob/master/crates/config/README.md#all-options
```
This configuration:
- Enables IR-based compilation (`via_ir = true`) for optimized bytecode.
- Enables Solidity optimizer with 200 runs (`optimizer = true`).
- Defines remappings for external dependencies.
- Specifies `src/` as the source directory and `lib/` as the library directory.

## 3. Run a Local Fork with Anvil
Anvil is a fast Ethereum RPC fork provider for running local blockchain simulations.

#### Start Anvil with Forking
Run the following command to start an Anvil instance:

```sh
anvil --fork-url https://your-rpc-url.com --chain-id YOUR_CHAIN_ID
```
Replace:
- `https://your-rpc-url.com` with your Ethereum RPC provider (Alchemy, Infura, QuickNode, etc.).
- `YOUR_CHAIN_ID` with the actual Chain ID of the blockchain you're testing (e.g., `1` for Ethereum, `534352` for Scroll).

Example for Scroll Mainnet (using Alchemy):
```sh
anvil --fork-url https://scroll-mainnet.g.alchemy.com/v2/YOUR_ALCHEMY_KEY --chain-id 534352
```
What This Does:
- Forks the mainnet, allowing contract interactions as if on mainnet.
- Persists the blockchain state, so transactions behave realistically.
- Runs a local RPC server (`127.0.0.1:8545`) for Foundry tests.

## Run Foundry Tests
Navigate to the Test Directory
```sh
cd test
```

Run a Specific Test
Use the following command:
```sh
forge test --fork-url http://127.0.0.1:8545 --match-path test/YOUR_TEST_SCRIPT.t.sol -vvv
```
Replace `YOUR_TEST_SCRIPT.t.sol` with the actual test file name.
Example:
```sh
forge test --fork-url http://127.0.0.1:8545 --match-path test/AaveAdapterTest.t.sol -vvv
```
Explanation of Flags:
- --fork-url `http://127.0.0.1:8545`→ Connects to the locally running Anvil fork.
- `--match-path test/YOUR_TEST_SCRIPT.t.sol` → Runs a specific test script.
- `-vvv` → Enables verbose mode (displays logs, transactions, and errors).

## 5. Log Successful Test Runs
Use the following command to log test results and store them in a file:
```sh
forge test --fork-url http://127.0.0.1:8545 -vvv | tee test-results.log
```
`tee test-results.log` → Saves all logs to test-results.log.

Review logs by opening the file:
```sh
cat test-results.log
```

Example Running Test Script for Combined Vault
```sh
forge test --fork-url http://127.0.0.1:8545 --match-path test/CombinedVault.t.sol -vvv
```
If successful, the output will look like:
```sh
Ran 8 tests for test/CombinedVault.t.sol:CombinedVaultTest
[PASS] testEarlyWithdrawalFee() (gas: 607134)
Logs:
  User 1 USDC balance: 1000000000
  User 2 USDC balance: 1000000000
  Distributing assets to Active Protocol ID: 1
  Supplied to Protocol ID: 1 Amount: 100000000
  Initial USDC balance before withdrawal: 900000000
  Final USDC balance after withdrawal: 995000000
  Actual received: 95000000
  Expected to receive: 95000000
  Early withdrawal fee test passed

// ... other test cases

Suite result: ok. 8 passed; 0 failed; 0 skipped; finished in 2.24s (13.10s CPU time)      

Ran 1 test suite in 2.28s (2.24s CPU time): 8 tests passed, 0 failed, 0 skipped (8 total tests)
```

## Summary

| Step                 | Command                                        | Description |
|----------------------|-----------------------------------------------|-------------|
| **Install Foundry**  | `foundryup`                                   | Installs Foundry tools (`forge`, `cast`, `anvil`) |
| **Clone Repository** | `git clone YOUR_REPO`                         | Clones the project to your local machine |
| **Install Dependencies** | `forge install ...`                        | Installs external libraries like Compound, Aave, LayerBank |
| **Start Anvil**      | `anvil --fork-url YOUR_RPC_URL --chain-id YOUR_CHAIN_ID` | Runs a local forked blockchain |
| **Run Tests**        | `forge test --fork-url http://127.0.0.1:8545 -vvv` | Runs tests against the forked blockchain |

## Documentation

Detailed technical documentation and architecture can be found on [Polystream Docs](https://docs.polystream.xyz).

## Contributing

Contributions and suggestions are welcome. Please open a pull request or issue to discuss proposed changes.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

