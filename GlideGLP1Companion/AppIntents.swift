// AppIntents.swift
//
// Siri Shortcuts and Spotlight Actions powered by the App Intents framework.
// Users can say or search:
//   "Log my Ozempic shot"
//   "Check my GLP-1 concentration"
//   "Log a meal in Glide"
//   "Log a workout in Glide"
//   "What's my food noise status?"

import AppIntents
import SwiftData
import SwiftUI

// MARK: - Log Shot Intent

struct LogShotIntent: AppIntent {

    static var title: LocalizedStringResource = "Log Injection"
    static var description = IntentDescription("Open Glide to log your latest GLP-1 injection.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouterStore.shared.router?.route(to: .logShot)
        return .result()
    }
}

// MARK: - Check Concentration Intent

struct CheckConcentrationIntent: AppIntent {

    static var title: LocalizedStringResource = "Check Concentration"
    static var description = IntentDescription("Get your current GLP-1 medication concentration level.")

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let snapshot = AppGroup.loadSnapshot() else {
            return .result(
                dialog: "No injection logged yet. Open Glide to log your first shot.",
                view: noDataSnippet
            )
        }

        let conc       = snapshot.concentration()
        let percent    = Int(conc * 100)
        let isRisk     = conc < 0.40
        let status     = isRisk ? "food noise zone" : "protected zone"
        let crossover  = snapshot.crossoverDate
        let daysLeft   = max(0, crossover.timeIntervalSinceNow / 86_400)

        let dialogText: String
        if isRisk {
            dialogText = "Your \(snapshot.medicationType) concentration is \(percent)%. You're currently in the food noise zone. Your next dose is \(snapshot.nextDoseDate.formatted(.relative(presentation: .named)))."
        } else {
            dialogText = "Your \(snapshot.medicationType) concentration is \(percent)% — you're in the protected zone. You'll enter the food noise zone in about \(Int(daysLeft)) days."
        }

        return .result(
            dialog: "\(dialogText)",
            view: concentrationSnippet(percent: percent, isRisk: isRisk, medType: snapshot.medicationType)
        )
    }

    @ViewBuilder
    private var noDataSnippet: some View {
        Label("No data", systemImage: "syringe")
            .font(.headline)
            .padding()
    }

    @ViewBuilder
    private func concentrationSnippet(percent: Int, isRisk: Bool, medType: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: isRisk ? "fork.knife.circle.fill" : "checkmark.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(isRisk ? Color.orange : Color.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(percent)%")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(isRisk ? Color.orange : Color.blue)
                Text(medType)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(isRisk ? "Food Noise Zone" : "Protected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isRisk ? Color.orange : Color.green)
            }
        }
        .padding()
    }
}

// MARK: - Log Meal Intent

struct LogMealIntent: AppIntent {

    static var title: LocalizedStringResource = "Log Meal"
    static var description = IntentDescription("Open Glide to log a meal.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouterStore.shared.router?.route(to: .logMeal)
        return .result()
    }
}

// MARK: - Log Workout Intent

struct LogWorkoutIntent: AppIntent {

    static var title: LocalizedStringResource = "Log Workout"
    static var description = IntentDescription("Open Glide to log an exercise session.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouterStore.shared.router?.route(to: .logExercise)
        return .result()
    }
}

// MARK: - Food Noise Status Intent

struct FoodNoiseStatusIntent: AppIntent {

    static var title: LocalizedStringResource = "Food Noise Status"
    static var description = IntentDescription("Check whether you're currently in the food noise vulnerability window.")

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = AppGroup.loadSnapshot() else {
            return .result(dialog: "No injection logged yet. Open Glide to get started.")
        }

        let conc = snapshot.concentration()
        if conc < 0.40 {
            return .result(dialog: "Yes — you're currently in the food noise zone. Your \(snapshot.medicationType) concentration is \(Int(conc * 100))%. Try to stick to your meal plan and log what you eat.")
        } else {
            let crossover = snapshot.crossoverDate
            if crossover > .now {
                let hours = Int(crossover.timeIntervalSinceNow / 3_600)
                return .result(dialog: "Not yet. You'll enter the food noise zone in about \(hours) hours. Your current concentration is \(Int(conc * 100))%.")
            } else {
                return .result(dialog: "Your concentration is \(Int(conc * 100))% — you're in the protected zone this week.")
            }
        }
    }
}

// MARK: - App Shortcuts Provider

struct GlideShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckConcentrationIntent(),
            phrases: [
                "Check my \(.applicationName) concentration",
                "What's my GLP-1 level",
                "What's my Ozempic concentration",
                "Check my medication level in \(.applicationName)",
            ],
            shortTitle: "Check Concentration",
            systemImageName: "waveform.path.ecg"
        )
        AppShortcut(
            intent: FoodNoiseStatusIntent(),
            phrases: [
                "Am I in food noise in \(.applicationName)",
                "Check food noise status",
                "Is my \(.applicationName) concentration low",
            ],
            shortTitle: "Food Noise Status",
            systemImageName: "fork.knife.circle.fill"
        )
        AppShortcut(
            intent: LogShotIntent(),
            phrases: [
                "Log my shot in \(.applicationName)",
                "Log my injection in \(.applicationName)",
                "I just took my GLP-1",
            ],
            shortTitle: "Log Injection",
            systemImageName: "syringe.fill"
        )
        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "Log a meal in \(.applicationName)",
                "Log food in \(.applicationName)",
            ],
            shortTitle: "Log Meal",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogWorkoutIntent(),
            phrases: [
                "Log a workout in \(.applicationName)",
                "Log exercise in \(.applicationName)",
            ],
            shortTitle: "Log Workout",
            systemImageName: "figure.run"
        )
    }
}

// MARK: - Router bridge for App Intents
// App Intents run in a separate process so they can't access @Environment.
// This singleton is set by GlideApp.onAppear and lets intents call route(to:).

extension DeepLinkRouter {
    func route(to link: DeepLink) {
        // Re-use the existing private route logic by calling handle(url:)
        let path: String
        switch link {
        case .logShot:     path = "glide://medication/log"
        case .logMeal:     path = "glide://nutrition/log"
        case .logExercise: path = "glide://exercise/log"
        default:           path = "glide://home"
        }
        if let url = URL(string: path) { handle(url: url) }
    }
}

final class DeepLinkRouterStore {
    static let shared = DeepLinkRouterStore()
    var router: DeepLinkRouter?
    private init() {}
}
