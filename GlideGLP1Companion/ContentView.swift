// ContentView.swift
//
// Root view — owns the onboarding gate and hands off to MainTabView.
// GlideApp sets this as the WindowGroup's root and injects all environments.

import SwiftUI
import SwiftData

struct ContentView: View {

    @AppStorage("onboardingComplete") private var onboardingComplete = false

    // Driven by the environment — read here so the tab bar reacts
    // live to subscription changes (e.g. badge updates after purchase).
    @Environment(SubscriptionManager.self)    private var store
    @Environment(HealthKitManager.self)       private var hkManager
    @Environment(NotificationManager.self)    private var notificationManager
    @Environment(LiveActivityManager.self)    private var liveActivityManager
    @Environment(DeepLinkRouter.self)         private var router

    var body: some View {
        MainTabView()
            .fullScreenCover(isPresented: Binding(
                get: { !onboardingComplete },
                set: { if !$0 { onboardingComplete = true } }
            )) {
                OnboardingView()
            }
            // ── URL scheme deep links (glide://) ──────────────────────────
            .onOpenURL { url in
                router.handle(url: url)
            }
            // ── Foreground lifecycle ──────────────────────────────────────
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                notificationManager.clearBadge()
                Task { await notificationManager.refreshPending() }
                Task { await liveActivityManager.update() }
            }
    }
}

// MARK: - Previews

#Preview("Fresh install — onboarding") {
    ContentView()
        .modelContainer(for: [
            UserConfiguration.self, MedicationLog.self,
            WeightLog.self, FoodLog.self, ExerciseLog.self,
        ], inMemory: true)
        .environment(SubscriptionManager())
        .environment(HealthKitManager())
        // Simulate first launch by not setting onboardingComplete in UserDefaults.
        // To force this in the live simulator, reset via:
        //   UserDefaults.standard.removeObject(forKey: "onboardingComplete")
}

#Preview("Returning user — tab bar") {
    // Write the flag so the tab bar shows immediately, no onboarding sheet.
    let _ = UserDefaults.standard.set(true, forKey: "onboardingComplete")

    return ContentView()
        .modelContainer(previewContainer)
        .environment(SubscriptionManager())
        .environment(HealthKitManager())
}

// MARK: - Preview container with sample data

@MainActor
private let previewContainer: ModelContainer = {
    let schema = Schema([
        UserConfiguration.self, MedicationLog.self,
        WeightLog.self, FoodLog.self, ExerciseLog.self,
    ])
    let container = try! ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext

    // UserConfiguration
    ctx.insert(UserConfiguration(
        selectedMedication:    GLP1MedicationType.semaglutide.rawValue,
        targetWeight:          78.0,
        currentWeight:         94.5,
        monthlyMedicationCost: 350
    ))

    // Most recent injection — 3 days ago
    ctx.insert(MedicationLog(
        date:           Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
        doseMg:         1.0,
        medicationType: GLP1MedicationType.semaglutide.rawValue
    ))

    // Previous injection — 10 days ago
    ctx.insert(MedicationLog(
        date:           Calendar.current.date(byAdding: .day, value: -10, to: .now)!,
        doseMg:         0.5,
        medicationType: GLP1MedicationType.semaglutide.rawValue
    ))

    // Weight entries — last 2 weeks
    let weightSamples: [(Int, Double)] = [
        (-14, 95.8), (-11, 95.2), (-7, 94.9), (-4, 94.5), (0, 94.1)
    ]
    for (offset, kg) in weightSamples {
        ctx.insert(WeightLog(
            date:   Calendar.current.date(byAdding: .day, value: offset, to: .now)!,
            weight: kg
        ))
    }

    // Today's food log
    let mealTime = Calendar.current.date(byAdding: .hour, value: -2, to: .now)!
    ctx.insert(FoodLog(timestamp: mealTime,   mealName: "Greek yogurt & berries", calories: 280, protein: 22, carbs: 34, fat: 5))
    ctx.insert(FoodLog(timestamp: .now,       mealName: "Grilled chicken salad",  calories: 420, protein: 48, carbs: 18, fat: 14))

    // Exercise entries
    ctx.insert(ExerciseLog(
        date:             Calendar.current.date(byAdding: .day, value: -1, to: .now)!,
        workoutType:      ExerciseType.running.rawValue,
        durationMinutes:  35,
        activeCalories:   310,
        distanceMeters:   5_200,
        source:           "manual"
    ))
    ctx.insert(ExerciseLog(
        date:             Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
        workoutType:      ExerciseType.strengthTraining.rawValue,
        durationMinutes:  45,
        activeCalories:   220,
        source:           "healthkit"
    ))
    ctx.insert(ExerciseLog(
        date:             Calendar.current.date(byAdding: .day, value: -5, to: .now)!,
        workoutType:      ExerciseType.cycling.rawValue,
        durationMinutes:  50,
        activeCalories:   380,
        distanceMeters:   18_400,
        source:           "healthkit"
    ))

    return container
}()
