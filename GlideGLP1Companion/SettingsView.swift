// SettingsView.swift
//
// Settings tab — user profile, goals, subscription status, privacy.

import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext)              private var context
    @Environment(SubscriptionManager.self)    private var store
    @Environment(NotificationManager.self)    private var notificationManager
    @Query                                    private var configs: [UserConfiguration]

    // Local edit state — synced from/to UserConfiguration on appear/save
    @State private var currentWeight       = ""
    @State private var targetWeight        = ""
    @State private var medicationCost      = ""
    @State private var selectedMedication  = GLP1MedicationType.semaglutide
    @State private var showPaywall         = false
    @State private var showRestoreAlert    = false
    @State private var restoreMessage      = ""

    private var config: UserConfiguration? { configs.first }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                goalsSection
                subscriptionSection
                notificationsSection
                dataSection
                privacySection
                aboutSection
            }
            .navigationTitle("Settings")
            .onAppear(perform: loadConfig)
            .onChange(of: selectedMedication) { saveConfig() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .alert("Restore Purchases", isPresented: $showRestoreAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreMessage)
            }
        }
    }

    // MARK: Profile

    private var profileSection: some View {
        Section {
            Picker("Medication", selection: $selectedMedication) {
                ForEach(GLP1MedicationType.allCases) {
                    Text($0.rawValue).tag($0)
                }
            }
            weightField("Current weight", text: $currentWeight)
            weightField("Target weight",  text: $targetWeight)
            HStack {
                Text("Monthly cost")
                Spacer()
                TextField("0", text: $medicationCost)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .onSubmit { saveConfig() }
                Text("$").foregroundStyle(.secondary)
            }
        } header: {
            Text("My Profile")
        } footer: {
            Text("Weight stored in kg. Used for goal tracking and cost modelling.")
                .font(.caption)
        }
    }

    private func weightField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0.0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .onSubmit { saveConfig() }
            Text("kg").foregroundStyle(.secondary)
        }
    }

    // MARK: Goals

    private var goalsSection: some View {
        Section("Goals") {
            if let cw = Double(currentWeight.replacingOccurrences(of: ",", with: ".")),
               let tw = Double(targetWeight.replacingOccurrences(of: ",", with: ".")),
               cw > 0, tw > 0 {
                let diff = cw - tw
                let weeks = diff > 0 ? Int(diff / 0.5) : 0  // ~0.5 kg/week typical GLP-1 loss
                HStack {
                    Label("Weight to lose", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Text(String(format: "%.1f kg", max(0, diff)))
                        .foregroundStyle(.secondary)
                }
                if weeks > 0 {
                    HStack {
                        Label("Est. timeline", systemImage: "calendar.badge.clock")
                            .foregroundStyle(.blue)
                        Spacer()
                        Text("~\(weeks) weeks")
                            .foregroundStyle(.secondary)
                    }
                }
                if let cost = Double(medicationCost), cost > 0, weeks > 0 {
                    HStack {
                        Label("Est. total cost", systemImage: "dollarsign.circle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Text(String(format: "$%.0f", cost * Double(weeks) / 4.33))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Enter your current and target weight above to see projections.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Subscription

    private var subscriptionSection: some View {
        Section("Subscription") {
            if store.isPremium {
                HStack {
                    Label("Premium Active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.blue)
                    Spacer()
                    if let expiry = store.expirationDate {
                        Text("Renews \(expiry.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let period = store.activePeriodType {
                    HStack {
                        Text("Plan")
                        Spacer()
                        Text(period == .normal ? "Monthly" : "Annual")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack {
                        Label("Unlock Premium", systemImage: "star.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .indigo],
                                   startPoint: .leading, endPoint: .trailing)
                )
            }

            Button {
                Task { await restorePurchases() }
            } label: {
                HStack {
                    if store.isRestoring {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("Restore Purchases")
                    }
                }
            }
            .foregroundStyle(.secondary)
            .disabled(store.isRestoring)
        }
    }

    // MARK: Data

    private var dataSection: some View {
        Section("Data") {
            NavigationLink {
                DataExportView()
            } label: {
                Label("Export Data", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        Section {
            LocalPrivacyNote(style: .card)
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
        } header: {
            Text("Data & Privacy")
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        Section("Reminders") {
            NavigationLink {
                NotificationSettingsView()
            } label: {
                HStack {
                    Label("Notifications", systemImage: "bell.fill")
                    Spacer()
                    // Inline status badge
                    Text(notificationManager.authState == .authorized ? "On" : "Off")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    .foregroundStyle(.secondary)
            }
            Link(destination: URL(string: "https://example.com/terms")!) {
                HStack {
                    Text("Terms of Use")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Link(destination: URL(string: "https://example.com/privacy")!) {
                HStack {
                    Text("Privacy Policy")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: Persistence

    private func loadConfig() {
        guard let c = config else { return }
        currentWeight      = c.currentWeight      > 0 ? String(c.currentWeight)      : ""
        targetWeight       = c.targetWeight        > 0 ? String(c.targetWeight)       : ""
        medicationCost     = c.monthlyMedicationCost > 0 ? String(c.monthlyMedicationCost) : ""
        selectedMedication = GLP1MedicationType(rawValue: c.selectedMedication) ?? .semaglutide
    }

    private func saveConfig() {
        let cw   = Double(currentWeight.replacingOccurrences(of: ",", with: "."))    ?? 0
        let tw   = Double(targetWeight.replacingOccurrences(of: ",", with: "."))     ?? 0
        let cost = Double(medicationCost.replacingOccurrences(of: ",", with: "."))   ?? 0

        if let existing = config {
            existing.currentWeight         = cw
            existing.targetWeight          = tw
            existing.monthlyMedicationCost = cost
            existing.selectedMedication    = selectedMedication.rawValue
        } else {
            context.insert(UserConfiguration(
                selectedMedication:    selectedMedication.rawValue,
                targetWeight:          tw,
                currentWeight:         cw,
                monthlyMedicationCost: cost
            ))
        }
        try? context.save()
    }

    private func restorePurchases() async {
        do {
            try await store.restorePurchases()
            restoreMessage = store.isPremium
                ? "Premium subscription restored successfully."
                : "No active subscription found on this Apple ID."
        } catch {
            restoreMessage = error.localizedDescription
        }
        showRestoreAlert = true
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .modelContainer(for: UserConfiguration.self, inMemory: true)
        .environment(SubscriptionManager())
}
