[1mdiff --git a/README.md b/README.md[m
[1mindex 9265b45..a0762b1 100644[m
[1m--- a/README.md[m
[1m+++ b/README.md[m
[36m@@ -1,66 +1,185 @@[m
[31m-## Foundry[m
[32m+[m[32m# Running Foundry Test Scripts[m
 [m
[31m-**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**[m
[32m+[m[32mThis guide explains how to set up Foundry, configure dependencies, and run test scripts for Compound, Aave, and LayerBank integrations.[m
 [m
[31m-Foundry consists of:[m
[32m+[m[32m---[m
 [m
[31m--   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).[m
[31m--   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.[m
[31m--   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.[m
[31m--   **Chisel**: Fast, utilitarian, and verbose solidity REPL.[m
[32m+[m[32m## 1. Install Foundry[m
 [m
[31m-## Documentation[m
[32m+[m[32mFoundry is a Rust-based Ethereum development framework providing tools like `forge`, `cast`, and `anvil` for compiling, deploying, and testing smart contracts.[m
 [m
[31m-https://book.getfoundry.sh/[m
[32m+[m[32m### Install Foundry (Linux/Mac)[m
 [m
[31m-## Usage[m
[32m+[m[32m```sh[m
[32m+[m[32mcurl -L https://foundry.paradigm.xyz | bash[m
[32m+[m[32m```[m
 [m
[31m-### Build[m
[32m+[m[32mAfter installation, reload your shell:[m
[32m+[m[32m```sh[m
[32m+[m[32mfoundryup[m
[32m+[m[32m```[m
 [m
[31m-```shell[m
[31m-$ forge build[m
[32m+[m[32mVerify installation:[m
[32m+[m[32m```sh[m
[32m+[m[32mforge --version[m
 ```[m
 [m
[31m-### Test[m
[32m+[m[32m### Install Foundry (Windows)[m
[32m+[m[32mOption 1: Using Windows Subsystem for Linux (WSL)[m
[32m+[m[32m1. Install WSL and Ubuntu from the Microsoft Store.[m
[32m+[m[32m2. Open WSL and follow the Linux installation steps above.[m
 [m
[31m-```shell[m
[31m-$ forge test[m
[32m+[m[32mOption 2: Using PowerShell[m
[32m+[m[32mRun the following command in PowerShell:[m
[32m+[m[32m```sh[m
[32m+[m[32miwr -useb https://foundry.paradigm.xyz | iex[m
 ```[m
 [m
[31m-### Format[m
[31m-[m
[31m-```shell[m
[31m-$ forge fmt[m
[32m+[m[32mRestart the terminal and run:[m
[32m+[m[32m```sh[m
[32m+[m[32mfoundryup[m
 ```[m
 [m
[31m-### Gas Snapshots[m
[32m+[m[32mVerify installation:[m
[32m+[m[32m```sh[m
[32m+[m[32mforge --version[m
[32m+[m[32m```[m
 [m
[31m-```shell[m
[31m-$ forge snapshot[m
[32m+[m[32m## 2. Clone and Configure the Repository[m
[32m+[m[32mAfter installing Foundry, clone the repository:[m
[32m+[m[32m```sh[m
[32m+[m[32mgit clone https://github.com/polystream-core/polystream-contracts[m
[32m+[m[32mcd polystream-contracts[m
 ```[m
 [m
[31m-### Anvil[m
[32m+[m[32m### Install Dependencies[m
[32m+[m[32mFoundry requires external libraries (Compound, Aave, LayerBank). Install them using `forge install`:[m
 [m
[31m-```shell[m
[31m-$ anvil[m
[32m+[m[32m```sh[m
[32m+[m[32mforge install --no-git "@openzeppelin=openzeppelin/openzeppelin-contracts"[m
[32m+[m[32mforge install --no-git "@compound=compound-finance/comet"[m
[32m+[m[32mforge install --no-git "@aave=aave/aave-v3-core"[m
[32m+[m[32mforge install --no-git "@layerbank-contracts=layerbank/layerbank-core"[m
[32m+[m[32mforge install --no-git "@forge-std=foundry-rs/forge-std"[m
[32m+[m[32mforge install --no-git "@account-abstraction=account-abstraction/contracts"[m
 ```[m
[32m+[m[32mThis command ensures all dependencies are placed in the `lib/` directory.[m
[32m+[m
[32m+[m[32m#### Update Foundry Configuration[m
[32m+[m[32mModify the `foundry.toml` file to include the following settings:[m
[32m+[m[32m```sh[m
[32m+[m[32m[profile.default][m
[32m+[m[32msrc = "src"[m
[32m+[m[32mout = "out"[m
[32m+[m[32mlibs = ["lib"][m
[32m+[m[32mvia_ir = true[m
[32m+[m[32moptimizer = true[m
[32m+[m[32moptimizer_runs = 200[m
[32m+[m[32mremappings = [[m
[32m+[m[32m    "@syncswapcontracts/=lib/core-contracts/contracts/",[m
[32m+[m[32m    "@layerbank-contracts/=lib/contracts/",[m
[32m+[m[32m    "@openzeppelin/=lib/openzeppelin-contracts/",[m
[32m+[m[32m    "@aave/=lib/aave-v3-origin/src/",[m
[32m+[m[32m    "@forge-std/=lib/forge-std/src/",[m
[32m+[m[32m    "@account-abstraction/=lib/account-abstraction/contracts/",[m
[32m+[m[32m    "@compound/=lib/comet/contracts/"[m
[32m+[m[32m][m
[32m+[m
[32m+[m[32m# See more config options https://github.com/foundry-rs/foundry/blob/master/crates/config/README.md#all-options[m
[32m+[m[32m```[m
[32m+[m[32mThis configuration:[m
[32m+[m[32m- Enables IR-based compilation (`via_ir = true`) for optimized bytecode.[m
[32m+[m[32m- Enables Solidity optimizer with 200 runs (`optimizer = true`).[m
[32m+[m[32m- Defines remappings for external dependencies.[m
[32m+[m[32m- Specifies `src/` as the source directory and `lib/` as the library directory.[m
[32m+[m
[32m+[m[32m## 3. Run a Local Fork with Anvil[m
[32m+[m[32mAnvil is a fast Ethereum RPC fork provider for running local blockchain simulations.[m
 [m
[31m-### Deploy[m
[32m+[m[32m#### Start Anvil with Forking[m
[32m+[m[32mRun the following command to start an Anvil instance:[m
 [m
[31m-```shell[m
[31m-$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>[m
[32m+[m[32m```sh[m
[32m+[m[32manvil --fork-url https://your-rpc-url.com --chain-id YOUR_CHAIN_ID[m
 ```[m
[32m+[m[32mReplace:[m
[32m+[m[32m- `https://your-rpc-url.com` with your Ethereum RPC provider (Alchemy, Infura, QuickNode, etc.).[m
[32m+[m[32m- `YOUR_CHAIN_ID` with the actual Chain ID of the blockchain you're testing (e.g., `1` for Ethereum, `534352` for Scroll).[m
 [m
[31m-### Cast[m
[32m+[m[32mExample for Scroll Mainnet (using Alchemy):[m
[32m+[m[32m```sh[m
[32m+[m[32manvil --fork-url https://scroll-mainnet.g.alchemy.com/v2/YOUR_ALCHEMY_KEY --chain-id 534352[m
[32m+[m[32m```[m
[32m+[m[32mWhat This Does:[m
[32m+[m[32m- Forks the mainnet, allowing contract interactions as if on mainnet.[m
[32m+[m[32m- Persists the blockchain state, so transactions behave realistically.[m
[32m+[m[32m- Runs a local RPC server (`127.0.0.1:8545`) for Foundry tests.[m
[32m+[m
[32m+[m[32m## Run Foundry Tests[m
[32m+[m[32mNavigate to the Test Directory[m
[32m+[m[32m```sh[m
[32m+[m[32mcd test[m
[32m+[m[32m```[m
 [m
[31m-```shell[m
[31m-$ cast <subcommand>[m
[32m+[m[32mRun a Specific Test[m
[32m+[m[32mUse the following command:[m
[32m+[m[32m```sh[m
[32m+[m[32mforge test --fork-url http://127.0.0.1:8545 --match-path test/YOUR_TEST_SCRIPT.t.sol -vvv[m
[32m+[m[32m```[m
[32m+[m[32mReplace `YOUR_TEST_SCRIPT.t.sol` with the actual test file name.[m
[32m+[m[32mExample:[m
[32m+[m[32m```sh[m
[32m+[m[32mforge test --fork-url http://127.0.0.1:8545 --match-path test/CompoundAdapterTest.t.sol -vvv[m
 ```[m
[32m+[m[32mExplanation of Flags:[m
[32m+[m[32m- --fork-url `http://127.0.0.1:8545`→ Connects to the locally running Anvil fork.[m
[32m+[m[32m- `--match-path test/YOUR_TEST_SCRIPT.t.sol` → Runs a specific test script.[m
[32m+[m[32m- `-vvv` → Enables verbose mode (displays logs, transactions, and errors).[m
[32m+[m
[32m+[m[32m## 5. Log Successful Test Runs[m
[32m+[m[32mUse the following command to log test results and store them in a file:[m
[32m+[m[32m```sh[m
[32m+[m[32mforge test --fork-url http://127.0.0.1:8545 -vvv | tee test-results.log[m
[32m+[m[32m```[m
[32m+[m[32m`tee test-results.log` → Saves all logs to test-results.log.[m
 [m
[31m-### Help[m
[32m+[m[32mReview logs by opening the file:[m
[32m+[m[32m```sh[m
[32m+[m[32mcat test-results.log[m
[32m+[m[32m```[m
 [m
[31m-```shell[m
[31m-$ forge --help[m
[31m-$ anvil --help[m
[31m-$ cast --help[m
[32m+[m[32mExample Running Test Script for Combined Vault