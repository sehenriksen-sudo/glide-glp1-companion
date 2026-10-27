// AppReviewManager.swift
//
// Requests an App Store review at meaningful milestones —
// never interrupts the user mid-flow, never asks more than once per milestone.
//
// Milestones:
//   • 3rd injection logged
//   • First goal weight reached (current ≤ target)
//   • 14 days after install with ≥ 5 data points logged
//   • First HealthKit import completes
//
// Apple allows at most 3 review requests per 365-day period.
// This manager respects that by tracking request dates in UserDefaults.

import StoreKit
import SwiftUI
import Observation

// MARK: - Milestone keys (UserDefaults)

private enum ReviewKey {
    static let requestDates      = "review.requestDates"
    static let installDate       = "review.installDate"
    static let shotMilestone     = "review.milestone.shots"
    static let goalMilestone     = "review.milestone.goal"
    static let engagementMilestone = "review.milestone.engagement"
    static let healthKitMilestone  = "review.milestone.healthkit"
}

// MARK: - AppReviewManager

@Observable
@MainActor
final class AppReviewManager {

    // MARK: Init

    init() {
        // Record install date on first launch
        if UserDefaults.standard.object(forKey: ReviewKey.installDate) == nil {
            UserDefaults.standard.set(Date.now, forKey: ReviewKey.installDate)
        }
    }

    // MARK: Public trigger points — call from the relevant view after an action

    /// Call after every injection is saved. Triggers review on the 3rd.
    func didLogShot(totalShots: Int) {
        guard totalShots == 3,
              !milestoneSeen(ReviewKey.shotMilestone)
        else { return }
        markMilestone(ReviewKey.shotMilestone)
        requestReview(reason: "3rd injection logged")
    }

    /// Call after saving a new weight log. Triggers review if goal is reached.
    func didLogWeight(current: Double, target: Double) {
        guard target > 0, current <= target,
              !milestoneSeen(ReviewKey.goalMilestone)
        else { return }
        markMilestone(ReviewKey.goalMilestone)
        // Short delay so the user sees their goal-reached celebration first
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.requestReview(reason: "Goal weight reached")
        }
    }

    /// Call after a successful HealthKit import with new workouts.
    func didImportFromHealthKit(importedCount: Int) {
        guard importedCount > 0,
              !milestoneSeen(ReviewKey.healthKitMilestone)
        else { return }
        markMilestone(ReviewKey.healthKitMilestone)
        requestReview(reason: "HealthKit import")
    }

    /// Call from DashboardView.onAppear — triggers review after 14 days of active use.
    func checkEngagementMilestone(totalDataPoints: Int) {
        guard totalDataPoints >= 5,
              !milestoneSeen(ReviewKey.engagementMilestone)
        else { return }

        let installDate = UserDefaults.standard.object(forKey: ReviewKey.installDate) as? Date ?? .now
        let daysSinceInstall = Date.now.timeIntervalSince(installDate) / 86_400
        guard daysSinceInstall >= 14 else { return }

        markMilestone(ReviewKey.engagementMilestone)
        requestReview(reason: "14-day engagement")
    }

    // MARK: Private

    private func requestReview(reason: String) {
        // Apple cap: 3 requests per 365 days
        guard canRequestReview() else { return }

        recordRequest()

        // Find the active window scene and request the review there
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }

        SKStoreReviewController.requestReview(in: scene)
    }

    private func canRequestReview() -> Bool {
        let dates = requestDates()
        let oneYearAgo = Date.now.addingTimeInterval(-365 * 86_400)
        let recentRequests = dates.filter { $0 > oneYearAgo }
        return recentRequests.count < 3
    }

    private func requestDates() -> [Date] {
        (UserDefaults.standard.array(forKey: ReviewKey.requestDates) as? [Date]) ?? []
    }

    private func recordRequest() {
        var dates = requestDates()
        dates.append(.now)
        UserDefaults.standard.set(dates, forKey: ReviewKey.requestDates)
    }

    private func milestoneSeen(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    private func markMilestone(_ key: String) {
        UserDefaults.standard.set(true, forKey: key)
    }
}
