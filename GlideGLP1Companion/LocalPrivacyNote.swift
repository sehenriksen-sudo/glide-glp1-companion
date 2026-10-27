// LocalPrivacyNote.swift
//
// Reusable privacy disclosure component.
// Drop into onboarding and Settings screens:
//
//   LocalPrivacyNote()              // default compact card
//   LocalPrivacyNote(style: .banner) // slim inline banner

import SwiftUI

// MARK: - Style

enum LocalPrivacyNoteStyle {
    /// Full card with icon, heading, and body text. Use in Settings and onboarding.
    case card
    /// Single-line banner for tighter spaces (e.g. above a form section).
    case banner
}

// MARK: - View

struct LocalPrivacyNote: View {

    var style: LocalPrivacyNoteStyle = .card

    var body: some View {
        switch style {
        case .card:   cardView
        case .banner: bannerView
        }
    }

    // MARK: Card

    private var cardView: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.green)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 5) {
                Text("Local Data Privacy Control")
                    .font(.system(size: 14, weight: .semibold))

                Text(privacyStatement)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.green.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.green.opacity(0.20), lineWidth: 1)
        }
    }

    // MARK: Banner

    private var bannerView: some View {
        Label {
            Text(privacyStatement)
                .font(.caption2)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "lock.shield.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.green)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Copy

    private let privacyStatement =
        "Your health, medication, and food logs are securely encrypted " +
        "and stored entirely on your device. Glide never uploads your " +
        "medical profile to external tracking servers."
}

// MARK: - Settings Section Helper

/// Drop-in section footer for any SwiftUI Form or List in Settings.
struct PrivacySettingsSection: View {
    var body: some View {
        Section {
            LocalPrivacyNote(style: .card)
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
        } header: {
            Text("Data & Privacy")
        }
    }
}

// MARK: - Previews

#Preview("Card") {
    LocalPrivacyNote(style: .card)
        .padding()
}

#Preview("Banner") {
    Form {
        Section("Weight Log") {
            Text("Add entry…")
        }
        Section {
            LocalPrivacyNote(style: .banner)
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
        }
    }
}

#Preview("Settings Section") {
    Form { PrivacySettingsSection() }
}
