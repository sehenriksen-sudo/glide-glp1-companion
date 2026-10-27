// GlideApp.swift
//
// @main entry point. Owns every manager and injects them into the environment.

import SwiftUI
import SwiftData
import WidgetKit
import BackgroundTasks
import Firebase   // add firebase-ios-sdk via SPM (FirebaseAuth, FirebaseFirestore, FirebaseStorage)

@main
struct GlideApp: App {

    // ── App Delegate ───────────────────────────────────────────────────────
    @UIApplicationDelegateAdaptor(GlideAppDelegate.self) var appDelegate

    // ── SwiftData container ────────────────────────────────────────────────
    private let container: ModelContainer = {
        let schema = Schema([
            UserConfiguration.self, MedicationLog.self,
            WeightLog.self, FoodLog.self, ExerciseLog.self,
            UserProfile.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do    { return try ModelContainer(for: schema, configurations: config) }
        catch { fatalError("SwiftData container failed: \(error)") }
    }()

    // ── Managers ───────────────────────────────────────────────────────────
    @State private var subscriptionManager  = SubscriptionManager()
    @State private var healthKitManager     = HealthKitManager()
    @State private var notificationManager  = NotificationManager()
    @State private var liveActivityManager  = LiveActivityManager()
    @State private var router               = DeepLinkRouter()
    @State private var spotlightManager     = SpotlightManager()
    @State private var hapticManager        = HapticManager()
    @State private var appReviewManager     = AppReviewManager()
    @State private var backgroundTaskManager = BackgroundTaskManager()
    @State private var chatManager           = ChatManager()

    // ── Background task registration + Firebase (must happen at init time) ─
    init() {
        // Only configure Firebase when a real GoogleService-Info.plist is present.
        // Replace the placeholder file before enabling community features.
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let appID = plist["GOOGLE_APP_ID"] as? String,
           !appID.contains("REPLACE_ME") {
            FirebaseApp.configure()
        }
        BackgroundTaskManager().registerHandlers()
    }

    // MARK: Scene

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .environment(subscriptionManager)
                .environment(healthKitManager)
                .environment(notificationManager)
                .environment(liveActivityManager)
                .environment(router)
                .environment(spotlightManager)
                .environment(hapticManager)
                .environment(appReviewManager)
                .environment(backgroundTaskManager)
                .environment(chatManager)
                .onAppear {
                    bootstrap()
                }
                // ── Spotlight / NSUserActivity continuation ────────────────
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let url = SpotlightManager.deepLinkURL(from: activity) {
                        router.handle(url: url)
                    }
                }
                // ── URL scheme deep links (glide://) ──────────────────────
                .onOpenURL { router.handle(url: $0) }
                // ── Background / foreground lifecycle ─────────────────────
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        backgroundTaskManager.scheduleAppRefresh()
                        backgroundTaskManager.scheduleHealthImport()
                        // Disconnect from chat and clean up Firestore listeners
                        Task { await chatManager.disconnect() }
                    case .active:
                        Task { await liveActivityManager.update() }
                        Task { await notificationManager.refreshPending() }
                        notificationManager.clearBadge()
                    default: break
                    }
                }
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    // MARK: Bootstrap

    private func bootstrap() {
        // Notification delegate
        appDelegate.router = router

        // RevenueCat
        subscriptionManager.configure()

        // Widget reloader bridge
        WidgetCenterBridge.reloadAll = { WidgetCenter.shared.reloadAllTimelines() }

        // Live Activity restore after kill
        liveActivityManager.restoreIfNeeded()

        // App Intents bridge
        DeepLinkRouterStore.shared.router = router

        // Background task manager dependencies
        backgroundTaskManager.liveActivityManager = liveActivityManager
        backgroundTaskManager.healthKitManager    = healthKitManager
        backgroundTaskManager.modelContainer      = container

        // Auth state refresh
        Task { await notificationManager.refreshAuthState() }

        // Initial Spotlight index (runs on a detached task so it doesn't block launch)
        Task.detached(priority: .background) {
            await indexSpotlight()
        }
    }

    @MainActor
    private func indexSpotlight() async {
        let ctx  = container.mainContext
        let meds = (try? ctx.fetch(FetchDescriptor<MedicationLog>())) ?? []
        let wts  = (try? ctx.fetch(FetchDescriptor<WeightLog>()))     ?? []
        let exs  = (try? ctx.fetch(FetchDescriptor<ExerciseLog>()))   ?? []
        let fds  = (try? ctx.fetch(FetchDescriptor<FoodLog>()))       ?? []
        await spotlightManager.indexAll(medications: meds, weights: wts, exercises: exs, foods: fds)
    }
}

// MARK: - CoreSpotlight import (needed for the activity type constant)
import CoreSpotlight
