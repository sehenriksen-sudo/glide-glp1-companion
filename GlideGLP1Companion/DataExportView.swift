// DataExportView.swift
//
// Exports all health data as CSV files via ShareSheet.
// Present as a NavigationLink destination from SettingsView.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Export View

struct DataExportView: View {

    @Query(sort: \MedicationLog.date,  order: .reverse) private var medications: [MedicationLog]
    @Query(sort: \WeightLog.date,      order: .reverse) private var weights:      [WeightLog]
    @Query(sort: \FoodLog.timestamp,   order: .reverse) private var foods:        [FoodLog]
    @Query(sort: \ExerciseLog.date,    order: .reverse) private var exercises:    [ExerciseLog]

    @State private var isExporting     = false
    @State private var shareItems:     [Any] = []
    @State private var showShareSheet  = false
    @State private var exportedType:   ExportType?

    enum ExportType: String, CaseIterable, Identifiable {
        case all          = "All Data"
        case medications  = "Medication Logs"
        case weights      = "Weight Logs"
        case foods        = "Food Logs"
        case exercises    = "Exercise Logs"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all:         return "square.and.arrow.up"
            case .medications: return "syringe.fill"
            case .weights:     return "scalemass.fill"
            case .foods:       return "fork.knife"
            case .exercises:   return "figure.run"
            }
        }
        var color: Color {
            switch self {
            case .all:         return .blue
            case .medications: return .indigo
            case .weights:     return .green
            case .foods:       return .orange
            case .exercises:   return .purple
            }
        }
    }

    // MARK: Body

    var body: some View {
        List {
            headerSection
            exportSection
            aboutSection
        }
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isExporting { exportingOverlay } }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
                .ignoresSafeArea()
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 36))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
                Text("Your data stays yours")
                    .font(.headline)
                Text("All exports are generated on-device and shared only when you choose to. Nothing is uploaded to external servers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private var exportSection: some View {
        Section("Export as CSV") {
            ForEach(ExportType.allCases) { type in
                Button {
                    Task { await export(type) }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: type.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(type.color)
                            .frame(width: 32, height: 32)
                            .background(type.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.rawValue)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(recordCount(for: type))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(type.color)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("About CSV Files") {
            Label("Open in Numbers, Excel, or any spreadsheet app", systemImage: "tablecells")
            Label("Dates use ISO 8601 format (UTC)", systemImage: "calendar")
            Label("Weights are always in kilograms", systemImage: "scalemass")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var exportingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.white)
                Text("Preparing export…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: Export logic

    private func export(_ type: ExportType) async {
        isExporting = true
        defer { isExporting = false }

        var urls: [URL] = []

        switch type {
        case .all:
            if let u = csvFile(name: "glide_medications", csv: medicationsCSV()) { urls.append(u) }
            if let u = csvFile(name: "glide_weights",     csv: weightsCSV())     { urls.append(u) }
            if let u = csvFile(name: "glide_food",        csv: foodsCSV())       { urls.append(u) }
            if let u = csvFile(name: "glide_exercise",    csv: exercisesCSV())   { urls.append(u) }
        case .medications:
            if let u = csvFile(name: "glide_medications", csv: medicationsCSV()) { urls.append(u) }
        case .weights:
            if let u = csvFile(name: "glide_weights",     csv: weightsCSV())     { urls.append(u) }
        case .foods:
            if let u = csvFile(name: "glide_food",        csv: foodsCSV())       { urls.append(u) }
        case .exercises:
            if let u = csvFile(name: "glide_exercise",    csv: exercisesCSV())   { urls.append(u) }
        }

        guard !urls.isEmpty else { return }
        shareItems    = urls
        showShareSheet = true
    }

    // MARK: CSV builders

    private func medicationsCSV() -> String {
        var rows = ["date,medication_type,dose_mg,half_life_days,concentration_at_export,source"]
        for log in medications {
            let conc = log.asMedication().remainingConcentration()
            rows.append([
                iso(log.date),
                log.medicationType,
                log.doseMg.formatted(),
                log.asMedication().halfLifeDays.formatted(),
                String(format: "%.4f", conc.fraction),
                "manual"
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private func weightsCSV() -> String {
        var rows = ["date,weight_kg"]
        for log in weights {
            rows.append([iso(log.date), String(format: "%.2f", log.weight)].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private func foodsCSV() -> String {
        var rows = ["timestamp,meal_name,calories_kcal,protein_g,carbs_g,fat_g,protein_pct"]
        for log in foods {
            rows.append([
                iso(log.timestamp),
                csvEscape(log.mealName),
                "\(log.calories)",
                "\(log.protein)",
                "\(log.carbs)",
                "\(log.fat)",
                String(format: "%.1f", log.proteinCaloriePercent)
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private func exercisesCSV() -> String {
        var rows = ["date,workout_type,duration_min,active_calories,distance_m,source"]
        for log in exercises {
            rows.append([
                iso(log.date),
                csvEscape(log.workoutType),
                "\(log.durationMinutes)",
                "\(log.activeCalories)",
                String(format: "%.0f", log.distanceMeters),
                log.source
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    // MARK: Helpers

    private func csvFile(name: String, csv: String) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: .now).prefix(10)
        let filename = "\(name)_\(stamp).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func iso(_ date: Date) -> String { isoFormatter.string(from: date) }

    private func csvEscape(_ s: String) -> String {
        s.contains(",") || s.contains("\"") || s.contains("\n")
            ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
            : s
    }

    private func recordCount(for type: ExportType) -> String {
        switch type {
        case .all:         return "\(medications.count + weights.count + foods.count + exercises.count) total records"
        case .medications: return "\(medications.count) injection\(medications.count == 1 ? "" : "s")"
        case .weights:     return "\(weights.count) weight entr\(weights.count == 1 ? "y" : "ies")"
        case .foods:       return "\(foods.count) meal\(foods.count == 1 ? "" : "s")"
        case .exercises:   return "\(exercises.count) workout\(exercises.count == 1 ? "" : "s")"
        }
    }
}

// MARK: - ShareSheet wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DataExportView()
            .modelContainer(for: [
                MedicationLog.self, WeightLog.self, FoodLog.self, ExerciseLog.self
            ], inMemory: true)
    }
}
