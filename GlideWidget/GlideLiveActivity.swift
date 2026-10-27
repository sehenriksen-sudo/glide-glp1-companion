// GlideLiveActivity.swift
//
// Live Activity views — add this file to the GlideWidget Extension target.
// Register in GlideWidgetBundle by adding GlideLiveActivityConfiguration().

import ActivityKit
import WidgetKit
import SwiftUI
import Charts

// MARK: - Live Activity Configuration

struct GlideLiveActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MedicationActivityAttributes.self) { context in
            // ── Lock Screen / StandBy / Notification Banner ───────────────
            LockScreenLiveActivityView(
                attributes: context.attributes,
                state:      context.state
            )
            .activityBackgroundTint(
                context.state.isInFoodNoiseZone
                    ? Color.orange.opacity(0.15)
                    : Color.blue.opacity(0.10)
            )
            .activitySystemActionForegroundColor(
                context.state.isInFoodNoiseZone ? .orange : .blue
            )

        } dynamicIsland: { context in
            DynamicIsland {
                // ── Expanded ─────────────────────────────────────────────
                DynamicIslandExpandedRegion(.leading)  { expandedLeading(context) }
                DynamicIslandExpandedRegion(.trailing) { expandedTrailing(context) }
                DynamicIslandExpandedRegion(.center)   { expandedCenter(context) }
                DynamicIslandExpandedRegion(.bottom)   { expandedBottom(context.attributes, context.state) }
            } compactLeading: {
                // ── Compact Leading — percentage ──────────────────────────
                HStack(spacing: 3) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(context.state.isInFoodNoiseZone ? .orange : .blue)
                    Text("\(context.state.concentrationPercent)%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(context.state.isInFoodNoiseZone ? .orange : .blue)
                }
                .padding(.leading, 4)

            } compactTrailing: {
                // ── Compact Trailing — status icon ────────────────────────
                Image(systemName: context.state.statusSFSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(context.state.isInFoodNoiseZone ? .orange : .green)
                    .padding(.trailing, 4)

            } minimal: {
                // ── Minimal — percentage only ─────────────────────────────
                Text("\(context.state.concentrationPercent)%")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(context.state.isInFoodNoiseZone ? .orange : .blue)
            }
            .keylineTint(context.state.isInFoodNoiseZone ? .orange : .blue)
            .contentMargins(.horizontal, 12, for: .expanded)
            .contentMargins(.vertical,   8,  for: .expanded)
        }
    }
}

// MARK: - Lock Screen View

private struct LockScreenLiveActivityView: View {
    let attributes: MedicationActivityAttributes
    let state:      MedicationActivityAttributes.ContentState

    private var accentColor: Color { state.isInFoodNoiseZone ? .orange : .blue }

    var body: some View {
        VStack(spacing: 10) {
            // ── Top row ───────────────────────────────────────────────────
            HStack(alignment: .top) {
                // App identity
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accentColor)
                    Text("Glide")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(attributes.medicationType)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Status pill
                Label(state.statusLabel, systemImage: state.statusSFSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.12), in: Capsule())
            }

            // ── Middle row — percentage + sparkline ───────────────────────
            HStack(alignment: .center, spacing: 16) {
                // Big number
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(state.concentrationPercent)%")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(accentColor)
                        .minimumScaleFactor(0.6)
                    Text("concentration")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Sparkline
                MiniActivitySparkline(attributes: attributes, state: state)
                    .frame(width: 130, height: 56)
            }

            // ── Concentration bar ──────────────────────────────────────────
            VStack(spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                            .frame(height: 7)
                        // 40% threshold tick
                        Rectangle()
                            .fill(Color.orange.opacity(0.5))
                            .frame(width: 2, height: 12)
                            .offset(x: geo.size.width * 0.40 - 1, y: -2.5)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: state.isInFoodNoiseZone
                                        ? [.orange, .red.opacity(0.7)]
                                        : [.blue, .indigo],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: max(6, geo.size.width * state.concentration), height: 7)
                    }
                }
                .frame(height: 12)

                HStack {
                    Text("0%")
                    Spacer()
                    Text("40%").foregroundStyle(.orange)
                    Spacer()
                    Text("100%")
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }

            // ── Bottom row — next event countdown ─────────────────────────
            HStack {
                Image(systemName: state.isInFoodNoiseZone ? "syringe.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(accentColor)
                Text("\(state.nextEventLabel) \(state.timeUntilNextEvent)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(attributes.doseMg.formatted() + " mg")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
    }
}

// MARK: - Dynamic Island Expanded regions

private func expandedLeading(_ context: ActivityViewContext<MedicationActivityAttributes>) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text("\(context.state.concentrationPercent)%")
            .font(.system(size: 28, weight: .black, design: .rounded))
            .foregroundStyle(context.state.isInFoodNoiseZone ? .orange : .blue)
        Text("remaining")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }
}

private func expandedTrailing(_ context: ActivityViewContext<MedicationActivityAttributes>) -> some View {
    VStack(alignment: .trailing, spacing: 2) {
        Image(systemName: context.state.statusSFSymbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(context.state.isInFoodNoiseZone ? .orange : .green)
        Text(context.state.isInFoodNoiseZone ? "At risk" : "Safe")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private func expandedCenter(_ context: ActivityViewContext<MedicationActivityAttributes>) -> some View {
    VStack(spacing: 1) {
        Text(context.attributes.medicationType)
            .font(.system(size: 12, weight: .semibold))
        Text(context.attributes.doseMg.formatted() + " mg")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }
}

private func expandedBottom(
    _ attributes: MedicationActivityAttributes,
    _ state:      MedicationActivityAttributes.ContentState
) -> some View {
    VStack(spacing: 8) {
        // Sparkline
        MiniActivitySparkline(attributes: attributes, state: state)
            .frame(height: 44)

        // Concentration bar
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 5)
                Rectangle()
                    .fill(Color.orange.opacity(0.5))
                    .frame(width: 1.5, height: 9)
                    .offset(x: geo.size.width * 0.40 - 0.75, y: -2)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: state.isInFoodNoiseZone
                                ? [.orange, .red.opacity(0.8)]
                                : [.blue, .cyan],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, geo.size.width * state.concentration), height: 5)
            }
        }
        .frame(height: 9)

        // Countdown
        HStack {
            Image(systemName: state.isInFoodNoiseZone ? "syringe.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(state.isInFoodNoiseZone ? .orange : .yellow)
            Text("\(state.nextEventLabel) \(state.timeUntilNextEvent)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Shared sparkline used in both lock screen and expanded island

private struct MiniActivitySparkline: View {
    let attributes: MedicationActivityAttributes
    let state:      MedicationActivityAttributes.ContentState

    private var points: [(day: Double, value: Double)] { attributes.sparklinePoints() }
    private var currentDay: Double {
        max(0, min(7, Date.now.timeIntervalSince(attributes.shotDate) / 86_400))
    }

    var body: some View {
        Chart {
            // Vulnerability band
            RectangleMark(xStart: .value("", 0), xEnd: .value("", 7),
                          yStart: .value("", 0), yEnd: .value("", 0.40))
                .foregroundStyle(Color.orange.opacity(0.06))

            // Area fill
            ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                AreaMark(x: .value("Day", pt.day), y: .value("Conc", pt.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: state.isInFoodNoiseZone
                                ? [.orange.opacity(0.22), .orange.opacity(0.02)]
                                : [.blue.opacity(0.22),   .blue.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }

            // Concentration line
            ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                LineMark(x: .value("Day", pt.day), y: .value("Conc", pt.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(pt.value >= 0.40 ? Color.blue : Color.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
            }

            // 40% dashed rule
            RuleMark(y: .value("", 0.40))
                .foregroundStyle(Color.orange.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // Current position
            if currentDay > 0.1 && currentDay < 6.9 {
                PointMark(
                    x: .value("Now", currentDay),
                    y: .value("Conc", state.concentration)
                )
                .symbolSize(38)
                .foregroundStyle(state.isInFoodNoiseZone ? Color.orange : Color.blue)
            }
        }
        .chartXScale(domain: 0...7)
        .chartYScale(domain: 0...1.05)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - Register in widget bundle (add to GlideWidgetBundle.body)
// Update GlideWidget.swift:
//
// @main
// struct GlideWidgetBundle: WidgetBundle {
//     var body: some Widget {
//         GlideConcentrationWidget()
//         GlideLiveActivityConfiguration()    ← add this line
//     }
// }

// MARK: - Previews

#Preview("Lock Screen — Protected", as: .content,
         using: MedicationActivityAttributes(
            medicationType: "Semaglutide",
            doseMg: 1.0,
            shotDate: Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
            halfLifeDays: 7.0
         )
) {
    GlideLiveActivityConfiguration()
} contentStates: {
    // Day 3 — 70% remaining, protected
    MedicationActivityAttributes.ContentState(
        concentration:     0.707,
        isInFoodNoiseZone: false,
        crossoverDate:     Calendar.current.date(byAdding: .day, value: 4, to: .now),
        nextDoseDate:      Calendar.current.date(byAdding: .day, value: 4, to: .now)!,
        staleDate:         Date.now.addingTimeInterval(2 * 3_600)
    )
}

#Preview("Lock Screen — Food Noise Zone", as: .content,
         using: MedicationActivityAttributes(
            medicationType: "Tirzepatide",
            doseMg: 5.0, shotDate: Calendar.current.date(byAdding: .day, value: -5, to: .now)!, halfLifeDays: 5.0
         )
) {
    GlideLiveActivityConfiguration()
} contentStates: {
    // Day 5 — 35% remaining, in zone
    MedicationActivityAttributes.ContentState(
        concentration:     0.354,
        isInFoodNoiseZone: true,
        crossoverDate:     Calendar.current.date(byAdding: .hour, value: -12, to: .now),
        nextDoseDate:      Calendar.current.date(byAdding: .day, value: 2, to: .now)!,
        staleDate:         Date.now.addingTimeInterval(2 * 3_600)
    )
}

#Preview("Dynamic Island — Protected", as: .dynamicIsland(.expanded),
         using: MedicationActivityAttributes(
            medicationType: "Semaglutide",
            doseMg: 1.0,
            shotDate: Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
            halfLifeDays: 7.0
         )
) {
    GlideLiveActivityConfiguration()
} contentStates: {
    MedicationActivityAttributes.ContentState(
        concentration:     0.707,
        isInFoodNoiseZone: false,
        crossoverDate:     Calendar.current.date(byAdding: .day, value: 2, to: .now),
        nextDoseDate:      Calendar.current.date(byAdding: .day, value: 4, to: .now)!,
        staleDate:         Date.now.addingTimeInterval(2 * 3_600)
    )
}

#Preview("Dynamic Island — Food Noise Zone", as: .dynamicIsland(.expanded),
         using: MedicationActivityAttributes(
            medicationType: "Tirzepatide",
            doseMg: 5.0,
            shotDate: Calendar.current.date(byAdding: .day, value: -5, to: .now)!,
            halfLifeDays: 5.0
         )
) {
    GlideLiveActivityConfiguration()
} contentStates: {
    MedicationActivityAttributes.ContentState(
        concentration:     0.354,
        isInFoodNoiseZone: true,
        crossoverDate:     Calendar.current.date(byAdding: .hour, value: -12, to: .now),
        nextDoseDate:      Calendar.current.date(byAdding: .day, value: 2, to: .now)!,
        staleDate:         Date.now.addingTimeInterval(2 * 3_600)
    )
}

#Preview("Dynamic Island Compact — Protected", as: .dynamicIsland(.compact),
         using: MedicationActivityAttributes(
            medicationType: "Semaglutide",
            doseMg: 1.0,
            shotDate: Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
            halfLifeDays: 7.0
         )
) {
    GlideLiveActivityConfiguration()
} contentStates: {
    MedicationActivityAttributes.ContentState(
        concentration:     0.707,
        isInFoodNoiseZone: false,
        crossoverDate:     Calendar.current.date(byAdding: .day, value: 2, to: .now),
        nextDoseDate:      Calendar.current.date(byAdding: .day, value: 4, to: .now)!,
        staleDate:         Date.now.addingTimeInterval(2 * 3_600)
    )
}

#Preview("Dynamic Island Minimal — Food Noise", as: .dynamicIsland(.minimal),
         using: MedicationActivityAttributes(
            medicationType: "Tirzepatide",
            doseMg: 5.0,
            shotDate: Calendar.current.date(byAdding: .day, value: -5, to: .now)!,
            halfLifeDays: 5.0
         )
) {
    GlideLiveActivityConfiguration()
} contentStates: {
    MedicationActivityAttributes.ContentState(
        concentration:     0.354,
        isInFoodNoiseZone: true,
        crossoverDate:     nil,
        nextDoseDate:      Calendar.current.date(byAdding: .day, value: 2, to: .now)!,
        staleDate:         Date.now.addingTimeInterval(2 * 3_600)
    )
}
