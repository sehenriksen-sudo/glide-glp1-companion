// HapticManager.swift
//
// Centralised haptic feedback — call semantic methods so individual views
// stay free of UIKit imports and haptic logic.
// Inject once via .environment(HapticManager()) and use @Environment(HapticManager.self).

import SwiftUI
import UIKit

// MARK: - HapticManager

@Observable
final class HapticManager {

    // ── Shared generators — reuse avoids the latency hit of repeated init ──
    private let light   = UIImpactFeedbackGenerator(style: .light)
    private let medium  = UIImpactFeedbackGenerator(style: .medium)
    private let heavy   = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid   = UIImpactFeedbackGenerator(style: .rigid)
    private let soft    = UIImpactFeedbackGenerator(style: .soft)
    private let notif   = UINotificationFeedbackGenerator()
    private let select  = UISelectionFeedbackGenerator()

    // MARK: Generic

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        generator(for: style).impactOccurred()
    }

    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notif.notificationOccurred(type)
    }

    func selection() { select.selectionChanged() }

    // MARK: Semantic — app events

    /// Tapping a tab bar item.
    func tabChanged()        { light.impactOccurred(intensity: 0.6) }

    /// Toggling a switch or picker selection.
    func toggleChanged()     { soft.impactOccurred() }

    /// Confirming a destructive action (delete, cancel subscription).
    func destructive()       { notif.notificationOccurred(.warning) }

    /// A form save succeeded.
    func saveSuceeded()      { notif.notificationOccurred(.success) }

    /// A form validation error.
    func validationError()   { notif.notificationOccurred(.error) }

    /// Shot / injection logged — satisfying double-tap.
    func shotLogged() {
        medium.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.heavy.impactOccurred(intensity: 0.8)
        }
    }

    /// Weight logged — light confirmation.
    func weightLogged()      { soft.impactOccurred(intensity: 0.9) }

    /// Meal logged — medium confirmation.
    func mealLogged()        { medium.impactOccurred(intensity: 0.7) }

    /// Workout logged — energetic heavy tap.
    func workoutLogged()     { heavy.impactOccurred() }

    /// Goal weight reached — celebratory triple pulse.
    func goalReached() {
        for delay in [0.0, 0.14, 0.28] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.notif.notificationOccurred(.success)
            }
        }
    }

    /// User has entered the food noise zone — urgent warning rhythm.
    func foodNoiseZoneEntered() {
        rigid.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.rigid.impactOccurred(intensity: 0.6)
        }
    }

    /// Drag/scroll threshold crossed (e.g. chart scrubbing).
    func thresholdCrossed()  { rigid.impactOccurred(intensity: 0.5) }

    /// Premium paywall opened.
    func paywallOpened()     { soft.impactOccurred(intensity: 0.5) }

    /// Subscription purchased.
    func subscriptionPurchased() {
        for delay in [0.0, 0.1, 0.22, 0.36] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.notif.notificationOccurred(.success)
            }
        }
    }

    // MARK: Prepare (call just before known interaction to reduce latency)

    func prepareForShot()    { medium.prepare(); heavy.prepare() }
    func prepareForSave()    { notif.prepare() }

    // MARK: Private

    private func generator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .light:  return light
        case .medium: return medium
        case .heavy:  return heavy
        case .rigid:  return rigid
        case .soft:   return soft
        @unknown default: return medium
        }
    }
}

// MARK: - View helper

extension View {
    /// Prepare haptic generators when a view appears (reduces first-tap latency).
    func prepareHaptics(_ manager: HapticManager) -> some View {
        onAppear { manager.prepareForSave() }
    }
}
