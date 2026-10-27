# Glide — GLP-1 Tracker

A full-featured iOS companion app for people on GLP-1 medications (Ozempic, Wegovy, Mounjaro, Zepbound). Built with SwiftUI, SwiftData, WidgetKit, ActivityKit, HealthKit, Firebase, and RevenueCat.

---

## Features

### Medication Tracking
- Log every injection with dose, date, and medication type
- Real-time 7-day concentration curve using first-order pharmacokinetics
- Food noise vulnerability zone overlay — know when cravings will hit before they do
- Live Activity on the lock screen + Dynamic Island, updated throughout the week
- Home screen widgets in small, medium, and large

### Health Tracking
- Weight log with goal progress and trend sparkline
- Nutrition log with calories, protein, carbs, and fat macros
- Exercise log with HealthKit import and manual entry

### Community
- Anonymous chatroulette-style peer chat — connect with other GLP-1 users
- Firebase anonymous auth — no name, email, or account required
- Ephemeral chat sessions — messages not retained after disconnect
- One-tap report for safety moderation

### Platform
- Push notifications: shot reminders, food noise alerts, overdue warnings
- Spotlight search across all logged data
- App Intents + Siri shortcuts
- Deep link routing (`glide://` scheme) from notifications and Spotlight
- Background refresh for widget and Live Activity
- CSV data export with ShareSheet
- App Store review prompts at meaningful milestones
- Semantic haptic feedback throughout

### Monetisation
- Free download with RevenueCat-managed Premium subscription (monthly + annual)
- Paywall gates: concentration curves, food noise alerts, community chat, weekly insights

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI (iOS 17+) |
| Persistence | SwiftData |
| Reactive state | `@Observable` macro |
| Charts | Swift Charts |
| Health | HealthKit |
| Widgets | WidgetKit |
| Live Activities | ActivityKit |
| Notifications | UserNotifications |
| Background tasks | BGTaskScheduler |
| Search | CoreSpotlight |
| Shortcuts | App Intents |
| Community chat | Firebase Auth + Firestore + Storage |
| Subscriptions | RevenueCat v5 |
| App Groups | `group.com.glide.shared` (app ↔ widget bridge) |

---

## Project Structure

```
GlideGLP1Companion/
├── project.yml                  # xcodegen spec — source of truth for the Xcode project
├── AppStore/
│   ├── metadata.md              # App name, subtitle, keywords, description, screenshot captions
│   └── privacy-policy.md        # Full privacy policy (also hosted on GitHub Pages)
├── GlideGLP1Companion/          # Main app target (32 Swift files)
│   ├── GlideApp.swift           # @main entry point, all manager injection
│   ├── GlideAppDelegate.swift   # UNUserNotificationCenterDelegate
│   ├── ContentView.swift        # Onboarding gate
│   ├── MainTabView.swift        # 6-tab navigation shell
│   ├── SwiftDataModels.swift    # All @Model types
│   ├── UserProfile.swift        # Community profile model
│   ├── GLP1Medication.swift     # Pharmacokinetic model
│   ├── DashboardView.swift
│   ├── MedicationView.swift
│   ├── NutritionView.swift
│   ├── ExerciseLogView.swift
│   ├── CommunityView.swift      # Chatroulette UI + chat
│   ├── ChatManager.swift        # Firebase matching + messaging
│   ├── ProfileEditView.swift
│   ├── SettingsView.swift
│   ├── OnboardingView.swift
│   ├── PaywallView.swift
│   ├── PremiumGate.swift
│   ├── SubscriptionManager.swift
│   ├── HealthKitManager.swift
│   ├── NotificationManager.swift
│   ├── LiveActivityManager.swift
│   ├── BackgroundTaskManager.swift
│   ├── SpotlightManager.swift
│   ├── HapticManager.swift
│   ├── AppReviewManager.swift
│   ├── DeepLinkRouter.swift
│   ├── AppIntents.swift
│   └── DataExportView.swift
├── GlideWidget/                 # Widget + Live Activity extension
│   ├── GlideWidget.swift        # WidgetKit timeline provider + 3 sizes
│   └── GlideLiveActivity.swift  # Lock screen + Dynamic Island views
└── Shared/                      # Compiled into both targets
    ├── SharedMedicationStore.swift   # App Group data bridge
    └── MedicationActivityAttributes.swift
```

---

## Getting Started

### Prerequisites
- Xcode 16+
- iOS 17+ device or simulator
- Apple Developer Program membership
- Firebase project
- RevenueCat account

### Setup

1. **Clone and generate the Xcode project**
   ```bash
   git clone https://github.com/sehenriksen-sudo/glide-glp1-companion.git
   cd glide-glp1-companion
   brew install xcodegen   # if not already installed
   xcodegen generate
   ```

2. **Add Firebase**
   - Create a project at [console.firebase.google.com](https://console.firebase.google.com)
   - Add an iOS app with bundle ID `com.glide.app`
   - Download `GoogleService-Info.plist` and replace the placeholder at `GlideGLP1Companion/GoogleService-Info.plist`
   - Enable Anonymous Authentication and create a Firestore database

3. **Add RevenueCat**
   - Create an account at [revenuecat.com](https://www.revenuecat.com)
   - Replace `"appl_REPLACE_WITH_YOUR_KEY"` in `SubscriptionManager.swift`
   - Create a subscription group in App Store Connect and link it in RevenueCat

4. **Open in Xcode**
   ```bash
   open GlideGLP1Companion.xcodeproj
   ```
   Xcode will resolve SPM packages (RevenueCat + Firebase) automatically. Sign in to your Apple ID and automatic signing will handle certificates and provisioning.

---

## Regenerating the Xcode Project

The `.xcodeproj` is generated from `project.yml` and is committed for convenience. If you change `project.yml`, regenerate with:

```bash
xcodegen generate
```

---

## Privacy

User health data is stored entirely on-device and never uploaded to external servers.
Community chat uses Firebase anonymous authentication — no real identity is required or collected.

Full privacy policy: [sehenriksen-sudo.github.io/glide-site/privacy.html](https://sehenriksen-sudo.github.io/glide-site/privacy.html)

---

## License

MIT
