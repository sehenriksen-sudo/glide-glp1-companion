// NutritionView.swift
//
// Nutrition tab — day-by-day food log with macro breakdown.

import SwiftUI
import SwiftData
import Charts

struct NutritionView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \FoodLog.timestamp, order: .reverse) private var allFoods: [FoodLog]

    @State private var selectedDate = Date.now
    @State private var showAddSheet = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    datePicker
                    if dayFoods.isEmpty {
                        emptyState
                    } else {
                        dailySummaryCard
                        macroBreakdownCard
                        foodListCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Nutrition")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddSheet) { AddFoodSheet() }
        }
    }

    // MARK: Date picker strip

    private var datePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(-6...0, id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: offset, to: startOfToday)!
                    let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    let hasData    = !foods(for: date).isEmpty

                    Button { selectedDate = date } label: {
                        VStack(spacing: 4) {
                            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isSelected ? .white : .secondary)
                            Text(date.formatted(.dateTime.day()))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(isSelected ? .white : .primary)
                            Circle()
                                .fill(hasData
                                      ? (isSelected ? Color.white.opacity(0.6) : Color.orange)
                                      : Color.clear)
                                .frame(width: 5, height: 5)
                        }
                        .frame(width: 46, height: 64)
                        .background(
                            isSelected
                                ? AnyShapeStyle(LinearGradient(colors: [.orange, .red.opacity(0.8)],
                                                               startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(Color(.systemBackground)),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .shadow(color: isSelected ? Color.orange.opacity(0.3) : Color.black.opacity(0.05),
                                radius: isSelected ? 8 : 3, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: Daily summary card

    private var dailySummaryCard: some View {
        let cal  = dayFoods.reduce(0) { $0 + $1.calories }
        let prot = dayFoods.reduce(0) { $0 + $1.protein }
        let carb = dayFoods.reduce(0) { $0 + $1.carbs }
        let fat  = dayFoods.reduce(0) { $0 + $1.fat }

        return VStack(spacing: 14) {
            // Calorie ring
            HStack(spacing: 20) {
                ZStack {
                    MacroDonut(protein: prot, carbs: carb, fat: fat, size: 90)
                    VStack(spacing: 1) {
                        Text("\(cal)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("kcal")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    macroRow(label: "Protein", grams: prot, color: .blue,   dailyGoal: 150)
                    macroRow(label: "Carbs",   grams: carb, color: .orange, dailyGoal: 200)
                    macroRow(label: "Fat",     grams: fat,  color: .yellow, dailyGoal: 65)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .dashCard(title: "Daily Summary", icon: "chart.pie.fill", color: .orange) {
            showAddSheet = true
        }
    }

    // MARK: Macro progress rows

    private func macroRow(label: String, grams: Int, color: Color, dailyGoal: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(grams) / \(dailyGoal)g")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(1.0, Double(grams) / Double(dailyGoal)))
                .tint(color)
        }
    }

    // MARK: 7-day macro bar chart

    private var macroBreakdownCard: some View {
        let days: [(date: Date, cal: Int)] = (-6...0).compactMap { offset in
            let d = Calendar.current.date(byAdding: .day, value: offset, to: startOfToday)!
            let c = foods(for: d).reduce(0) { $0 + $1.calories }
            return (date: d, cal: c)
        }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Calories this week")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Chart(days, id: \.date) { entry in
                BarMark(
                    x: .value("Day", entry.date, unit: .day),
                    y: .value("Calories", entry.cal)
                )
                .foregroundStyle(
                    Calendar.current.isDate(entry.date, inSameDayAs: selectedDate)
                        ? Color.orange
                        : Color.orange.opacity(0.3)
                )
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { val in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 9))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { val in
                    AxisValueLabel()
                        .font(.system(size: 9))
                }
            }
            .frame(height: 120)
        }
        .padding(16)
        .background(Color(.systemBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }

    // MARK: Food list card

    private var foodListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Meals")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ForEach(Array(dayFoods.enumerated()), id: \.element.id) { index, food in
                FoodLogRow(food: food)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            context.delete(food)
                            try? context.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                if index < dayFoods.count - 1 {
                    Divider().padding(.leading, 66)
                }
            }
            .padding(.bottom, 8)
        }
        .background(Color(.systemBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 52))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.orange)
            Text("No meals logged")
                .font(.title3.weight(.semibold))
            Text(Calendar.current.isDateInToday(selectedDate)
                 ? "Tap + to log your first meal today."
                 : "Nothing was logged on this day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if Calendar.current.isDateInToday(selectedDate) {
                Button("Log Meal") { showAddSheet = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding(40)
    }

    // MARK: Helpers

    private var startOfToday: Date {
        Calendar.current.startOfDay(for: .now)
    }

    private var dayFoods: [FoodLog] {
        foods(for: selectedDate)
    }

    private func foods(for date: Date) -> [FoodLog] {
        allFoods.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: date) }
    }
}

// MARK: - Food Log Row

private struct FoodLogRow: View {
    let food: FoodLog

    var body: some View {
        HStack(spacing: 12) {
            // Protein percentage ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 3)
                    .frame(width: 38, height: 38)
                Circle()
                    .trim(from: 0, to: min(1, food.proteinCaloriePercent / 100))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 38, height: 38)
                Text("\(Int(food.proteinCaloriePercent))%")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.blue)
            }
            .padding(.leading, 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(food.mealName)
                    .font(.system(size: 14, weight: .medium))
                HStack(spacing: 8) {
                    Text("P \(food.protein)g").foregroundStyle(.blue)
                    Text("C \(food.carbs)g").foregroundStyle(.orange)
                    Text("F \(food.fat)g").foregroundStyle(.yellow)
                }
                .font(.system(size: 11))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(food.calories)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("kcal")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 14)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Macro donut (full ring, no stroke gap)

private struct MacroDonut: View {
    let protein: Int
    let carbs:   Int
    let fat:     Int
    let size:    CGFloat

    private var total: Double { Double(protein + carbs + fat) }
    private var pFrac: Double { total > 0 ? Double(protein) / total : 0 }
    private var cFrac: Double { total > 0 ? Double(carbs)   / total : 0 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.10), lineWidth: 11)
            if total > 0 {
                Circle()
                    .trim(from: 0, to: pFrac)
                    .stroke(Color.blue,   style: StrokeStyle(lineWidth: 11, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: pFrac, to: pFrac + cFrac)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 11, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: pFrac + cFrac, to: 1.0)
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 11, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - DashCard modifier (shared style)

private extension View {
    func dashCard(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                Spacer()
                Button(action: action) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(color)
                }
            }
            self
        }
        .padding(16)
        .background(Color(.systemBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }
}

// MARK: - Add Food Sheet

struct AddFoodSheet: View {
    @Environment(\.modelContext)        private var context
    @Environment(\.dismiss)             private var dismiss
    @Environment(HapticManager.self)    private var hapticManager
    @Environment(SpotlightManager.self) private var spotlightManager
    @State private var name     = ""
    @State private var calories = ""
    @State private var protein  = ""
    @State private var carbs    = ""
    @State private var fat      = ""
    @FocusState private var focus: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("Meal name", text: $name).focused($focus, equals: "name")
                }
                Section("Macros") {
                    macroRow("Calories", text: $calories, unit: "kcal", field: "cal")
                    macroRow("Protein",  text: $protein,  unit: "g",    field: "prot")
                    macroRow("Carbs",    text: $carbs,    unit: "g",    field: "carb")
                    macroRow("Fat",      text: $fat,      unit: "g",    field: "fat")
                }
            }
            .navigationTitle("Log Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let log = FoodLog(
                            mealName: name.isEmpty ? "Meal" : name,
                            calories: Int(calories) ?? 0,
                            protein:  Int(protein)  ?? 0,
                            carbs:    Int(carbs)    ?? 0,
                            fat:      Int(fat)      ?? 0
                        )
                        context.insert(log)
                        try? context.save()
                        hapticManager.mealLogged()
                        Task { await spotlightManager.index(food: log) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
        }
    }

    private func macroRow(_ label: String, text: Binding<String>, unit: String, field: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($focus, equals: field)
                .frame(width: 70)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    NutritionView()
        .modelContainer(for: FoodLog.self, inMemory: true)
}
