# ⚡ Zeus — Command your Chevy Bolt

A futuristic, native iOS alternative to the *myChevrolet* app, built specifically
for the **Chevy Bolt / Bolt EUV**. Zeus gives you the full remote command suite,
Siri voice control, home-screen & Control Center widgets, smart auto-start
timers, a charger map, CarPlay, and live OBD-II telemetry — wrapped in a
**Frutiger Aero 2088** glass-and-glow aesthetic.

> **Status: foundation / scaffold.** The architecture and the remote-command +
> Siri path are built out in real, working code. Maps, CarPlay, OBD and timers
> are functional scaffolds you can build on. This was bootstrapped on a machine
> without Xcode, so it has not yet been compiled on-device — expect to shake out
> small issues in Xcode (see *Known caveats*).

---

## ✨ Features

| Area | What's here |
|------|-------------|
| **Remote commands** | Start / stop, lock / unlock, charge-now, find-my-car (honk+flash), locate, live diagnostics — issued through GM's OnStar mobile API with async command polling. |
| **Siri** | "Hey Siri, **start my car** with Zeus", lock/unlock, charge, and "what's my Bolt's charge?" via App Intents + App Shortcuts. |
| **Widgets** | Status widget (battery/range/lock) for home & lock screen, an **interactive** control-panel widget (Start/Lock/Charge buttons), and iOS 18 Control Center controls. |
| **Smart timers** | Fixed-time and **adaptive** auto-start that learns when you leave home/work and pre-warms the cabin before you go. |
| **Charger map** | Nearby L2 / DC-fast chargers via Open Charge Map, with one-tap navigation. |
| **CarPlay** | Charger lists (DC fast / Level 2) + a live Bolt dashboard. |
| **OBD-II** | BLE ELM327 dongle reader for live speed / RPM / temps / HV battery while driving. |
| **Design** | A reusable Frutiger Aero 2088 design system: deep-space gradients, frosted glass, glossy buttons, drifting bubbles, holographic rims. |

---

## 🏗 Architecture

```
Sources/
  Zeus/
    App/            SwiftUI @main app + tab shell
    DesignSystem/   Frutiger Aero 2088 (palette, glass, components, background)
    Models/         Vehicle, VehicleSnapshot, VehicleCommand, ChargingStation
    Shared/         App Group, snapshot cache, secrets   (app + widget)
    Core/           UIKit-free engine                      (app + widget)
                      OnStarClient ........ commands + polling
                      GMTokenService ...... PKCE + OAuth token exchange/refresh
                      RemoteCommandService  shared façade for Siri/widgets
                      CommandIntents ...... App Intents (Siri + widget buttons)
                      KeychainStore, OnStarConfig, OnStarParsing, OnStarError
    Services/       App-only services
                      OnStar/GMAuthSession  interactive web login (ASWebAuth)
                      VehicleManager ...... UI state + biometrics
                      Charging/, OBD/, Timers/, LocationProvider
    Intents/        ZeusShortcuts (Siri phrases)
    Features/       Home, Chargers, Timers, Settings/Onboarding (SwiftUI)
    CarPlay/        CPTemplate scene delegate
    Resources/      Info.plist, entitlements, asset catalog
  ZeusWidgets/      WidgetKit extension (status, control panel, CC controls)
```

**Key design choice — the `Core` split.** Anything Siri or the widget extension
must run (commands, token refresh, intents) lives in `Core` and is **UIKit-free**,
so it compiles into both the app and the extension. The only UIKit-bound piece —
the interactive web login — stays in the app target (`GMAuthSession`). The app,
Siri, and widgets all funnel through `RemoteCommandService`.

---

## 🔐 How it talks to your Bolt (important)

**GM publishes no public API.** Zeus speaks the same private OnStar mobile API
that *myChevrolet* uses, following the reverse-engineering maintained by
[**OnStarJS**](https://github.com/BigThunderSR/OnStarJS).

Login uses **`ASWebAuthenticationSession`** against GM's own Azure AD B2C login
page with PKCE. Because GM's hosted page handles the password and **MFA / TOTP /
passkeys natively**, Zeus never sees or stores your password — only the resulting
OAuth tokens (kept in the Keychain).

⚠️ This may violate GM's Terms of Service. Use it for **personal use with your own
vehicle and account**. GM rotates the B2C tenant, client id and scopes from time
to time; if login breaks, update the constants in `Core/OnStarConfig.swift`
against the latest OnStarJS release.

---

## 🚀 Getting started

### 1. Generate the Xcode project
This repo commits an [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec
(`project.yml`) instead of a `.xcodeproj` so it stays diff-friendly.

```bash
brew install xcodegen
xcodegen generate
open Zeus.xcodeproj
```

### 2. Set your signing + identifiers
- In **project.yml** set `DEVELOPMENT_TEAM`, then re-run `xcodegen generate`
  (or set the team in Xcode → Signing & Capabilities for both targets).
- The app + widget share **App Group `group.com.zeus.bolt`** and a Keychain
  group. Create the App Group in your Apple Developer account and make sure both
  targets have it enabled. To share the OnStar token with widgets, set
  `KeychainStore.accessGroup` to your team's keychain group.

### 3. Add API keys (optional, for the charger map)
Create `Sources/Zeus/Resources/Secrets.plist` (it's **gitignored**):

```xml
<plist version="1.0"><dict>
  <key>OpenChargeMapKey</key><string>YOUR_OCM_KEY</string>
</dict></plist>
```
Get a free key at <https://openchargemap.org/site/profile/applications>.

### 4. Build & run
Build the **Zeus** scheme on a device (Siri/CarPlay/OBD need real hardware).
On first launch, enter your OnStar email + VIN and complete the secure GM login.

### 5. Try Siri
> "Hey Siri, start my car with Zeus."
> "Hey Siri, what's my Bolt's charge with Zeus?"

---

## 🚢 TestFlight CI (no Xcode needed)

`.github/workflows/testflight.yml` builds and uploads a TestFlight build with
**fastlane** on a macOS runner. Trigger it from the **Actions** tab
(*Run workflow*) or by pushing a tag like `v0.1.0`. It runs `xcodegen generate`,
fetches signing assets via **fastlane match**, builds, and uploads.

### Required GitHub Actions secrets
| Secret | What it is |
|--------|-----------|
| `ASC_KEY_ID` | App Store Connect API key ID. |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID. |
| `ASC_KEY_CONTENT` | The `.p8` key, **base64-encoded** (`base64 -i AuthKey_XXX.p8 \| pbcopy`). |
| `TEAM_ID` | Your 10-char Apple Developer Team ID. |
| `MATCH_GIT_URL` | Git URL of your fastlane **match** certificates repo. |
| `MATCH_PASSWORD` | The match encryption passphrase. |
| `MATCH_GIT_BASIC_AUTHORIZATION` | base64 of `username:personal_access_token` for the match repo. |

These are the standard fastlane-match + App Store Connect API secrets — the same
set you already have in your other repo can be copied over verbatim.

### One-time prerequisites
- App IDs `com.zeus.bolt` and `com.zeus.bolt.widgets` exist in the portal with
  the **App Groups** + **Siri** capabilities, and an **App Group**
  `group.com.zeus.bolt`.
- The app record exists in App Store Connect (matching `com.zeus.bolt`).
- Your match repo holds **App Store** distribution certs/profiles for both IDs
  (run `fastlane match appstore` once locally to seed it).

---

## ⚠️ Known caveats / next steps
- **Not yet compiled in Xcode** — first build may surface minor type/availability
  fixes.
- **CarPlay** needs a CarPlay entitlement granted by Apple; add the granted role
  to `Zeus.entitlements` before it appears on a head unit.
- **No app icon art yet** — the asset catalog has an empty `AppIcon` slot.
- **OnStar endpoints** track OnStarJS and may need updating when GM changes them.
- **Adaptive timers** need a geofence/visit monitor to feed
  `SmartTimerEngine.recordDeparture` — the learning math and scheduling are in
  place; wiring `CLVisit` monitoring is the remaining step.
- Background remote-start is best-effort within iOS background-task limits.

---

## 🙏 Credits
- [OnStarJS](https://github.com/BigThunderSR/OnStarJS) — the OnStar API reference.
- [Open Charge Map](https://openchargemap.org) — charger data.

Unofficial. Not affiliated with General Motors, Chevrolet, or OnStar.
