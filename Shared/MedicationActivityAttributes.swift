// MedicationActivityAttributes.swift
//
// Shared between the main app target AND the GlideWidget extension target.
// Add to Target Membership for both in Xcode.
//
// Info.plist (main app target) — add before shipping:
//   NSSupportsLiveActivities          Boolean  YES
//   NSSupportsLiveActivitiesFrequentUpdates  Boolean  YES   (optional — allows more frequent pushes)

import ActivityKit
import Foundation

// MARK: - Activity Attributes

struct MedicationActivityAttributes: ActivityAttributes {

    // ── Static data — set once at activity start, never changes ──────────
    let medicationType: String   // e.g. "Semaglutide"
    let doseMg:         Double
    let shotDate:       Date
    let halfLifeDays:   Double

    // ── Dynamic content state — updated as concentration changes ─────────
    struct ContentState: Codable, Hashable {
        /// Current concentration fraction (0.0–1.0), pre-computed so the
        /// widget extension doesn't need to re-derive it each render.
        var concentration:    Double
        var isInFoodNoiseZone: Bool
        /// Nil when the curve stays above 40 % for the full 7-day window.
        var crossoverDate:    Date?
        var nextDoseDate:     Date
        /// Allows the system to mark the activity "stale" if the app
        /// hasn't updated it within a reasonable window.
        var staleDate:        Date

        // MARK: Convenience

        var concentrationPercent: Int { Int(concentration * 100) }

        var statusLabel: String { isInFoodNoiseZone ? "Food Noise Zone" : "Protected" }

        var statusSFSymbol: String {
            isInFoodNoiseZone ? "fork.knife.circle.fill" : "checkmark.shield.fill"
        }

        var timeUntilNextEvent: String {
            let target = isInFoodNoiseZone ? nextDoseDate : (crossoverDate ?? nextDoseDate)
            return target.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        }

        var nextEventLabel: String {
            isInFoodNoiseZone ? "Next dose" : "Food noise zone"
        }
    }

    // MARK: Derived helpers (use static attributes in views)

    /// Sparkline sample points — computed from static attributes so they
    /// don't need to be stored in ContentState (saves payload space).
    func sparklinePoints() -> [(day: Double, value: Double)] {
        stride(from: 0.0, through: 7.0, by: 0.25).map { day in
            let elapsed = day
            let value   = pow(0.5, elapsed / halfLifeDays)
            return (day: day, value: value)
        }
    }
}

// MARK: - Factory helpers used by LiveActivityManager

extension MedicationActivityAttributes {

    /// Build a fresh ContentState for "right now".
    func currentContentState() -> ContentState {
        let elapsed       = max(0, Date.now.timeIntervalSince(shotDate) / 86_400)
        let concentration = pow(0.5, elapsed / halfLifeDays)
        let crossoverDays = halfLifeDays * log2(1.0 / 0.40)
        let crossoverDate = shotDate.addingTimeInterval(crossoverDays * 86_400)
        let nextDoseDate  = shotDate.addingTimeInterval(7 * 86_400)

        return ContentState(
            concentration:     concentration,
            isInFoodNoiseZone: concentration < 0.40,
            crossoverDate:     crossoverDays <= 7 ? crossoverDate : nil,
            nextDoseDate:      nextDoseDate,
            staleDate:         Date.now.addingTimeInterval(2 * 3_600)   // stale after 2 h
        )
    }
}
