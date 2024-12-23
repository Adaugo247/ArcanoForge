
## README for **ArcanaForge Smart Contract**

### Overview

**ArcanaForge** is a smart contract for a blockchain-based **Fantasy Card Game Marketplace and Tournament Platform**. It enables players, collectors, and organizers to mint, trade, and manage fantasy game cards while hosting competitive tournaments. With features like rarity bonuses, safe trading, and prize pools, **ArcanaForge** aims to create a robust and transparent ecosystem for card game enthusiasts.

---

### Features

1. **Card Management**:
   - Mint new cards with customizable data.
   - Assign rarity bonuses and manage card ownership.
   - Lock cards for tournament use or safe transfers.

2. **Marketplace**:
   - Trade cards with other players securely.
   - Set prices for listed cards or host auctions.
   - Built-in platform fee for trades ensures sustainability.

3. **Tournament System**:
   - Create and manage tournaments with customizable rules and prize pools.
   - Lock stakes and reward participants based on outcomes.

4. **Seasonal Rewards**:
   - Distribute rewards to participants based on performance in seasonal cycles.

5. **Admin Controls**:
   - Lock or unlock the system for maintenance.
   - Update the treasury wallet for fee collection.
   - Enable maintenance mode for upgrades or critical fixes.

6. **Error Handling**:
   - Comprehensive error codes to handle invalid operations (e.g., unauthorized access, low balance, invalid card IDs).

---

### Core Components

#### **Fungible Tokens**
- **`card-fragments`**: Utility tokens for card-related operations.
- **`arena-token`**: Token for tournament participation.
- **`battle-points`**: Rewards for competitive activities.

#### **Data Structures**
- **`cards`**: Stores metadata and ownership details for game cards.
- **`trade-listings`**: Manages trade and auction data for listed cards.
- **`tournaments`**: Holds tournament details like rules, participants, and prize pools.
- **`card-balances`**: Tracks the quantity of owned cards and their locked status.
- **`season-rewards`**: Manages reward distribution across cycles.

#### **Constants**
- **`PLATFORM-FEE`**: Fee percentage deducted from trades (2.0%).
- **`TOURNAMENT-LOCK`**: Lock duration (~24 hours in blocks).
- **`MIN-CARD-PRICE`**: Minimum price for cards in the marketplace.
- **`MAX-RARITY-BONUS`**: Maximum allowed rarity bonus (25%).

---

### Usage

#### Minting a Card
To create a new card:
```clojure
(mint-card "Card Description" rarity-bonus total-prints)
```
- **`rarity-bonus`**: Value up to 25%.
- **`total-prints`**: Number of card copies.

#### Listing a Card for Trade
To list a card on the marketplace:
```clojure
(list-for-trade card-id quantity price)
```
- **`card-id`**: Unique ID of the card.
- **`price`**: Selling price in micro-STX.

#### Buying a Card
To purchase a card from the marketplace:
```clojure
(purchase-card card-id)
```

#### Participating in Tournaments
To stake in a tournament:
```clojure
(participate-in-tournament tournament-id stake-amount)
```

#### Admin Functions
- Lock the system:
  ```clojure
  (set-system-lock true)
  ```
- Update treasury wallet:
  ```clojure
  (set-treasury-wallet new-wallet)
  ```

---

### Development and Testing

1. **Environment Setup**:
   - Deploy using the Clarity language on the Stacks blockchain.
   - Ensure `card-fragments`, `arena-token`, and `battle-points` are properly initialized.

2. **Testing**:
   - Validate card minting, trading, and ownership functions.
   - Simulate tournaments and reward distribution.
   - Test edge cases for error handling.

---

### Contribution

Contributions are welcome! Please fork the repository, make your changes, and submit a pull request. Ensure proper testing and documentation for new features.
