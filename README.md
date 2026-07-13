# Fortune — SwiftUI (v2.0)

This is the updated build for Fortune — see
"What's new in this version" below for the delta.

---

## Setup (about 5 minutes)

1. In Xcode: **File → New → Project → iOS → App**.
   - Product Name: `Fortune`
   - Interface: **SwiftUI**, Language: **Swift**
   - Set the deployment target to **iOS 17.0** or later.
2. Xcode generates a `ContentView.swift` and a `FortuneApp.swift`. **Delete both**
   (move to Trash) — this folder has its own `FortuneApp.swift`.
3. Drag every `.swift` file from this folder into the project navigator.
   Check **"Copy items if needed"** and make sure your app target is ticked.
4. **Logo (optional):** open `Assets.xcassets`, drag in `FortuneLogo.png`, and
   name the image set exactly **`FortuneLogo`**. If you skip this, the app still
   runs — it falls back to a gradient `sparkles` glyph everywhere the logo appears.
5. Build and run (Cmd-R).

---

## File map

| File | What's in it |
|------|--------------|
| `FortuneApp.swift` | App entry point. |
| `RootView.swift` | Onboarding vs. main shell, header bar, bottom tab bar. |
| `Theme.swift` | All colors, gradients, fonts, number formatting. **Start here to restyle.** |
| `Models.swift` | Data types + `AppModel` (the shared app state). |
| `MockData.swift` | All sample data: stocks, timeframes, holdings, news, predictions, leaderboard, candles. |
| `Components.swift` | Shared pieces: logo, PnL badge, backgrounds, footer, flow layout. |
| `OnboardingView.swift` | The 9-step welcome flow. |
| `TradeView.swift` | Trade screen + order / detail / alerts sheets. |
***Will Be Deprecated Feature***| `PredictionsView.swift` | Prediction markets ("Predict" tab). |
| `LeaderboardView.swift` | Leaderboard + daily challenges. |
| `PnLView.swift` | Portfolio: PnL, candles, allocation donut, holdings, news. |
| `AccountView.swift` | Account & settings + sign-out action sheet. |

**"I want to change X":**
- Colors / gradients -> `Theme.swift`
- The numbers, stocks, holdings, news -> `MockData.swift`
- Starting balance / user name -> `AppModel` in `Models.swift`
- Which tabs show in the bar -> `AppTab.barTabs` in `Models.swift`

---
