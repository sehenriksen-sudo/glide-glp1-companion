// GlideWidget.swift
//
// WidgetKit extension — add this file to the "GlideWidget" Extension target.
//
// Xcode setup:
//   File → New → Target → Widget Extension
//   Product Name: GlideWidget
//   Include Live Activity: NO (optional, add later)
//   Include Configuration App Intent: NO
//
// Then:
//   1. Add SharedMedicationStore.swift to both the app target AND GlideWidget target.
//   2. Enable the same App Group (group.com.glide.shared) on both targets.
//   3. Delete the boilerplate files Xcode generates and use this file instead.

import WidgetKit
import SwiftUI
import Charts

// MARK: - Timeline Entry

struct MedicationEntry: TimelineEntry {
    let date:     Date
    let snapshot: SharedMedicationSnapshot?

    // Convenience accessors with safe defaults
    var concentration:   Double  { snapshot?.concentration(at: date) ?? 0 }
    var isVulnerable:    Bool    { concentration < 0.40 }
    var medName:         String  { snapshot?.medicationType ?? "—" }
    var nextDose:        Date?   { snapshot?.nextDoseDate }
    var crossoverDate:   Date?   { snapshot?.crossoverDate }

    var statusLabel: String {
        guard snapshot != nil else { return "No data" }
        return isVulnerable ? "Food Noise Zone" : "Protected"
    }

    var statusColor: Color {
        guard snapshot != nil else { return .secondary }
        if concentration < 0.40 { return .orange }
        if concentration < 0.60 { return .yellow }
        return .green
    }
}

// MARK: - Timeline Provider

struct MedicationTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> MedicationEntry {
        MedicationEntry(date: .now, snapshot: placeholderSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (MedicationEntry) -> Void) {
        let snapshot = AppGroup.loadSnapshot() ?? placeholderSnapshot
        completion(MedicationEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MedicationEntry>) -> Void) {
        guard let snapshot = AppGroup.loadSnapshot() else {
            // No injection logged yet — refresh once per hour hoping the user logs one
            let entry    = MedicationEntry(date: .now, snapshot: nil)
            let nextDate = Calendar.current.date(byAdding: .hour, value: 1, to: .now)!
            completion(Timeline(entries: [entry], policy: .after(nextDate)))
            return
        }

        var entries: [MedicationEntry] = []
        let now = Date.now

        // Emit one entry every 30 minutes for the next 6 hours
        // so the percentage and color update smoothly throughout the day
        for offset in stride(from: 0, through: 360, by: 30) {
            let entryDate = Calendar.current.date(byAdding: .minute, value: offset, to: now)!
            entries.append(MedicationEntry(date: entryDate, snapshot: snapshot))
        }

        // Also schedule a high-priority entry exactly at the crossover so
        // the widget flips from blue to orange without waiting for the next slot
        let crossover = snapshot.crossoverDate
        if crossover > now && crossover < now.addingTimeInterval(7 * 86_400) {
            entries.append(MedicationEntry(date: crossover, snapshot: snapshot))
        }

        // Reload after 6 hours regardless
        let reloadDate = Calendar.current.date(byAdding: .hour, value: 6, to: now)!
        completion(Timeline(entries: entries.sorted { $0.date < $1.date }, policy: .after(reloadDate)))
    }

    // MARK: Placeholder data

    private var placeholderSnapshot: SharedMedicationSnapshot {
        SharedMedicationSnapshot(
            medicationType: "Semaglutide",
            shotDate:       Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
            doseMg:         1.0,
            halfLifeDays:   7.0
        )
    }
}

// MARK: - Widget Configuration

struct GlideConcentrationWidget: Widget {
    let kind = "GlideConcentrationWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MedicationTimelineProvider()) { entry in
            GlideWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Concentration")
        .description("See your GLP-1 medication level and food noise status at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Entry View Router

struct GlideWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MedicationEntry

    var body: some View {
        switch family {
        case .systemSmall:  SmallWidgetView(entry: entry)
        case .systemMedium: MediumWidgetView(entry: entry)
        case .systemLarge:  LargeWidgetView(entry: entry)
        default:            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Small Widget  (2 × 2)

struct SmallWidgetView: View {
    let entry: MedicationEntry

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: entry.snapshot == nil
                    ? [Color(.systemGray5), Color(.systemGray6)]
                    : entry.isVulnerable
                        ? [Color.orange.opacity(0.85), Color.red.opacity(0.65)]
                        : [Color.blue.opacity(0.85), Color.indigo.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 6) {
                // Glide logo row
                HStack {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("GLIDE")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                }

                Spacer()

                // Big percentage
                Text("\(Int(entry.concentration * 100))%")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)

                // Status label
                Text(entry.statusLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Medication name
                Text(entry.medName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Medium Widget  (4 × 2)

struct MediumWidgetView: View {
    let entry: MedicationEntry

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: entry.isVulnerable
                    ? [Color.orange.opacity(0.88), Color.red.opacity(0.70)]
                    : [Color.blue.opacity(0.88), Color.indigo.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 0) {
                // Left — stats
                VStack(alignment: .leading, spacing: 8) {
                    // Header
                    HStack(spacing: 5) {
                        Image(systemName: "waveform.path.ecg.rectangle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                        Text("GLIDE")
                            .font(.system(size: 9, weight: .black))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.75))
                    }

                    Spacer()

                    // Percentage
                    Text("\(Int(entry.concentration * 100))%")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    // Status pill
                    Label(entry.statusLabel, systemImage: entry.isVulnerable ? "fork.knife.circle.fill" : "checkmark.shield.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.18), in: Capsule())

                    // Next dose
                    if let next = entry.nextDose {
                        Text("Next dose \(next.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right — sparkline
                if let snapshot = entry.snapshot {
                    SparklineChart(snapshot: snapshot, currentDate: entry.date)
                        .frame(width: 130)
                        .padding(.vertical, 12)
                        .padding(.trailing, 12)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Large Widget  (4 × 4)

struct LargeWidgetView: View {
    let entry: MedicationEntry

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background
            LinearGradient(
                colors: entry.isVulnerable
                    ? [Color(red: 0.18, green: 0.08, blue: 0.02), Color.orange.opacity(0.5)]
                    : [Color(red: 0.06, green: 0.08, blue: 0.22), Color.blue.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                // ── Header ────────────────────────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: "waveform.path.ecg.rectangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("GLIDE")
                                .font(.system(size: 9, weight: .black))
                                .tracking(1.5)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Text("Concentration")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    // Current percentage badge
                    VStack(spacing: 1) {
                        Text("\(Int(entry.concentration * 100))%")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("remaining")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // ── Sparkline ─────────────────────────────────────────────
                if let snapshot = entry.snapshot {
                    SparklineChart(snapshot: snapshot, currentDate: entry.date)
                        .frame(height: 110)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                } else {
                    Spacer().frame(height: 130)
                }

                // ── Concentration bar ──────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12)).frame(height: 8)
                            // 40% threshold tick
                            Rectangle()
                                .fill(.white.opacity(0.4))
                                .frame(width: 2, height: 14)
                                .offset(x: geo.size.width * 0.40 - 1, y: -3)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: entry.isVulnerable ? [.orange, .red] : [.blue, .cyan],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * entry.concentration, height: 8)
                        }
                    }
                    .frame(height: 14)

                    HStack {
                        Text("0%").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                        Spacer()
                        Text("40% threshold").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text("100%").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 16)

                Spacer()

                // ── Stats strip ───────────────────────────────────────────
                HStack(spacing: 0) {
                    largeStat(
                        icon: entry.isVulnerable ? "fork.knife.circle.fill" : "checkmark.shield.fill",
                        label: "Status",
                        value: entry.isVulnerable ? "Risk" : "Protected",
                        color: entry.statusColor
                    )
                    Divider().background(.white.opacity(0.2)).frame(height: 32)
                    largeStat(
                        icon: "syringe.fill",
                        label: "Medication",
                        value: entry.medName,
                        color: .white
                    )
                    Divider().background(.white.opacity(0.2)).frame(height: 32)
                    largeStat(
                        icon: "calendar.badge.clock",
                        label: "Next dose",
                        value: entry.nextDose.map {
                            $0.formatted(.relative(presentation: .named))
                        } ?? "—",
                        color: .white
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func largeStat(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color.opacity(0.8))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Shared sparkline chart

private struct SparklineChart: View {
    let snapshot:    SharedMedicationSnapshot
    let currentDate: Date

    private var points: [(day: Double, value: Double)] { snapshot.sparklinePoints() }
    private var currentDay: Double {
        max(0, min(7, currentDate.timeIntervalSince(snapshot.shotDate) / 86_400))
    }
    private var currentConc: Double { snapshot.concentration(at: currentDate) }

    var body: some View {
        Chart {
            // Vulnerability background band
            RectangleMark(
                xStart: .value("", 0),   xEnd: .value("", 7),
                yStart: .value("", 0.0), yEnd: .value("", 0.40)
            )
            .foregroundStyle(Color.orange.opacity(0.08))

            // Area fill
            ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                AreaMark(x: .value("Day", pt.day), y: .value("Conc", pt.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .white.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }

            // Concentration line — colour changes at threshold
            let threshold = 0.40
            ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                LineMark(x: .value("Day", pt.day), y: .value("Conc", pt.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(pt.value >= threshold ? Color.white.opacity(0.9) : Color.orange.opacity(0.9))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }

            // 40% threshold dashed rule
            RuleMark(y: .value("", threshold))
                .foregroundStyle(.white.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // Current position dot
            if currentDay > 0.1 && currentDay < 6.9 {
                PointMark(x: .value("Now", currentDay), y: .value("Conc", currentConc))
                    .symbolSize(45)
                    .foregroundStyle(currentConc < threshold ? Color.orange : Color.white)
            }
        }
        .chartXScale(domain: 0...7)
        .chartYScale(domain: 0...1.05)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - Widget Bundle

@main
struct GlideWidgetBundle: WidgetBundle {
    var body: some Widget {
        GlideConcentrationWidget()
        GlideLiveActivityConfiguration()
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    GlideConcentrationWidget()
} timeline: {
    MedicationEntry(
        date: .now,
        snapshot: SharedMedicationSnapshot(
            medicationType: "Semaglutide",
            shotDate: Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
            doseMg: 1.0, halfLifeDays: 7.0
        )
    )
    MedicationEntry(
        date: .now,
        snapshot: SharedMedicationSnapshot(
            medicationType: "Tirzepatide",
            shotDate: Calendar.current.date(byAdding: .day, value: -5, to: .now)!,
            doseMg: 5.0, halfLifeDays: 5.0
        )
    )
}

#Preview("Medium", as: .systemMedium) {
    GlideConcentrationWidget()
} timeline: {
    MedicationEntry(
        date: .now,
        snapshot: SharedMedicationSnapshot(
            medicationType: "Semaglutide",
            shotDate: Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
            doseMg: 1.0, halfLifeDays: 7.0
        )
    )
    MedicationEntry(
        date: .now,
        snapshot: SharedMedicationSnapshot(
            medicationType: "Tirzepatide",
            shotDate: Calendar.current.date(byAdding: .day, value: -5, to: .now)!,
            doseMg: 5.0, halfLifeDays: 5.0
        )
    )
}

#Preview("Large", as: .systemLarge) {
    GlideConcentrationWidget()
} timeline: {
    MedicationEntry(
        date: .now,
        snapshot: SharedMedicationSnapshot(
            medicationType: "Semaglutide",
            shotDate: Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
            doseMg: 1.0, halfLifeDays: 7.0
        )
    )
    MedicationEntry(
        date: .now,
        snapshot: SharedMedicationSnapshot(
            medicationType: "Tirzepatide",
            shotDate: Calendar.current.date(byAdding: .day, value: -5, to: .now)!,
            doseMg: 5.0, halfLifeDays: 5.0
        )
    )
}

#Preview("Small — Food Noise Zone", as: .systemSmall) {
    GlideConcentrationWidget()
} timeline: {
    MedicationEntry(
        date: .now,
        snapshot: SharedMedicationSnapshot(
            medicationType: "Tirzepatide",
            shotDate: Calendar.current.date(byAdding: .day, value: -5, to: .now)!,
            doseMg: 5.0, halfLifeDays: 5.0
        )
    )
}

#Preview("Medium — No Data", as: .systemMedium) {
    GlideConcentrationWidget()
} timeline: {
    MedicationEntry(date: .now, snapshot: nil)
}
