## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## Vaults Hackathon - Sonic Integration

SuperVault is an innovative ERC4626-compliant vault system built on Sonic that leverages artificial intelligence to maximize yield across multiple DeFi protocols. The system's unique architecture ensures capital efficiency by maintaining all assets within the vault contract while dynamically reallocating them between different yield strategies.

### Key Innovation

Our vault implements an AI-powered agent that:

- Continuously monitors yield opportunities across integrated protocols
- Automatically rebalances assets between strategies for optimal returns
- Executes all operations within the vault contract, eliminating external transfer risks
- Makes yield optimization sustainable and reusable through smart contract composability

### Deployed Contracts (Sonic Mainnet)

| Contract   | Address                                      |
| ---------- | -------------------------------------------- |
| SuperVault | `0xc946130d9373b01395c10c63802abdc3fdfca54c` |
| Asset      | `0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E` |

### Features

- ERC4626-compliant vault for seamless integration with other DeFi protocols
- AI-driven yield optimization across multiple strategies
- Automated rebalancing with zero external fund transfers
- Integration with leading protocols (Aave V3, Balancer V2)
- Role-based access control for enhanced security
- Composable architecture enabling strategy reusability
- Real-time yield optimization through AI agent monitoring

### Development

This project uses Foundry for development and testing. Here's how to get started:

### Deployment

To deploy to Sonic:

```shell
$ forge script script/SuperVault.s.sol:DeploySuperVault --rpc-url $SONIC_RPC_URL --broadcast --verify
```

### Environment Setup

1. Copy `.env.example` to `.env`
2. Fill in the required variables:
   ```
   PRIVATE_KEY=your_private_key
   RPC_URL=rpc.soniclabs.com
   SILO_FINANCE_ADDRESS=0x22AacdEc57b13911dE9f188CF69633cC537BdB76
   BEETS_V2_ADDRESS=0xBA12222222228d8Ba445958a75a0704d566BF2C8
   ASSET_ADDRESS=0x29219dd400f2Bf60E5a23d13Be72B486D4038894 (usdc)
   ```

### Testing

```shell
$ forge test
```

### Documentation

For detailed documentation about the vault system and its integration with Sonic, visit our [documentation](https://book.getfoundry.sh/).

### Security

- All contracts are thoroughly tested
- Role-based access control implemented
- Emergency pause functionality
- Timelock for critical operations

### License

This project is licensed under MIT.
