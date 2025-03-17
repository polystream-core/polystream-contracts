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

- [Yield Optimizer](https://automation.chain.link/base-sepolia/107443536759514165874241348299091642006288174294890837793929995441409617679000)
- [Check & Harvest](https://automation.chain.link/base-sepolia/87721494756957191100234032125401142591208032377220498353673678292683728673730)

### Medium Risk

- [Yield Optimizer](https://automation.chain.link/base-sepolia/98314516364213539040790969844350770599744547289741055073636813964628480151061)
- [Check & Harvest](https://automation.chain.link/base-sepolia/111354042029573592214927345359678256484228151768938293740336212040373641721436)

### High Risk

- [Yield Optimizer](https://automation.chain.link/base-sepolia/5722856465140387540441604925408038381342243203718227198244158903361646393851)
- [Check & Harvest](https://automation.chain.link/base-sepolia/9221094301717693037134162986003226806540908205494210047742633189647059819185)


For further technical details and integration guidelines, please visit our [documentation](https://docs.polystream.xyz).



## Development

### Installation

Clone the repository and install dependencies:

```bash
git clone https://github.com/your-repo/polystream-contracts.git
cd polystream-contracts
forge install
```

### Compilation

Compile contracts using Forge:

```bash
forge build
```

### Testing

Run tests with Forge:

```bash
forge test
```

## Deployment

Contracts are deployed on:

- **Scroll Sepolia Testnet**
- **Base Sepolia Testnet**

Refer to [Contract Addresses](https://docs.polystream.xyz) for deployed addresses.

## Documentation

Detailed technical documentation and architecture can be found on [Polystream Docs](https://docs.polystream.xyz).

## Contributing

Contributions and suggestions are welcome. Please open a pull request or issue to discuss proposed changes.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

