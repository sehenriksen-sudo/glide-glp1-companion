// NotificationSettingsView.swift
//
// Notification preferences section — embed inside SettingsView as a Section,
// or present as a standalone NavigationLink destination.
//
// Usage in SettingsView:
//   NavigationLink("Notifications") { NotificationSettingsView() }

import SwiftUI
import UserNotifications

// MARK: - Standalone screen

struct NotificationSettingsView: View {

    @Environment(NotificationManager.self) private var manager

    // Mirror NotificationManager.settings into @AppStorage so prefs survive
    // kills without needing SwiftData. Keys match the manager's fields.
    @AppStorage("notif.shotReminder")    private var shotReminder    = true
    @AppStorage("notif.shotOverdue")     private var shotOverdue     = true
    @AppStorage("notif.foodNoiseWarn")   private var foodNoiseWarn   = true
    @AppStorage("notif.foodNoiseActive") private var foodNoiseActive = true
    @AppStorage("notif.reminderHour")    private var reminderHour    = 9
    @AppStorage("notif.reminderMinute")  private var reminderMinute  = 0
    @AppStorage("notif.shotInterval")    private var shotInterval    = 7

    // Binding proxy for the time picker
    @State private var reminderTime: Date = {
        var c = DateComponents(); c.hour = 9; c.minute = 0
        return Calendar.current.date(from: c) ?? .now
    }()

    var body: some View {
        Form {
            authSection
            shotSection
            foodNoiseSection
            scheduleSection
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            syncFromStorage()
            Task { await manager.refreshAuthState() }
            Task { await manager.refreshPending() }
        }
        .onChange(of: reminderTime) { syncTimeToStorage() }
    }

    // MARK: Auth banner

    @ViewBuilder
    private var authSection: some View {
        switch manager.authState {
        case .denied:
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "bell.slash.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notifications disabled")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Enable them in iOS Settings to receive shot reminders and food noise alerts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundStyle(.blue)
            }
        case .notDetermined:
            Section {
                Button {
                    Task {
                        await manager.requestAuthorization()
                        await manager.refreshPending()
                    }
                } label: {
                    Label("Enable Notifications", systemImage: "bell.badge")
                }
                .foregroundStyle(.blue)
            }
        default:
            EmptyView()
        }
    }

    // MARK: Shot notifications

    private var shotSection: some View {
        Section {
            Toggle(isOn: $shotReminder) {
                Label("Shot Reminder", systemImage: "syringe.fill")
            }
            .onChange(of: shotReminder) { saveAndSync() }

            Toggle(isOn: $shotOverdue) {
                Label("Shot Overdue Alert", systemImage: "exclamationmark.triangle.fill")
            }
            .onChange(of: shotOverdue) { saveAndSync() }

            if shotReminder {
                DatePicker(
                    "Reminder time",
                    selection: $reminderTime,
                    displayedComponents: .hourAndMinute
                )
                Stepper(
                    "Every \(shotInterval) days",
                    value: $shotInterval,
                    in: 5...14
                )
                .onChange(of: shotInterval) { saveAndSync() }
            }
        } header: {
            Text("Injection Schedule")
        } footer: {
            Text("You'll be reminded at the chosen time on your next injection day, and alerted the following day if you haven't logged a shot.")
        }
    }

    // MARK: Food noise notifications

    private var foodNoiseSection: some View {
        Section {
            Toggle(isOn: $foodNoiseWarn) {
                Label("6-Hour Warning", systemImage: "fork.knife.circle.fill")
            }
            .onChange(of: foodNoiseWarn) { saveAndSync() }

            Toggle(isOn: $foodNoiseActive) {
                Label("Zone Active Alert", systemImage: "bell.badge.fill")
            }
            .onChange(of: foodNoiseActive) { saveAndSync() }
        } header: {
            Text("Food Noise Zone")
        } footer: {
            Text("Glide calculates when your medication concentration drops below 40% and notifies you before — and exactly when — you enter the vulnerability window.")
        }
    }

    // MARK: Pending schedule

    private var scheduleSection: some View {
        Section {
            if manager.pending.isEmpty {
                Text("No notifications scheduled")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(manager.pending, id: \.identifier) { req in
                    PendingNotificationRow(request: req)
                }
            }
        } header: {
            HStack {
                Text("Scheduled")
                Spacer()
                if !manager.pending.isEmpty {
                    Button("Cancel All") {
                        manager.cancelAll()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: Persistence helpers

    private func syncFromStorage() {
        manager.settings.shotReminderEnabled    = shotReminder
        manager.settings.shotOverdueEnabled     = shotOverdue
        manager.settings.foodNoiseWarnEnabled   = foodNoiseWarn
        manager.settings.foodNoiseActiveEnabled = foodNoiseActive
        manager.settings.reminderHour           = reminderHour
        manager.settings.reminderMinute         = reminderMinute
        manager.settings.shotIntervalDays       = shotInterval

        var c = DateComponents()
        c.hour = reminderHour; c.minute = reminderMinute
        reminderTime = Calendar.current.date(from: c) ?? reminderTime
    }

    private func syncTimeToStorage() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        reminderHour   = c.hour   ?? 9
        reminderMinute = c.minute ?? 0
        saveAndSync()
    }

    private func saveAndSync() {
        manager.settings.shotReminderEnabled    = shotReminder
        manager.settings.shotOverdueEnabled     = shotOverdue
        manager.settings.foodNoiseWarnEnabled   = foodNoiseWarn
        manager.settings.foodNoiseActiveEnabled = foodNoiseActive
        manager.settings.reminderHour           = reminderHour
        manager.settings.reminderMinute         = reminderMinute
        manager.settings.shotIntervalDays       = shotInterval
        // Caller is responsible for calling reschedule(for:) after a new log is saved.
        // Settings changes here take effect the next time reschedule is called.
    }
}

// MARK: - Pending notification row

private struct PendingNotificationRow: View {

    let request: UNNotificationRequest

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(request.content.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let date = nextTriggerDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Scheduled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                UNUserNotificationCenter.current()
                    .removePendingNotificationRequests(withIdentifiers: [request.identifier])
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private var nextTriggerDate: Date? {
        if let t = request.trigger as? UNTimeIntervalNotificationTrigger { return t.nextTriggerDate() }
        if let t = request.trigger as? UNCalendarNotificationTrigger     { return t.nextTriggerDate() }
        return nil
    }

    private var icon: String {
        switch request.identifier {
        case GlideNotification.shotReminder.rawValue:    return "syringe.fill"
        case GlideNotification.shotOverdue.rawValue:     return "exclamationmark.triangle.fill"
        case GlideNotification.foodNoiseWarn.rawValue:   return "clock.fill"
        case GlideNotification.foodNoiseActive.rawValue: return "fork.knife.circle.fill"
        default:                                         return "bell.fill"
        }
    }

    private var color: Color {
        switch request.identifier {
        case GlideNotification.shotReminder.rawValue:    return .indigo
        case GlideNotification.shotOverdue.rawValue:     return .red
        case GlideNotification.foodNoiseWarn.rawValue:   return .orange
        case GlideNotification.foodNoiseActive.rawValue: return .orange
        default:                                         return .blue
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NotificationSettingsView()
            .environment(NotificationManager())
    }
}
