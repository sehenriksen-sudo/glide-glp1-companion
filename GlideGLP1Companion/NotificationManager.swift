// NotificationManager.swift
//
// Schedules and manages all local notifications for GlideGLP1Companion.
//
// Notification types:
//   • Shot reminder      — fires at the user's chosen time on injection day (day 7)
//   • Shot overdue       — fires 24 h after the due date if no new shot is logged
//   • Food noise warning — fires 6 h before concentration drops below 40 %
//   • Food noise active  — fires exactly when concentration crosses the 40 % threshold
//
// Inject into the environment alongside SubscriptionManager and HealthKitManager,
// then call reschedule(for:) whenever a new MedicationLog is inserted.

import Foundation
import UserNotifications
import Observation

// MARK: - Notification identifiers

enum GlideNotification: String {
    case shotReminder    = "glide.shot.reminder"
    case shotOverdue     = "glide.shot.overdue"
    case foodNoiseWarn   = "glide.foodnoise.warning"
    case foodNoiseActive = "glide.foodnoise.active"

    /// All identifiers — used for bulk cancellation before rescheduling.
    static var all: [String] { Self.allCases.map(\.rawValue) }
}

extension GlideNotification: CaseIterable {}

// MARK: - Notification Settings

/// Persisted via @AppStorage keys. Exposed in SettingsView.
struct NotificationSettings {
    // Enable / disable each type
    var shotReminderEnabled:    Bool   = true
    var shotOverdueEnabled:     Bool   = true
    var foodNoiseWarnEnabled:   Bool   = true
    var foodNoiseActiveEnabled: Bool   = true

    // Shot reminder fires at this time of day (hour + minute)
    var reminderHour:   Int = 9
    var reminderMinute: Int = 0

    // How many days after the last shot to fire the reminder (default: 7)
    var shotIntervalDays: Int = 7
}

// MARK: - Authorization State

enum NotificationAuthState {
    case notDetermined, authorized, denied, provisional
}

// MARK: - NotificationManager

@Observable
@MainActor
final class NotificationManager {

    // ── Public state ──────────────────────────────────────────────────────
    private(set) var authState:  NotificationAuthState = .notDetermined
    private(set) var pending:    [UNNotificationRequest] = []
    var settings = NotificationSettings()

    private let center = UNUserNotificationCenter.current()

    // MARK: Authorization

    /// Call once from onboarding or Settings. Safe to call multiple times.
    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            authState = granted ? .authorized : .denied
            if granted { registerCategories() }
        } catch {
            authState = .denied
        }
    }

    func refreshAuthState() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized:                authState = .authorized
        case .denied:                    authState = .denied
        case .provisional:               authState = .provisional
        case .notDetermined, .ephemeral: authState = .notDetermined
        @unknown default:               authState = .notDetermined
        }
    }

    // MARK: Schedule

    /// Primary entry point — cancel all pending Glide notifications and
    /// reschedule fresh ones based on the most recent injection.
    func reschedule(for log: MedicationLog) async {
        guard authState == .authorized || authState == .provisional else { return }

        // Cancel all existing before adding new ones
        center.removePendingNotificationRequests(withIdentifiers: GlideNotification.all)

        let med          = log.asMedication()
        let shotDate     = log.date
        let halfLife     = med.halfLifeDays
        let threshold    = 0.40

        // ── Shot reminder ────────────────────────────────────────────────
        if settings.shotReminderEnabled {
            let dueDate = shotDate.addingTimeInterval(
                Double(settings.shotIntervalDays) * 86_400
            )
            if let trigger = dailyTimeTrigger(on: dueDate,
                                              hour: settings.reminderHour,
                                              minute: settings.reminderMinute) {
                let content        = UNMutableNotificationContent()
                content.title      = "Time for Your Weekly Shot 💉"
                content.body       = "Your \(log.medicationType) dose is due today. Staying on schedule keeps your concentration in the protected zone."
                content.sound      = .default
                content.badge      = 1
                content.categoryIdentifier = GlideNotification.shotReminder.rawValue
                content.userInfo   = ["deepLink": "glide://medication/log"]
                let request = UNNotificationRequest(
                    identifier: GlideNotification.shotReminder.rawValue,
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)
            }
        }

        // ── Shot overdue (24 h after due date) ───────────────────────────
        if settings.shotOverdueEnabled {
            let overdueDate = shotDate.addingTimeInterval(
                Double(settings.shotIntervalDays + 1) * 86_400
            )
            if overdueDate > .now, let trigger = intervalTrigger(for: overdueDate) {
                let content        = UNMutableNotificationContent()
                content.title      = "Shot Overdue"
                content.body       = "You missed your scheduled \(log.medicationType) injection yesterday. Your concentration may already be in the food noise zone."
                content.sound      = .default
                content.categoryIdentifier = GlideNotification.shotOverdue.rawValue
                content.userInfo   = ["deepLink": "glide://medication/log"]
                let request = UNNotificationRequest(
                    identifier: GlideNotification.shotOverdue.rawValue,
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)
            }
        }

        // ── Crossover math ───────────────────────────────────────────────
        // t_crossover = halfLife × log₂(1 / threshold)
        let crossoverDays  = halfLife * log2(1.0 / threshold)
        let crossoverDate  = shotDate.addingTimeInterval(crossoverDays * 86_400)
        let warningDate    = crossoverDate.addingTimeInterval(-6 * 3_600)  // 6 h before

        // ── Food noise warning (6 h before crossover) ────────────────────
        if settings.foodNoiseWarnEnabled, warningDate > .now {
            let content        = UNMutableNotificationContent()
            content.title      = "Food Noise Zone in 6 Hours ⚠️"
            content.body       = "Your \(log.medicationType) concentration will drop below 40% around \(crossoverDate.formatted(.dateTime.hour().minute())). Plan your meals accordingly."
            content.sound      = .default
            content.categoryIdentifier = GlideNotification.foodNoiseWarn.rawValue
            content.userInfo   = [
                "crossoverDate": crossoverDate.timeIntervalSince1970,
                "deepLink": "glide://nutrition/log"
            ]
            let request = UNNotificationRequest(
                identifier: GlideNotification.foodNoiseWarn.rawValue,
                content: content,
                trigger: intervalTrigger(for: warningDate)!
            )
            try? await center.add(request)
        }

        // ── Food noise active (at crossover) ────────────────────────────
        if settings.foodNoiseActiveEnabled, crossoverDate > .now {
            let remaining = Int(crossoverDays)
            let content        = UNMutableNotificationContent()
            content.title      = "Food Noise Zone Active 🍽️"
            content.body       = "Day \(remaining): Your \(log.medicationType) concentration has dropped below 40%. You may experience increased appetite — log your meals and stay on track."
            content.sound      = UNNotificationSound(named: UNNotificationSoundName("gentle_chime.aiff"))
            content.badge      = 1
            content.categoryIdentifier = GlideNotification.foodNoiseActive.rawValue
            content.userInfo   = ["deepLink": "glide://nutrition/log"]
            let request = UNNotificationRequest(
                identifier: GlideNotification.foodNoiseActive.rawValue,
                content: content,
                trigger: intervalTrigger(for: crossoverDate)!
            )
            try? await center.add(request)
        }

        await refreshPending()
    }

    // MARK: Cancel

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: GlideNotification.all)
        center.removeDeliveredNotifications(withIdentifiers: GlideNotification.all)
        pending = []
    }

    func cancel(_ notification: GlideNotification) {
        center.removePendingNotificationRequests(withIdentifiers: [notification.rawValue])
        center.removeDeliveredNotifications(withIdentifiers: [notification.rawValue])
        Task { await refreshPending() }
    }

    // MARK: Pending list (for Settings display)

    func refreshPending() async {
        pending = await center.pendingNotificationRequests()
            .filter { GlideNotification.all.contains($0.identifier) }
            .sorted {
                triggerDate(for: $0) ?? .distantFuture < triggerDate(for: $1) ?? .distantFuture
            }
    }

    // MARK: Badge

    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
    }

    // MARK: Private helpers

    /// Trigger that fires at the given hour:minute on the same calendar day as `date`.
    private func dailyTimeTrigger(on date: Date, hour: Int, minute: Int) -> UNCalendarNotificationTrigger? {
        guard date > .now else { return nil }
        var components        = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour       = hour
        components.minute     = minute
        components.second     = 0
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    /// Trigger that fires at an absolute point in time.
    private func intervalTrigger(for date: Date) -> UNTimeIntervalNotificationTrigger? {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return nil }
        return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
    }

    private func triggerDate(for request: UNNotificationRequest) -> Date? {
        if let t = request.trigger as? UNTimeIntervalNotificationTrigger {
            return t.nextTriggerDate()
        }
        if let t = request.trigger as? UNCalendarNotificationTrigger {
            return t.nextTriggerDate()
        }
        return nil
    }

    /// Register actionable notification categories.
    private func registerCategories() {
        let logShotAction = UNNotificationAction(
            identifier: "LOG_SHOT",
            title: "Log Shot Now",
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: [.destructive]
        )
        let logMealAction = UNNotificationAction(
            identifier: "LOG_MEAL",
            title: "Log a Meal",
            options: [.foreground]
        )

        let shotCategory = UNNotificationCategory(
            identifier: GlideNotification.shotReminder.rawValue,
            actions: [logShotAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        let overdueCategory = UNNotificationCategory(
            identifier: GlideNotification.shotOverdue.rawValue,
            actions: [logShotAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        let foodWarnCategory = UNNotificationCategory(
            identifier: GlideNotification.foodNoiseWarn.rawValue,
            actions: [logMealAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        let foodActiveCategory = UNNotificationCategory(
            identifier: GlideNotification.foodNoiseActive.rawValue,
            actions: [logMealAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([
            shotCategory, overdueCategory, foodWarnCategory, foodActiveCategory
        ])
    }
}
