# ETF Strategy Uniswap V4 Hook

**An ETF-focused tax strategy implementation using Uniswap V4 Hooks 🦄💰**

### Overview

This project implements a sophisticated tax strategy hook for Uniswap V4 that enables ETF-like fee collection and distribution. The hook automatically collects fees on swaps and distributes them between a strategy treasury (for ETF operations) and a development address (for operational costs).

### Key Features

- **Automated Fee Collection**: 10% fee on all swaps through the pool
- **Dual Fee Distribution**: 90% to strategy treasury, 10% to dev operations
- **ETH Conversion**: Automatically converts fee tokens to ETH for simplified treasury management
- **Strategy Token Integration**: Custom ERC20 token with treasury management capabilities
- **Comprehensive Testing**: Full test suite covering all fee scenarios and edge cases

### Project Structure

```
src/
├── contracts/
│   ├── StandardToken.sol          # Basic ERC20 token implementation
│   └── StrategyTokenSample.sol    # ETF strategy token with treasury integration
├── hooks/
│   └── TaxStrategyHook.sol        # Main hook implementing tax strategy
└── mocks/
    ├── MockTaxStrategy.sol        # Mock implementation for testing
    └── MockWETH.sol              # Mock WETH for test scenarios

script/
├── 00_DeployHook.s.sol           # Deploy the tax strategy hook
├── 01_CreatePoolAndAddLiquidity.s.sol # Initialize pool with liquidity
├── 02_AddLiquidity.s.sol         # Add additional liquidity
└── 03_Swap.s.sol                 # Execute swaps to test fee collection

test/
├── TaxStrategyHookTest.t.sol     # Comprehensive hook testing
└── utils/                        # Testing utilities and helpers
```

### Core Components

#### TaxStrategyHook
- Implements `afterSwap` hook to collect fees
- Collects 10% fee on all swap amounts
- Automatically converts fees to ETH
- Distributes 90% to strategy treasury, 10% to dev address
- Supports fee address updates by current fee recipient

#### StrategyTokenSample
- ERC20 token with integrated treasury functionality
- Includes `addFees()` method for receiving ETH from hooks
- Supports token burning and treasury address updates
- Designed for ETF strategy token implementations

### Quick Start

1. **Install Dependencies**
```bash
forge install
```

2. **Run Tests**
```bash
forge test -vv
```

3. **Deploy Locally**
```bash
# Start local anvil node
anvil

# Deploy hook and setup pool
forge script script/00_DeployHook.s.sol --rpc-url http://localhost:8545 --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d --broadcast

# Create pool and add initial liquidity
forge script script/01_CreatePoolAndAddLiquidity.s.sol --rpc-url http://localhost:8545 --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d --broadcast

# Test swaps and fee collection
forge script script/03_Swap.s.sol --rpc-url http://localhost:8545 --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d --broadcast
```

### Fee Strategy Details

The tax strategy hook implements the following fee structure:

- **Collection Rate**: 10% of swap amount (`HOOK_FEE_PERCENTAGE = 10000`)
- **Strategy Treasury**: 90% of collected fees (`STRATEGY_FEE_PERCENTAGE = 90000`)
- **Development Fund**: 10% of collected fees (remainder)
- **Fee Denominator**: 100,000 for precise percentage calculations

#### Fee Flow
1. User executes swap through Uniswap V4 pool
2. Hook collects 10% fee from the swap amount
3. If fee token is not ETH, hook converts it to ETH via internal swap
4. 90% of ETH fee sent to strategy token's treasury via `addFees()`
5. 10% of ETH fee sent to designated fee recipient address

### Configuration

Update the following parameters in your deployment scripts:

1. **Token Addresses** (`BaseScript.sol`):
   - Update `token0` and `token1` addresses for your target network
   - Ensure proper ETH/Token pairing

2. **Liquidity Amounts** (`CreatePoolAndAddLiquidity.s.sol`, `AddLiquidity.s.sol`):
   - Adjust `token0Amount` and `token1Amount` for initial liquidity
   - Consider price impact and slippage

3. **Swap Parameters** (`Swap.s.sol`):
   - Modify `amountIn` and `amountOutMin` for testing
   - Adjust for different swap scenarios

4. **Fee Recipients**:
   - Set appropriate treasury address in strategy token constructor
   - Configure dev fee recipient address in hook constructor


### Requirements

- **Foundry** (stable version recommended)
- **Solidity 0.8.26** (required for Uniswap V4 transient storage)
- **Node.js** (optional, for additional tooling)

Update Foundry to the latest stable version:
```bash
foundryup
```

### Production Deployment

#### Using Keystore (Recommended)

1. **Add Private Key to Keystore**:
```bash
cast wallet import <WALLET_NAME> --interactive
```

2. **Deploy with Keystore**:
```bash
forge script script/00_DeployHook.s.sol \
    --rpc-url <YOUR_RPC_URL> \
    --account <WALLET_NAME> \
    --sender <YOUR_WALLET_ADDRESS> \
    --broadcast
```

#### Using Environment Variables

1. **Set Environment Variables**:
```bash
export PRIVATE_KEY=<your_private_key>
export RPC_URL=<your_rpc_url>
```

2. **Deploy**:
```bash
forge script script/00_DeployHook.s.sol \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast
```

### Testing

The project includes comprehensive tests covering:

- Fee collection mechanics
- ETH conversion functionality  
- Treasury and dev fee distribution
- Edge cases and error conditions
- Integration with Uniswap V4 pool manager

Run tests with different verbosity levels:
```bash
# Basic test run
forge test

# Detailed output
forge test -vv

# Very detailed with traces
forge test -vvv

# Specific test contract
forge test --match-contract TaxStrategyHookTest
```

### Troubleshooting

#### Common Issues

**Permission Denied During Installation**
- Ensure GitHub SSH keys are properly configured
- Follow [GitHub SSH setup guide](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)

**Anvil Fork Test Failures**
- Some Foundry versions limit contract code size to ~25kb
- Solution: Start anvil with increased code size limit
```bash
anvil --code-size-limit 40000
```

**Hook Deployment Failures**
1. **Verify Hook Flags**: Ensure `getHookPermissions()` returns correct flags matching `HookMiner.find()` requirements
2. **Salt Mining Issues**: 
   - In tests: Deployer must match between `new Hook{salt: salt}()` and `HookMiner.find(deployer, ...)`
   - In scripts: Deployer must be CREATE2 Proxy: `0x4e59b44847b379578588920cA78FbF26c0B4956C`
3. **Update Foundry**: Ensure latest version with `foundryup`

**Fee Collection Issues**
- Verify pool has sufficient liquidity for fee token -> ETH conversion
- Check that fee recipient addresses are properly configured
- Ensure strategy token treasury address is set correctly

**Gas Estimation Failures**
- Increase gas limit in deployment scripts
- Use `--with-gas-price` flag for better gas estimation
- Consider using `--legacy` flag for older networks

### Additional Resources

- [Uniswap V4 Documentation](https://docs.uniswap.org/contracts/v4/overview)
- [V4 Core Repository](https://github.com/uniswap/v4-core)
- [V4 Periphery Repository](https://github.com/uniswap/v4-periphery)
- [V4 Examples and Tutorials](https://v4-by-example.org)
- [Foundry Documentation](https://book.getfoundry.sh/)
- [Solidity Documentation](https://docs.soliditylang.org/)

### License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Acknowledgments

- Uniswap Foundation for V4 architecture and templates
- OpenZeppelin for secure contract implementations
- Foundry team for excellent development tooling
