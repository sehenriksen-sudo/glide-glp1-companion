// DeepLinkRouter.swift
//
// Single source of truth for all in-app navigation driven by:
//   • Tapping a local notification (via GlideAppDelegate)
//   • Opening a glide:// URL (via .onOpenURL in ContentView)
//   • Notification action buttons ("Log Shot Now", "Log a Meal")
//
// URL scheme: glide://
//   glide://home                      → Home tab
//   glide://medication                → Medication tab
//   glide://medication/log            → Medication tab + open log-shot sheet
//   glide://nutrition                 → Nutrition tab
//   glide://nutrition/log             → Nutrition tab + open log-meal sheet
//   glide://exercise                  → Exercise tab
//   glide://exercise/log              → Exercise tab + open log-workout sheet
//   glide://settings                  → Settings tab
//   glide://settings/notifications    → Settings tab + push notification settings
//
// Register the scheme in Xcode:
//   Target → Info → URL Types → + → URL Schemes: glide

import SwiftUI
import UserNotifications

// MARK: - Deep Link destination

enum DeepLink: Equatable {
    case home
    case medication
    case logShot
    case nutrition
    case logMeal
    case exercise
    case logExercise
    case settings
    case notificationSettings
}

// MARK: - Router

@Observable
@MainActor
final class DeepLinkRouter {

    // ── Navigation state ──────────────────────────────────────────────────
    var selectedTab:              AppTab = .home

    // Sheet presentation flags — each view observes the one(s) it owns
    var presentLogShot:           Bool   = false
    var presentLogMeal:           Bool   = false
    var presentLogExercise:       Bool   = false
    var presentNotifSettings:     Bool   = false

    // ── URL handling ──────────────────────────────────────────────────────

    /// Called from ContentView's `.onOpenURL` modifier.
    func handle(url: URL) {
        guard url.scheme?.lowercased() == "glide" else { return }
        let host = url.host?.lowercased() ?? ""
        let path = url.pathComponents.dropFirst().first?.lowercased() ?? ""

        route(to: deepLink(from: host, path: path))
    }

    // ── Notification handling ─────────────────────────────────────────────

    /// Called from GlideAppDelegate when the user taps a notification or action button.
    func handle(response: UNNotificationResponse) {
        let id     = response.notification.request.identifier
        let action = response.actionIdentifier

        // Action buttons take priority over the notification body tap
        switch action {
        case "LOG_SHOT":
            route(to: .logShot)
        case "LOG_MEAL":
            route(to: .logMeal)
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification body — navigate to the relevant screen
            route(to: destination(forNotificationID: id))
        default:
            break
        }
    }

    // MARK: Private routing

    private func route(to link: DeepLink) {
        switch link {
        case .home:
            selectedTab = .home

        case .medication:
            selectedTab = .medication

        case .logShot:
            selectedTab        = .medication
            // Small delay so the tab switch completes before the sheet appears
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                presentLogShot = true
            }

        case .nutrition:
            selectedTab = .nutrition

        case .logMeal:
            selectedTab      = .nutrition
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                presentLogMeal = true
            }

        case .exercise:
            selectedTab = .exercise

        case .logExercise:
            selectedTab       = .exercise
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                presentLogExercise = true
            }

        case .settings:
            selectedTab = .settings

        case .notificationSettings:
            selectedTab = .settings
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                presentNotifSettings = true
            }
        }
    }

    private func deepLink(from host: String, path: String) -> DeepLink {
        switch (host, path) {
        case ("home",       _):           return .home
        case ("medication", "log"):       return .logShot
        case ("medication", _):           return .medication
        case ("nutrition",  "log"):       return .logMeal
        case ("nutrition",  _):           return .nutrition
        case ("exercise",   "log"):       return .logExercise
        case ("exercise",   _):           return .exercise
        case ("settings",   "notifications"): return .notificationSettings
        case ("settings",   _):           return .settings
        default:                          return .home
        }
    }

    private func destination(forNotificationID id: String) -> DeepLink {
        switch id {
        case GlideNotification.shotReminder.rawValue,
             GlideNotification.shotOverdue.rawValue:
            return .logShot

        case GlideNotification.foodNoiseWarn.rawValue,
             GlideNotification.foodNoiseActive.rawValue:
            return .nutrition

        default:
            return .home
        }
    }
}
