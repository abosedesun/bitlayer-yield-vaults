# BitLayer Yield Vaults - Protocol Documentation

## Overview

BitLayer Yield Vaults is a sophisticated yield optimization protocol built natively on Bitcoin via Stacks Layer 2. This non-custodial solution offers institutional-grade strategy management with three distinct risk profiles, combining automated asset allocation with Bitcoin's security model.

## Key Features

- **Risk-Tiered Strategies**
  - 🛡 Conservative (Stablecoin Lending)
  - ⚖ Balanced (Liquid Staking)
  - 🚀 Growth (High-Yield Farming)
- **Multi-Protocol Exposure**
  - Integrated with Stackswap, Arkadiko, ALEX, and Zest
  - Dynamic TVL-weighted allocations
- **Advanced Automation**
  - Smart auto-compounding engine
  - Real-time APY oracle updates
  - Emergency withdrawal triggers
- **Bitcoin-Centric Security**
  - STX settlement finality
  - Multisig treasury management
  - Strategy freeze capabilities

## Architecture

### Core Components

1. **Strategies**

   ```clarity
   (define-map strategies { strategy-id: uint } { ... })
   ```

   - Three predefined risk tiers with protocol allocations
   - TVL tracking and APY calculations
   - Locking mechanisms for capital protection

2. **Protocol Integrations**

   ```clarity
   (define-map protocol-info { protocol-id: uint } { ... })
   ```

   - Current APY tracking
   - Active/inactive status management
   - Last updated timestamps

3. **User Management**

   ```clarity
   (define-map user-balances { user: principal, strategy: uint } uint)
   (define-map user-strategy-info ...)
   ```

   - Custom compounding schedules
   - Personal emergency thresholds
   - Deposit history tracking

4. **Fee Structure**
   - Withdrawal Fees: 0.5%-2% based on strategy
   - Performance Fees: 10%-20% on yields
   - Treasury Address: Contract-managed reserve

## Smart Contract Functions

### User Operations

| Function                  | Parameters                 | Description                           |
| ------------------------- | -------------------------- | ------------------------------------- |
| `deposit`                 | `(strategy-id, amount)`    | Allocate funds to specified strategy  |
| `withdraw`                | `(strategy-id, amount)`    | Partial withdrawal with fee deduction |
| `withdraw-all`            | `(strategy-id)`            | Full position liquidation             |
| `compound-rewards`        | `(user, strategy-id)`      | Manual reward compounding trigger     |
| `set-emergency-threshold` | `(strategy-id, threshold)` | Custom APY floor setting              |

### Strategy Management

| Function                  | Description                       | Access |
| ------------------------- | --------------------------------- | ------ |
| `rebalance-strategy`      | Recalculate protocol allocations  | Owner  |
| `update-protocol-apy`     | Modify integrated protocol yields | Owner  |
| `activate-emergency-mode` | Halt deposits/withdrawals         | Owner  |

### Administrative Functions

| Function                      | Purpose                  | Lock     |
| ----------------------------- | ------------------------ | -------- |
| `update-strategy-allocations` | Modify protocol weights  | 24h      |
| `withdraw-treasury`           | Treasury fund management | Multisig |
| `add-to-emergency-fund`       | Capital reserve top-up   | Public   |

## Security Model

### Bitcoin-Native Protections

1. **Withdrawal Finality**

   - All transactions settled through Bitcoin L1
   - STX-based atomic swaps

2. **Circuit Breakers**

   ```clarity
   (define-data-var emergency-fund uint u0)
   ```

   - 5% TVL emergency reserve
   - Strategy-specific emergency modes

3. **Temporal Locks**
   - 24-hour delay on critical parameter changes
   - Multi-sig authorization requirements

## Fee Structure

| Strategy Type | Withdrawal Fee | Performance Fee | Min Deposit |
| ------------- | -------------- | --------------- | ----------- |
| Conservative  | 0.5%           | 10%             | 1 STX       |
| Balanced      | 1%             | 15%             | 10 STX      |
| Growth        | 2%             | 20%             | 50 STX      |
