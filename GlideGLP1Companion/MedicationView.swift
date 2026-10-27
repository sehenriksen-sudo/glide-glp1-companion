// MedicationView.swift
//
// Medication tab — log history + live concentration chart for the active injection.

import SwiftUI
import SwiftData

struct MedicationView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \MedicationLog.date, order: .reverse) private var logs: [MedicationLog]

    @State private var showAddSheet    = false
    @State private var logToDelete:    MedicationLog?
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Live concentration chart for the most recent shot
                    if let latest = logs.first {
                        MedicationConcentrationChart(medication: latest.asMedication())
                            .padding(.horizontal, 16)
                    } else {
                        emptyHero
                    }

                    // Shot history
                    if !logs.isEmpty {
                        historySection
                    }
                }
                .padding(.bottom, 100) // clear tab bar
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Medication")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) { AddMedicationSheet() }
            .alert("Delete log entry?", isPresented: $showDeleteAlert, presenting: logToDelete) { log in
                Button("Delete", role: .destructive) { delete(log) }
                Button("Cancel", role: .cancel) {}
            } message: { log in
                Text("\(log.medicationType) · \(log.doseMg.formatted()) mg · \(log.date.formatted(date: .abbreviated, time: .shortened))")
            }
        }
    }

    // MARK: Empty hero

    private var emptyHero: some View {
        VStack(spacing: 16) {
            Image(systemName: "syringe")
                .font(.system(size: 52))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.indigo)
            Text("No injections logged")
                .font(.title3.weight(.semibold))
            Text("Log your first shot to see your\n7-day concentration curve.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Log Injection") { showAddSheet = true }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
        }
        .padding(40)
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Injection History")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 1) {
                ForEach(Array(logs.enumerated()), id: \.element.id) { index, log in
                    MedicationLogRow(log: log, isLatest: index == 0)
                        .contentShape(Rectangle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                logToDelete    = log
                                showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .background(Color(.systemBackground))
                    if index < logs.count - 1 {
                        Divider().padding(.leading, 72)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func delete(_ log: MedicationLog) {
        context.delete(log)
        try? context.save()
    }
}

// MARK: - Medication Log Row

private struct MedicationLogRow: View {
    let log:      MedicationLog
    let isLatest: Bool

    private var conc: Double {
        log.asMedication().remainingConcentration().fraction
    }

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isLatest ? Color.indigo.opacity(0.12) : Color(.systemGray5))
                    .frame(width: 44, height: 44)
                Image(systemName: "syringe.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isLatest ? Color.indigo : Color(.systemGray2))
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(log.medicationType)
                        .font(.system(size: 15, weight: .semibold))
                    if isLatest {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.indigo, in: Capsule())
                    }
                }
                Text("\(log.doseMg.formatted()) mg · \(log.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Remaining concentration (only meaningful for active)
            if isLatest {
                VStack(spacing: 2) {
                    Text("\(Int(conc * 100))%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(conc < 0.40 ? .orange : .indigo)
                    Text("remaining")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Add Medication Sheet (shared with DashboardView)

struct AddMedicationSheet: View {
    @Environment(\.modelContext)           private var context
    @Environment(\.dismiss)                private var dismiss
    @Environment(NotificationManager.self) private var notificationManager
    @Environment(LiveActivityManager.self) private var liveActivityManager
    @Environment(HapticManager.self)       private var hapticManager
    @Environment(AppReviewManager.self)    private var appReviewManager
    @Environment(SpotlightManager.self)    private var spotlightManager
    @State private var type = GLP1MedicationType.semaglutide
    @State private var dose = 1.0
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    Picker("Type", selection: $type) {
                        ForEach(GLP1MedicationType.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Picker("Dose", selection: $dose) {
                        ForEach(type.availableDoses, id: \.self) {
                            Text("\($0.formatted()) mg").tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Injection Date & Time") {
                    DatePicker("Date", selection: $date, in: ...Date.now)
                }
                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Half-life: \(String(format: "%.0f days", type.typicalHalfLifeDays)) (clinical default)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Log Injection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let log = MedicationLog(date: date, doseMg: dose, medicationType: type.rawValue)
                        context.insert(log)
                        try? context.save()
                        // Push to shared App Group store so the widget can read it
                        AppGroup.save(SharedMedicationSnapshot(
                            medicationType: type.rawValue,
                            shotDate:       date,
                            doseMg:         dose,
                            halfLifeDays:   type.typicalHalfLifeDays
                        ))
                        // Haptic feedback
                        hapticManager.shotLogged()
                        // App review milestone
                        let totalShots = (try? context.fetchCount(FetchDescriptor<MedicationLog>())) ?? 0
                        appReviewManager.didLogShot(totalShots: totalShots)
                        // Reschedule notifications, start Live Activity, index in Spotlight
                        Task {
                            await notificationManager.reschedule(for: log)
                            await liveActivityManager.start(for: log)
                            let nextDose = log.date.addingTimeInterval(7 * 86_400)
                            liveActivityManager.scheduleEnd(at: nextDose)
                            await spotlightManager.index(medication: log)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: type) { dose = type.availableDoses.first ?? 1.0 }
    }
}

// MARK: - Preview

#Preview {
    MedicationView()
        .modelContainer(for: MedicationLog.self, inMemory: true)
        .environment(SubscriptionManager())
}
