# Fortune — Stock Market Paper-Trading Simulator

Fortune is an iOS app for practicing stock trading with live market data and zero real money. You get a mock portfolio, buy and sell real stocks at live prices, set stop losses and take-profit targets, and compete on a leaderboard while earning XP and achievements.

Built entirely in **SwiftUI** with Swift Concurrency, Swift Charts, and the Observation framework.

<p align="center">
  <img src="docs/screenshots/trade.png" width="200" alt="Trade screen with live candlestick chart and positions">
  &nbsp;
  <img src="docs/screenshots/portfolio.png" width="200" alt="Portfolio screen with P&L, allocation, and trade journal">
  &nbsp;
  <img src="docs/screenshots/leaderboard.png" width="200" alt="Leaderboard with daily challenges">
  &nbsp;
  <img src="docs/screenshots/account.png" width="200" alt="Account screen with level, portfolio value, and stats">
</p>

---

## Features

**Trading**
- Live quotes for 22 stocks across Tech, Finance, Consumer, Media, Crypto, and EV sectors
- Real-time price updates over a WebSocket feed, plus periodic REST refreshes
- Candlestick charts (1D / 1W / 1M / 3M) with the latest bar updated live
- Market orders with stop-loss and take-profit levels that **execute automatically** when price crosses them
- Partial sells, average-cost basis across multiple buys, and realized vs. unrealized P&L
- Price alerts that fire a notification when a target is crossed
- Search, sector filters, sorting, top movers, and a starred watchlist

**Portfolio**
- Combined P&L hero, equity curve, allocation donut chart, open positions, and a trade journal of every closed trade (manual, stop loss, or take profit)
- Market news feed

**Gamification**
- XP and levels earned from real trading activity
- Daily challenges (First Blood, Diversify, Profit Streak) that reset at midnight
- Achievements such as Hot Streak (5 wins in a row) and Night Owl (trades outside NYSE hours)
- Practice League: all-time and weekly rankings against clearly labeled simulated traders, ranked by **% return** so every starting balance competes fairly

**Personalization**
- 9-step onboarding that tailors the starting balance, default stop-loss / take-profit %, chart timeframe, sort order, and sector focus
- Local notifications for level-ups, big moves in held stocks, and stop-loss / take-profit fills
- Starred stocks sync across devices with iCloud key-value storage
- Everything persists on-device; no account or server required

---

## Tech Stack

| Area | Technology |
|------|------------|
| UI | SwiftUI, Swift Charts, Canvas (donut chart, confetti) |
| State | Observation (`@Observable`); a thin `AppModel` coordinating focused types |
| Money | `Decimal` ledger (exact cents); market quotes as `Double` |
| Concurrency | async/await, `actor`, `TaskGroup`, `AsyncStream` |
| Networking | `URLSession` REST + `URLSessionWebSocketTask` |
| Data | [Finnhub](https://finnhub.io) (quotes, fundamentals, news, live trades), Yahoo Finance (OHLC candles) |
| Persistence | `Codable` + `UserDefaults`, `NSUbiquitousKeyValueStore` for iCloud sync |
| Notifications | UserNotifications (local only) |
| Testing | Swift Testing (34 unit tests) |

---

## Architecture

```
Views (SwiftUI)  ──▶  AppModel (@Observable coordinator)
                        ├─ PortfolioEngine   ledger: cash, orders, positions, P&L   (pure struct)
                        ├─ Gamification      XP, levels, challenges, achievements   (pure struct)
                        ├─ PracticeLeague    rankings vs. simulated traders         (pure functions)
                        ├─ MarketDataStore   quotes, charts, news, live feed  ──async──▶  MarketService (actor)
                        └─ PersistenceStore  save/load (protocol), iCloud watchlist
```

- **`AppModel`** is glue: it reacts to price changes (stop loss / take profit, alerts), sends notifications, drives toasts, and saves. The rules live in the types below it.
- **`PortfolioEngine`** is a plain value type with no UI, networking, or storage, so every trading rule is unit tested directly.
- **`MarketService`** is an `actor`, so network work stays off the main thread and its state is isolated.
- **`PersistenceStore`** is a protocol, so tests run against isolated storage instead of the real app's data.

### Engineering details

- **Rate-limit aware loading.** Finnhub's free tier allows 60 calls/minute. Quotes load first so the UI fills in within a second or two. Fundamentals (P/E, market cap, 52-week range, analyst rating) are then fetched in small batches with pauses between them. Rate-limited or empty responses are rejected so a `429` can never turn into a $0 price that falsely triggers a stop loss.
- **Throttled live feed.** Large-cap stocks trade thousands of times a minute. WebSocket updates are throttled to one UI update per symbol every 2 seconds and ignore sub-cent moves. The stream reconnects automatically.
- **Order engine.** Weighted average-cost basis, realized P&L on partial sells, and automatic stop-loss / take-profit execution that records the exit reason in the trade journal.
- **Exact money.** The ledger uses `Decimal` and rounds to cents at execution, so `33.33 × 3` is exactly `99.99` (in `Double` it's `99.99000000000001`). Quotes stay `Double` and convert only at the edges.
- **Incremental positions.** Positions update in O(1) per trade instead of replaying the whole order history on every read. The same update function rebuilds positions when a save is loaded, and a test checks that the two always agree.
- **Typed, backward-compatible data.** Preferences and order fields are enums and numbers instead of strings; custom decoding still loads saves written by older versions (covered by a test).

---

## Getting Started

### Requirements
- Xcode 27 or later
- iOS 26.5+ (simulator or device)
- A free [Finnhub API key](https://finnhub.io/register)

### Setup
1. Clone the repo:
   ```bash
   git clone https://github.com/Kalmxz007/Fortune-iOS-App-Dev.git
   ```
2. Add your API key. Copy the template into the app folder and paste your key into it:
   ```bash
   cp Secrets.example.plist "Fortune Final V2/Secrets.plist"
   ```
   `Secrets.plist` is git-ignored, so your key stays on your machine.
3. Open `Fortune Final V2.xcodeproj` and run the **Fortune Final V2** scheme (⌘R).

> **iCloud sync (optional):** syncing starred stocks on a real device requires enabling **iCloud → Key-value storage** under *Signing & Capabilities* with your own team. Everything else works without it.

### Running tests
Press **⌘U** in Xcode, or run:
```bash
xcodebuild test -project "Fortune Final V2.xcodeproj" -scheme "Fortune Final V2" \
  -destination "platform=iOS Simulator,name=iPhone 18 Pro"
```
The tests cover cost basis, realized P&L, exact-cent `Decimal` math, incremental positions vs. full replay, stop-loss / take-profit execution, win streaks, daily-challenge XP, price alerts, persistence (including loading old save formats), Practice League ranking, stock filtering, NYSE market-hours detection, and number formatting.

---

## Project Structure

| File | Responsibility |
|------|----------------|
| **App state & logic** | |
| `AppModel.swift` | Observable coordinator: profile, settings, reacting to prices, notifications, saving |
| `PortfolioEngine.swift` | Ledger: order execution, incremental positions, realized P&L, stop loss / take profit, equity curve |
| `Gamification.swift` | XP, levels, daily challenges, achievements, NYSE market hours |
| `PracticeLeague.swift` | Leaderboard vs. simulated traders, ranked by % return |
| `MarketDataStore.swift` | Quotes, charts, news, live price feed, O(1) symbol lookup |
| `Persistence.swift` | Saved state, `PersistenceStore` protocol, iCloud watchlist |
| `Models.swift` | Domain types: orders, closed trades, holdings, stocks, alerts |
| `Preferences.swift` | Typed onboarding choices (risk, experience, goal, frequency, timeframe) |
| `Money.swift` | `Decimal` helpers: cent rounding, quote conversion |
| `MarketService.swift` | Finnhub / Yahoo networking and the WebSocket feed (actor) |
| `NotificationManager.swift` | Local notification permissions and delivery |
| **Screens** | |
| `FortuneApp.swift` | App entry point |
| `RootView.swift` | Onboarding vs. main shell, header, tab bar, global toasts |
| `TradeView.swift` | Trade screen container: state and sheets |
| `TradeChartHeader.swift` | Live price, timeframe picker, candlestick chart |
| `TradeSections.swift` | Positions, movers, filter bar, "For You" strip, stock rows |
| `StockFilter.swift` | Search / sector / sort logic (no SwiftUI, unit tested) |
| `OrderSheet.swift`, `StockDetailSheet.swift`, `PriceAlertsSheet.swift` | Trade sheets |
| `PnLView.swift` | Portfolio: P&L, equity curve, allocation, positions, journal, news |
| `LeaderboardView.swift` | Practice League and daily challenges |
| `AccountView.swift` | Profile, stats, achievements, settings, privacy policy |
| `OnboardingView.swift` | 9-step personalized onboarding |
| `TutorialView.swift` | In-app how-to guide |
| `Components.swift` | Shared views: badges, backgrounds, confetti, flow layout |
| `Theme.swift` | Colors, gradients, fonts, number formatting |
| `FortuneTests/` | Swift Testing unit tests |

---

## Roadmap

- Limit orders and short selling
- Portfolio history snapshots for a time-based equity curve
- Real multiplayer leaderboard via Game Center
- Widgets and Live Activities for open positions

---

## How This Was Built

Fortune was built as a group project with AI pair-programming, using Claude as a coding assistant (credited as a co-author on the commits where it helped).

**My role:** We came up with the concept and decided what the app should do: the trading features, the gamification, the onboarding flow, and the look and feel. I directed each change, tested the app on the simulator, reported bugs I found, and reviewed the code before committing.

**Claude's role:** writing and refactoring much of the Swift code, tracking down bugs, and writing unit tests and documentation from my direction.

**What I learned:** SwiftUI state management with `@Observable`, Swift Concurrency (actors, task groups, async streams), working within a real API's rate limits, and how to structure code so it can be unit tested.

---

## Disclaimer

Fortune is a simulator for educational and entertainment purposes. No real money is involved and no real trades are placed. Market data is provided by third parties and may be delayed or inaccurate.
