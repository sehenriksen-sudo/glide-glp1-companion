// ExerciseLogView.swift
//
// Full exercise tracking screen — HealthKit import + manual entry.
//
// Requirements in environment:
//   .modelContainer(container)          — from GlideApp
//   .environment(healthKitManager)      — add @State private var healthKitManager = HealthKitManager()
//                                         to GlideApp and inject it like SubscriptionManager

import SwiftUI
import SwiftData

// MARK: - Main View

struct ExerciseLogView: View {

    @Environment(\.modelContext)         private var context
    @Environment(HealthKitManager.self)  private var hkManager
    @Environment(AppReviewManager.self)  private var appReviewManager
    @Environment(SpotlightManager.self)  private var spotlightManager

    @Query(sort: \ExerciseLog.date, order: .reverse)
    private var logs: [ExerciseLog]

    @State private var showAddSheet     = false
    @State private var showImportBanner = false
    @State private var importMessage    = ""

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if logs.isEmpty {
                    emptyState
                } else {
                    logList
                }
            }
            .navigationTitle("Exercise")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    importButton
                    addButton
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddExerciseSheet()
            }
            .overlay(alignment: .bottom) {
                if showImportBanner {
                    importResultBanner
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 16)
                }
            }
            .animation(.spring(duration: 0.35), value: showImportBanner)
            .task {
                if hkManager.authState == .notDetermined {
                    await hkManager.requestAuthorization()
                }
            }
        }
    }

    // MARK: List

    private var logList: some View {
        List {
            weeklySummarySection
            entriesSection
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Weekly summary

    private var weeklySummarySection: some View {
        let week = weekLogs
        let totalMin  = week.reduce(0) { $0 + $1.durationMinutes }
        let totalKcal = week.reduce(0) { $0 + $1.activeCalories }

        return Section {
            HStack(spacing: 0) {
                summaryPill(label: "Sessions",  value: "\(week.count)",         icon: "figure.mixed.cardio", color: .blue)
                Divider().frame(height: 40)
                summaryPill(label: "Minutes",   value: "\(totalMin)",           icon: "clock.fill",          color: .indigo)
                Divider().frame(height: 40)
                summaryPill(label: "Calories",  value: totalKcal > 0 ? "\(totalKcal)" : "—",
                            icon: "flame.fill", color: .orange)
            }
            .padding(.vertical, 6)
        } header: {
            Text("This Week")
        }
    }

    private func summaryPill(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Entries

    private var entriesSection: some View {
        Section {
            ForEach(logs) { log in
                ExerciseRow(log: log)
            }
            .onDelete(perform: delete)
        } header: {
            Text("All Workouts")
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Workouts Yet", systemImage: "figure.run.circle")
        } description: {
            Text("Import from Apple Health or add a workout manually.")
        } actions: {
            Button("Import from Health") { Task { await runImport() } }
                .buttonStyle(.borderedProminent)
            Button("Add Manually") { showAddSheet = true }
                .buttonStyle(.bordered)
        }
    }

    // MARK: Toolbar buttons

    private var importButton: some View {
        Button {
            Task { await runImport() }
        } label: {
            if hkManager.isImporting {
                ProgressView().scaleEffect(0.75)
            } else {
                Label("Import from Health", systemImage: "heart.fill")
                    .labelStyle(.iconOnly)
            }
        }
        .disabled(hkManager.isImporting)
    }

    private var addButton: some View {
        Button { showAddSheet = true } label: {
            Image(systemName: "plus")
        }
    }

    // MARK: Import result banner

    private var importResultBanner: some View {
        Text(importMessage)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    // MARK: Helpers

    private var weekLogs: [ExerciseLog] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        return logs.filter { $0.date >= cutoff }
    }

    private func runImport() async {
        let result = await hkManager.importRecentWorkouts(days: 90, into: context)
        // App review milestone
        appReviewManager.didImportFromHealthKit(importedCount: result.imported)
        // Index newly imported logs in Spotlight (most recent batch)
        if result.imported > 0 {
            for log in logs.prefix(result.imported) {
                await spotlightManager.index(exercise: log)
            }
        }
        importMessage = result.imported > 0
            ? "Imported \(result.imported) workout\(result.imported == 1 ? "" : "s")"
            : result.duplicates > 0 ? "Already up to date" : "No new workouts found"
        withAnimation { showImportBanner = true }
        try? await Task.sleep(for: .seconds(2.8))
        withAnimation { showImportBanner = false }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(logs[index]) }
        try? context.save()
    }
}

// MARK: - Exercise Row

private struct ExerciseRow: View {

    let log: ExerciseLog

    var body: some View {
        HStack(spacing: 14) {
            // Type icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: log.type.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            // Details
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(log.workoutType)
                        .font(.system(size: 15, weight: .semibold))
                    if log.isFromHealthKit {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.pink)
                    }
                }
                HStack(spacing: 8) {
                    Label("\(log.durationMinutes) min", systemImage: "clock")
                    if log.activeCalories > 0 {
                        Label("\(log.activeCalories) kcal", systemImage: "flame")
                    }
                    if let dist = log.formattedDistance {
                        Label(dist, systemImage: "arrow.forward")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }

            Spacer()

            Text(log.date, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var iconColor: Color {
        switch log.type {
        case .running, .walking, .hiking:    return .blue
        case .cycling:                       return .green
        case .swimming, .rowing:             return .cyan
        case .strengthTraining, .crossFit:   return .orange
        case .yoga, .pilates, .stretching:   return .purple
        case .hiit:                          return .red
        default:                             return .indigo
        }
    }
}

// MARK: - Add Exercise Sheet

struct AddExerciseSheet: View {

    @Environment(\.modelContext)        private var context
    @Environment(\.dismiss)             private var dismiss
    @Environment(HapticManager.self)    private var hapticManager
    @Environment(SpotlightManager.self) private var spotlightManager

    @State private var selectedType:     ExerciseType = .running
    @State private var date:             Date         = .now
    @State private var durationMinutes:  Int          = 30
    @State private var activeCalories:   Int          = 0
    @State private var distanceMeters:   Double       = 0
    @State private var notes:            String       = ""

    @FocusState private var focusedField: Field?
    private enum Field { case calories, distance, notes }

    var body: some View {
        NavigationStack {
            Form {
                // Type picker
                Section("Workout Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(ExerciseType.allCases) { type in
                            Label(type.rawValue, systemImage: type.systemImage).tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                // Date & duration
                Section("When") {
                    DatePicker("Date & Time", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Stepper(
                        "\(durationMinutes) minutes",
                        value: $durationMinutes,
                        in: 1...600,
                        step: 5
                    )
                }

                // Stats
                Section("Stats (optional)") {
                    HStack {
                        Text("Calories burned")
                        Spacer()
                        TextField("0", value: $activeCalories, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .calories)
                        Text("kcal").foregroundStyle(.secondary)
                    }

                    if selectedType.tracksDistance {
                        HStack {
                            Text("Distance")
                            Spacer()
                            TextField("0", value: $distanceMeters, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($focusedField, equals: .distance)
                            Text("m").foregroundStyle(.secondary)
                        }
                    }
                }

                // Notes
                Section("Notes") {
                    TextField("Optional notes…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .notes)
                }
            }
            .navigationTitle("Add Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }

    private func save() {
        let log = ExerciseLog(
            date:             date,
            workoutType:      selectedType.rawValue,
            durationMinutes:  durationMinutes,
            activeCalories:   activeCalories,
            distanceMeters:   selectedType.tracksDistance ? distanceMeters : 0,
            notes:            notes,
            source:           "manual"
        )
        context.insert(log)
        try? context.save()
        hapticManager.workoutLogged()
        Task { await spotlightManager.index(exercise: log) }
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    ExerciseLogView()
        .modelContainer(for: ExerciseLog.self, inMemory: true)
        .environment(HealthKitManager())
}
