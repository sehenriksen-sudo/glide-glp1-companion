// SharedMedicationStore.swift
//
// Bridges the main app's SwiftData store and the Widget extension.
// Both targets must belong to the same App Group:
//
//   Signing & Capabilities → + Capability → App Groups
//   Identifier: group.com.glide.shared   (must match appGroupID below)
//
// The main app writes here after every injection log.
// The widget reads from here — it cannot access SwiftData directly.

import Foundation

// MARK: - Shared container identifier

enum AppGroup {
    static let id = "group.com.glide.shared"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}

// MARK: - Shared medication snapshot

/// Lightweight, Codable summary of the active injection — safe to store in UserDefaults.
struct SharedMedicationSnapshot: Codable {
    let medicationType:   String   // GLP1MedicationType.rawValue
    let shotDate:         Date
    let doseMg:           Double
    let halfLifeDays:     Double

    // MARK: Derived — computed on read so the widget always has fresh values

    /// Remaining concentration fraction at the current moment (0.0–1.0).
    func concentration(at date: Date = .now) -> Double {
        let elapsed = max(0, date.timeIntervalSince(shotDate) / 86_400)
        return pow(0.5, elapsed / halfLifeDays)
    }

    /// Day when concentration crosses 40 % threshold.
    var crossoverDate: Date {
        let days = halfLifeDays * log2(1.0 / 0.40)
        return shotDate.addingTimeInterval(days * 86_400)
    }

    var nextDoseDate: Date {
        shotDate.addingTimeInterval(7 * 86_400)
    }

    var isInFoodNoiseZone: Bool { concentration() < 0.40 }

    /// Sample points for the sparkline (one per 0.5 days over 7 days).
    func sparklinePoints(from start: Date = .now) -> [(day: Double, value: Double)] {
        let origin = shotDate
        return stride(from: 0.0, through: 7.0, by: 0.25).map { day in
            let date  = origin.addingTimeInterval(day * 86_400)
            return (day: day, value: concentration(at: date))
        }
    }
}

// MARK: - Persistence

private let snapshotKey = "activeInjectionSnapshot"

extension AppGroup {
    /// Write the active injection to the shared container.
    /// Call this every time a new `MedicationLog` is saved.
    static func save(_ snapshot: SharedMedicationSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
        // Ask WidgetKit to reload all timelines immediately
        WidgetCenterBridge.reloadAll()
    }

    /// Read the most recently saved snapshot. Returns nil on first launch.
    static func loadSnapshot() -> SharedMedicationSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(SharedMedicationSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }
}

// MARK: - WidgetCenter bridge
// Calling WidgetCenter.shared.reloadAllTimelines() from the main app target
// works fine, but the shared store file is also compiled into the widget target
// where WidgetCenter is available natively. This stub avoids a direct import
// of WidgetKit in a file shared across both targets.

enum WidgetCenterBridge {
    static var reloadAll: () -> Void = { }
}
