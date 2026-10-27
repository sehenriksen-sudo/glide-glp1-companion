// DashboardView.swift
//
// Home screen — ties medication, weight, nutrition, and exercise together.
// Requires in the environment:
//   .modelContainer(container)
//   .environment(subscriptionManager)
//   .environment(healthKitManager)

import SwiftUI
import SwiftData
import Charts

// MARK: - Dashboard

struct DashboardView: View {

    @Environment(SubscriptionManager.self) private var store
    @Environment(HealthKitManager.self)    private var hkManager
    @Environment(\.modelContext)           private var context

    // SwiftData queries — sorted so .first gives the most recent record
    @Query(sort: \MedicationLog.date,  order: .reverse) private var medications:  [MedicationLog]
    @Query(sort: \WeightLog.date,      order: .reverse) private var weights:       [WeightLog]
    @Query(sort: \FoodLog.timestamp,   order: .reverse) private var foods:         [FoodLog]
    @Query(sort: \ExerciseLog.date,    order: .reverse) private var exercises:     [ExerciseLog]
    @Query                                              private var configs:        [UserConfiguration]

    @State private var showPaywall       = false
    @State private var showAddWeight     = false
    @State private var showAddFood       = false
    @State private var showAddExercise   = false
    @State private var showAddMedication = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    medicationCard
                    weightCard
                    todayNutritionCard
                    exerciseCard
                    quickActionsCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showPaywall)       { PaywallView() }
        .sheet(isPresented: $showAddWeight)     { AddWeightSheet() }
        .sheet(isPresented: $showAddFood)       { AddFoodSheet() }
        .sheet(isPresented: $showAddExercise)   { AddExerciseSheet() }
        .sheet(isPresented: $showAddMedication) { AddMedicationSheet() }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Glide")
                .font(.system(size: 20, weight: .bold, design: .rounded))
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !store.isPremium {
                Button {
                    showPaywall = true
                } label: {
                    Label("Upgrade", systemImage: "star.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            LinearGradient(colors: [.blue, .indigo],
                                           startPoint: .leading, endPoint: .trailing),
                            in: Capsule()
                        )
                }
                .labelStyle(.titleAndIcon)
            }
        }
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(greeting)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(Date.now.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        switch h {
        case 0..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var statusBadge: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(medicationStatusColor)
                .frame(width: 10, height: 10)
            Text(medicationStatusLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(medicationStatusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(medicationStatusColor.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Medication Card

    private var medicationCard: some View {
        DashCard(title: "Medication", icon: "syringe.fill", iconColor: .blue,
                 action: { showAddMedication = true }, actionLabel: "Log Shot") {
            if let log = medications.first {
                let med = log.asMedication()
                let conc = med.remainingConcentration()
                let isVulnerable = conc.fraction < 0.40

                VStack(spacing: 14) {
                    // Concentration bar
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(log.medicationType)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(conc.percentageString)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(isVulnerable ? .orange : .blue)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.12))
                                    .frame(height: 10)
                                Capsule()
                                    .fill(isVulnerable
                                          ? AnyShapeStyle(LinearGradient(colors: [.orange, .red.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                                          : AnyShapeStyle(LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing)))
                                    .frame(width: geo.size.width * conc.fraction, height: 10)
                                    .animation(.spring(duration: 0.6), value: conc.fraction)
                                // 40% threshold tick
                                Rectangle()
                                    .fill(Color.orange.opacity(0.6))
                                    .frame(width: 2, height: 16)
                                    .offset(x: geo.size.width * 0.40 - 1, y: -3)
                            }
                        }
                        .frame(height: 16)

                        HStack {
                            Label(daysSinceLabel(log.date), systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if isVulnerable {
                                Label("Food noise risk", systemImage: "fork.knife.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                            } else {
                                Label("Protected zone", systemImage: "checkmark.shield.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    // Mini sparkline — 7-day curve
                    MiniConcentrationSparkline(medication: med)
                        .frame(height: 52)
                }
            } else {
                emptyPrompt(
                    icon: "syringe",
                    message: "Log your first injection to start tracking your concentration curve.",
                    actionLabel: "Log Shot",
                    action: { showAddMedication = true }
                )
            }
        }
    }

    // MARK: Weight Card

    private var weightCard: some View {
        DashCard(title: "Weight", icon: "scalemass.fill", iconColor: .green,
                 action: { showAddWeight = true }, actionLabel: "Log") {
            if weights.isEmpty {
                emptyPrompt(icon: "scalemass",
                            message: "Add your first weight entry to track your progress.",
                            actionLabel: "Add Weight",
                            action: { showAddWeight = true })
            } else {
                let current   = weights[0].weight
                let target    = configs.first?.targetWeight ?? 0
                let previous  = weights.count > 1 ? weights[1].weight : current
                let delta     = current - previous
                let hasTarget = target > 0

                VStack(spacing: 12) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", current))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("kg")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        // Delta vs previous
                        if weights.count > 1 {
                            Label(String(format: "%+.1f kg", delta),
                                  systemImage: delta <= 0 ? "arrow.down.right" : "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(delta <= 0 ? .green : .orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background((delta <= 0 ? Color.green : Color.orange).opacity(0.1),
                                            in: Capsule())
                        }
                    }

                    // Progress to target
                    if hasTarget {
                        let start    = weights.last?.weight ?? current
                        let progress = start > target
                            ? (start - current) / (start - target)
                            : 0.0
                        let clamped  = max(0, min(1, progress))

                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Goal: \(String(format: "%.1f", target)) kg")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(clamped * 100))%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                            ProgressView(value: clamped)
                                .tint(.green)
                        }
                    }

                    // Mini weight sparkline
                    WeightSparkline(logs: Array(weights.prefix(14).reversed()))
                        .frame(height: 48)
                }
            }
        }
    }

    // MARK: Nutrition Card

    private var todayNutritionCard: some View {
        DashCard(title: "Today's Nutrition", icon: "fork.knife", iconColor: .orange,
                 action: { showAddFood = true }, actionLabel: "Log Meal") {
            let todayFoods = foods.filter { Calendar.current.isDateInToday($0.timestamp) }

            if todayFoods.isEmpty {
                emptyPrompt(icon: "fork.knife",
                            message: "No meals logged today.",
                            actionLabel: "Log Meal",
                            action: { showAddFood = true })
            } else {
                let totalCal  = todayFoods.reduce(0) { $0 + $1.calories }
                let totalProt = todayFoods.reduce(0) { $0 + $1.protein }
                let totalCarb = todayFoods.reduce(0) { $0 + $1.carbs }
                let totalFat  = todayFoods.reduce(0) { $0 + $1.fat }

                VStack(spacing: 12) {
                    // Calorie headline + macro ring
                    HStack(spacing: 16) {
                        MacroRingView(protein: totalProt, carbs: totalCarb, fat: totalFat)
                            .frame(width: 72, height: 72)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .lastTextBaseline, spacing: 4) {
                                Text("\(totalCal)")
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                Text("kcal")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 10) {
                                macroPill("P", value: totalProt, color: .blue)
                                macroPill("C", value: totalCarb, color: .orange)
                                macroPill("F", value: totalFat,  color: .yellow)
                            }
                        }

                        Spacer()
                    }

                    // Meal list
                    VStack(spacing: 4) {
                        ForEach(todayFoods.prefix(3)) { food in
                            HStack {
                                Text(food.mealName)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(food.calories) kcal")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if todayFoods.count > 3 {
                            Text("+ \(todayFoods.count - 3) more")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    // MARK: Exercise Card

    private var exerciseCard: some View {
        DashCard(title: "Exercise", icon: "figure.run", iconColor: .indigo,
                 action: { showAddExercise = true }, actionLabel: "Log") {
            let weekExercises = exercises.filter {
                $0.date >= Calendar.current.date(byAdding: .day, value: -7, to: .now)!
            }

            if exercises.isEmpty {
                emptyPrompt(icon: "figure.run",
                            message: "No workouts logged yet. Import from Health or add manually.",
                            actionLabel: "Add Workout",
                            action: { showAddExercise = true })
            } else {
                let totalMin  = weekExercises.reduce(0) { $0 + $1.durationMinutes }
                let totalKcal = weekExercises.reduce(0) { $0 + $1.activeCalories }

                VStack(spacing: 12) {
                    // Stats row
                    HStack(spacing: 0) {
                        exerciseStat(value: "\(weekExercises.count)", label: "Sessions",  icon: "checkmark.circle.fill", color: .indigo)
                        Divider().frame(height: 36)
                        exerciseStat(value: "\(totalMin)", label: "Minutes",  icon: "clock.fill", color: .blue)
                        Divider().frame(height: 36)
                        exerciseStat(value: totalKcal > 0 ? "\(totalKcal)" : "—", label: "Calories", icon: "flame.fill", color: .orange)
                    }

                    // Recent workouts
                    VStack(spacing: 6) {
                        ForEach(exercises.prefix(3)) { ex in
                            HStack(spacing: 10) {
                                Image(systemName: ex.type.systemImage)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.indigo)
                                    .frame(width: 20)
                                Text(ex.workoutType)
                                    .font(.system(size: 13))
                                Spacer()
                                Text("\(ex.durationMinutes) min")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text(ex.date, style: .relative)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Quick Actions

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Add")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                quickAction(label: "Log Shot",    icon: "syringe.fill",     color: .blue)    { showAddMedication = true }
                quickAction(label: "Log Weight",  icon: "scalemass.fill",   color: .green)   { showAddWeight = true }
                quickAction(label: "Log Meal",    icon: "fork.knife",       color: .orange)  { showAddFood = true }
                quickAction(label: "Log Workout", icon: "figure.run",       color: .indigo)  { showAddExercise = true }
            }
        }
    }

    private func quickAction(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 22)
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(color.opacity(0.5))
            }
            .padding(14)
            .background(Color(.systemBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: Derived medication state

    private var medicationStatusColor: Color {
        guard let log = medications.first else { return .secondary }
        let conc = log.asMedication().remainingConcentration()
        if conc.fraction < 0.40 { return .orange }
        if conc.fraction < 0.60 { return .yellow }
        return .green
    }

    private var medicationStatusLabel: String {
        guard let log = medications.first else { return "No data" }
        let conc = log.asMedication().remainingConcentration()
        if conc.fraction < 0.40 { return "Risk" }
        if conc.fraction < 0.60 { return "Fading" }
        return "Protected"
    }

    // MARK: Helpers

    private func daysSinceLabel(_ date: Date) -> String {
        let days = Int(Date.now.timeIntervalSince(date) / 86_400)
        switch days {
        case 0:  return "Injected today"
        case 1:  return "Injected yesterday"
        default: return "Day \(days) of 7"
        }
    }

    private func macroPill(_ label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label).fontWeight(.bold)
            Text("\(value)g")
        }
        .font(.system(size: 11))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: Capsule())
    }

    private func exerciseStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(color)
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func emptyPrompt(icon: String, message: String, actionLabel: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(actionLabel, action: action)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - DashCard

/// Reusable card shell used by every dashboard section.
private struct DashCard<Content: View>: View {
    let title:       String
    let icon:        String
    let iconColor:   Color
    let action:      () -> Void
    let actionLabel: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                Spacer()
                Button(action: action) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(iconColor)
                }
            }

            content()
        }
        .padding(16)
        .background(Color(.systemBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }
}

// MARK: - Mini Concentration Sparkline

private struct MiniConcentrationSparkline: View {
    let medication: GLP1Medication
    private let step = 0.1

    private var points: [(x: Double, y: Double)] {
        stride(from: 0.0, through: 7.0, by: step).map { day in
            let date = medication.shotDate.addingTimeInterval(day * 86_400)
            return (x: day, y: medication.remainingConcentration(at: date).fraction)
        }
    }

    var body: some View {
        Chart {
            // Vulnerability zone
            RectangleMark(xStart: .value("", 0), xEnd: .value("", 7),
                          yStart: .value("", 0), yEnd: .value("", 0.40))
                .foregroundStyle(Color.orange.opacity(0.06))

            // Area fill
            ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                AreaMark(x: .value("Day", pt.x), y: .value("Conc", pt.y))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(colors: [.blue.opacity(0.20), .blue.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom)
                    )
            }

            // Line
            ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                LineMark(x: .value("Day", pt.x), y: .value("Conc", pt.y))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(pt.y >= 0.40 ? Color.blue : Color.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }

            // Threshold rule
            RuleMark(y: .value("", 0.40))
                .foregroundStyle(Color.orange.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // Current position dot
            let currentDay = min(medication.daysSinceShot, 7.0)
            let currentConc = medication.remainingConcentration().fraction
            PointMark(x: .value("Now", currentDay), y: .value("Conc", currentConc))
                .symbolSize(50)
                .foregroundStyle(currentConc < 0.40 ? Color.orange : Color.blue)
        }
        .chartXScale(domain: 0...7)
        .chartYScale(domain: 0...1.05)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - Weight Sparkline

private struct WeightSparkline: View {
    let logs: [WeightLog]  // pass in chronological order

    var body: some View {
        Chart {
            ForEach(Array(logs.enumerated()), id: \.offset) { i, log in
                AreaMark(
                    x: .value("Index", i),
                    y: .value("Weight", log.weight)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(colors: [.green.opacity(0.25), .green.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                )
                LineMark(
                    x: .value("Index", i),
                    y: .value("Weight", log.weight)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.green)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - Macro Ring

private struct MacroRingView: View {
    let protein: Int
    let carbs:   Int
    let fat:     Int

    private var total: Double { Double(protein + carbs + fat) }

    var body: some View {
        ZStack {
            if total > 0 {
                Circle()
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 10)
                RingSegment(start: 0,               end: proteinFrac,                color: .blue)
                RingSegment(start: proteinFrac,      end: proteinFrac + carbsFrac,   color: .orange)
                RingSegment(start: proteinFrac + carbsFrac, end: 1.0,               color: .yellow)
            } else {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 10)
            }
        }
    }

    private var proteinFrac: Double { total > 0 ? Double(protein) / total : 0 }
    private var carbsFrac:   Double { total > 0 ? Double(carbs)   / total : 0 }
}

private struct RingSegment: View {
    let start: Double
    let end:   Double
    let color: Color

    var body: some View {
        Circle()
            .trim(from: start, to: max(start, end - 0.01))
            .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}

// MARK: - Stub Add Sheets (replace with real implementations)
// Weight and Food sheets are placeholders — wire up to your existing forms.

private struct AddWeightSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @State private var weight = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight (kg)") {
                    TextField("e.g. 82.5", text: $weight)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let kg = Double(weight.replacingOccurrences(of: ",", with: ".")) {
                            context.insert(WeightLog(weight: kg))
                            try? context.save()
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(Double(weight.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
        .modelContainer(for: [
            MedicationLog.self, WeightLog.self,
            FoodLog.self, ExerciseLog.self, UserConfiguration.self,
        ], inMemory: true)
        .environment(SubscriptionManager())
        .environment(HealthKitManager())
}
