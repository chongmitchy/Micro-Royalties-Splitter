# 💰 Micro-Royalties-Splitter

A smart contract for automatically splitting and distributing royalties among multiple recipients on the Stacks blockchain.

## 🚀 Features

- 📊 **Automatic Distribution**: Automatically splits incoming payments based on predefined percentages
- 👥 **Multi-Recipient Support**: Support for up to 20 recipients with customizable percentage splits
- 🔒 **Owner Controls**: Contract owner can add, remove, and update recipient percentages
- 💳 **Individual Withdrawals**: Recipients can withdraw their earned balance anytime
- 📈 **Detailed Analytics**: Track total received, distributed, and individual recipient earnings
- 🎯 **Micro-Payment Optimized**: Efficient handling of small royalty payments
- 🔍 **Transparent**: All distributions and balances are publicly readable

## 🛠️ Usage

### For Contract Owner

#### Add a Recipient
```clarity
(contract-call? .micro-royalties-splitter add-recipient 'SP1ABC... u25)
```
Adds a recipient with 25% share of all future distributions.

#### Remove a Recipient
```clarity
(contract-call? .micro-royalties-splitter remove-recipient 'SP1ABC...)
```

#### Update Recipient Percentage
```clarity
(contract-call? .micro-royalties-splitter update-recipient-percentage 'SP1ABC... u30)
```

#### Transfer Ownership
```clarity
(contract-call? .micro-royalties-splitter transfer-ownership 'SP1NEW...)
```

### For Anyone

#### Make a Payment/Deposit
```clarity
(contract-call? .micro-royalties-splitter deposit-amount u1000000)
```
Deposits 1 STX and automatically distributes it among all active recipients.

#### Deposit All Available Balance
```clarity
(contract-call? .micro-royalties-splitter deposit)
```

### For Recipients

#### Withdraw Earned Balance
```clarity
(contract-call? .micro-royalties-splitter withdraw)
```

### 📋 Read-Only Functions

#### Check Recipient Information
```clarity
(contract-call? .micro-royalties-splitter get-recipient-info 'SP1ABC...)
```

#### Check Available Balance
```clarity
(contract-call? .micro-royalties-splitter get-recipient-balance 'SP1ABC...)
```

#### Get Distribution Preview
```clarity
(contract-call? .micro-royalties-splitter get-distribution-preview u1000000)
```

#### View All Recipients
```clarity
(contract-call? .micro-royalties-splitter get-all-recipient-data)
```

#### Contract Statistics
```clarity
(contract-call? .micro-royalties-splitter get-total-received)
(contract-call? .micro-royalties-splitter get-total-distributed)
(contract-call? .micro-royalties-splitter get-contract-balance)
```

## 🏗️ Contract Structure

### Data Storage
- **Recipients Map**: Stores recipient info (percentage, earnings, withdrawal history)
- **Balances Map**: Tracks pending withdrawable amounts for each recipient
- **Contract Variables**: Owner, totals, and recipient count

### Key Functions
- `add-recipient`: Add new recipient with percentage
- `deposit-amount`: Accept payment and distribute automatically
- `withdraw`: Allow recipients to claim their earnings
- `get-distribution-preview`: Preview how an amount would be split

## 🔐 Security Features

- ✅ Owner-only functions for recipient management
- ✅ Percentage validation (total cannot exceed 100%)
- ✅ Balance checks before withdrawals
- ✅ Protected against double-spending
- ✅ Proper error handling with descriptive error codes

## 📊 Error Codes

- `u100`: Owner only operation
- `u101`: Recipient not found
- `u102`: Invalid percentage (must be 1-100)
- `u103`: Total percentage exceeds 100%
- `u104`: Insufficient balance
- `u105`: Transfer failed
- `u106`: Recipient already exists
- `u107`: Invalid amount
- `u108`: No recipients configured

## 🚦 Getting Started

1. Deploy the contract using Clarinet
2. Add recipients using `add-recipient`
3. Start receiving payments via `deposit-amount`
4. Recipients can withdraw using `withdraw`

## 📝 Example Workflow

```clarity
;; 1. Owner adds recipients
(contract-call? .micro-royalties-splitter add-recipient 'SP1ARTIST... u40)
(contract-call? .micro-royalties-splitter add-recipient 'SP1PRODUCER... u35)
(contract-call? .micro-royalties-splitter add-recipient 'SP1LABEL... u25)

;; 2. Someone makes a payment
(contract-call? .micro-royalties-splitter deposit-amount u1000000)

;; 3. Recipients withdraw their earnings
(contract-call? .micro-royalties-splitter withdraw)
```

## 🎯 Use Cases

- 🎵 **Music Royalties**: Split streaming revenue between artists, producers, and labels
- 🎮 **Game Revenue**: Distribute earnings among developers, artists, and publishers
- 📚 **Content Creation**: Share revenue from digital content sales
- 🤝 **Joint Ventures**: Automatic profit sharing for business partnerships
- 💻 **Software Licensing**: Distribute license fees among contributors

## 🔧 Development

Built with [Clarinet](https://github.com/hirosystems/clarinet) for the Stacks blockchain.

### Testing
```bash
clarinet check
clarinet test
```

### Deployment
```bash
clarinet deploy
```

---

*Built with ❤️ for the Stacks ecosystem*
