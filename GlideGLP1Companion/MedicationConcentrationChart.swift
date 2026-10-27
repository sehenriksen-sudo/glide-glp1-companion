import SwiftUI
import Charts

// MARK: - Private chart data type

private struct CurvePoint: Identifiable {
    let id = UUID()
    let day: Double
    let concentration: Double   // 0.0 – 1.0
}

// MARK: - Main View

struct MedicationConcentrationChart: View {

    let medication: GLP1Medication

    // ── Configuration ────────────────────────────────────────────────────────
    private let vulnerabilityThreshold = 0.40
    private let totalDays              = 7.0
    private let sampleStep             = 0.05   // every ~72 minutes

    // ── Derived data ─────────────────────────────────────────────────────────

    /// Full curve sampled at `sampleStep` resolution.
    private var allPoints: [CurvePoint] {
        stride(from: 0.0, through: totalDays, by: sampleStep).map { day in
            CurvePoint(day: day, concentration: concentrationValue(at: day))
        }
    }

    /// Points at or above threshold, with the crossover point appended so the
    /// blue and orange line segments meet precisely at the 40 % crossing.
    private var safePoints: [CurvePoint] {
        var pts = allPoints.filter { $0.concentration >= vulnerabilityThreshold }
        if let cd = crossoverDay {
            pts.append(CurvePoint(day: cd, concentration: vulnerabilityThreshold))
        }
        return pts.sorted { $0.day < $1.day }
    }

    /// Points below threshold, with the crossover point prepended.
    private var vulnerablePoints: [CurvePoint] {
        var pts = allPoints.filter { $0.concentration < vulnerabilityThreshold }
        if let cd = crossoverDay {
            pts.insert(CurvePoint(day: cd, concentration: vulnerabilityThreshold), at: 0)
        }
        return pts
    }

    /// Exact fractional day when concentration first crosses the threshold.
    /// nil if the curve stays above 40 % for the full 7-day window.
    private var crossoverDay: Double? {
        let t = medication.halfLifeDays * log2(1.0 / vulnerabilityThreshold)
        return t <= totalDays ? t : nil
    }

    private var currentDay: Double      { min(medication.daysSinceShot, totalDays) }
    private var currentConc: Double     { concentrationValue(at: currentDay) }
    private var isVulnerable: Bool      { currentConc < vulnerabilityThreshold }
    private var showNowMarker: Bool     { currentDay > 0.15 && currentDay < totalDays - 0.15 }

    private func concentrationValue(at day: Double) -> Double {
        let date = medication.shotDate.addingTimeInterval(day * 86_400)
        return medication.remainingConcentration(at: date).fraction
    }

    // ── Body ─────────────────────────────────────────────────────────────────

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            headerView
            chartView
            statsView
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 6)
        }
    }

    // MARK: Header

    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Medication type label
                Label(medication.medicationType.rawValue.uppercased(),
                      systemImage: "syringe.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.0)

                Text("Weekly Concentration Curve")
                    .font(.headline)

                Text(medication.brandNamesDisplay)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Dose badge
            VStack(spacing: 2) {
                Text("\(medication.doseMg.formatted()) mg")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
                Text("initial dose")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.blue.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: Chart

    private var chartView: some View {
        Chart {

            // ── Layer 1: vulnerability zone background band ───────────────
            //    Subtle orange fill behind the area where concentration < 40 %
            if let cd = crossoverDay {
                RectangleMark(
                    xStart: .value("Crossover", cd),
                    xEnd:   .value("End", totalDays + 0.5),
                    yStart: .value("Zero", 0.0),
                    yEnd:   .value("Threshold", vulnerabilityThreshold)
                )
                .foregroundStyle(Color.orange.opacity(0.07))
            }

            // ── Layer 2: area fill under the full concentration curve ─────
            ForEach(allPoints) { pt in
                AreaMark(
                    x: .value("Day", pt.day),
                    y: .value("Concentration", pt.concentration)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: Color.blue.opacity(0.22), location: 0.0),
                            .init(color: Color.blue.opacity(0.03), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // ── Layer 3: concentration line — safe zone (blue) ────────────
            ForEach(safePoints) { pt in
                LineMark(
                    x: .value("Day", pt.day),
                    y: .value("Concentration", pt.concentration)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }

            // ── Layer 4: concentration line — vulnerable zone (orange) ────
            ForEach(vulnerablePoints) { pt in
                LineMark(
                    x: .value("Day", pt.day),
                    y: .value("Concentration", pt.concentration)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.orange)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }

            // ── Layer 5: 40 % threshold dashed rule mark ──────────────────
            RuleMark(y: .value("Threshold", vulnerabilityThreshold))
                .foregroundStyle(Color.orange.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .annotation(position: .top, alignment: .leading, spacing: 3) {
                    Text("40 % threshold")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1),
                                    in: Capsule())
                }

            // ── Layer 6: "Next dose" vertical marker at day 7 ────────────
            RuleMark(x: .value("NextDose", totalDays))
                .foregroundStyle(Color.secondary.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .center, spacing: 4) {
                    Text("Next dose")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

            // ── Layer 7: current day position ────────────────────────────
            if showNowMarker {
                // Vertical rule
                RuleMark(x: .value("Today", currentDay))
                    .foregroundStyle(
                        (isVulnerable ? Color.orange : Color.blue).opacity(0.30)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                // Dot with callout
                PointMark(
                    x: .value("Day", currentDay),
                    y: .value("Concentration", currentConc)
                )
                .symbolSize(70)
                .foregroundStyle(isVulnerable ? Color.orange : Color.blue)
                .annotation(
                    position: currentConc > 0.58 ? .bottom : .top,
                    alignment: .center,
                    spacing: 7
                ) {
                    nowCallout
                }
            }

            // ── Layer 8: food noise zone label (anchored via invisible point)
            if let cd = crossoverDay {
                PointMark(
                    x: .value("LabelAnchorX", (cd + totalDays) * 0.5),
                    y: .value("LabelAnchorY", vulnerabilityThreshold * 0.44)
                )
                .opacity(0)
                .annotation(position: .overlay, alignment: .center) {
                    foodNoiseOverlay
                }
            }
        }
        .chartXScale(domain: 0...(totalDays + 0.4))
        .chartYScale(domain: 0...1.06)
        .chartXAxis {
            AxisMarks(values: Array(0...7).map(Double.init)) { axisValue in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel {
                    if let d = axisValue.as(Double.self) {
                        Text(d == 0 ? "Shot" : "Day \(Int(d))")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [0.0, 0.25, 0.40, 0.50, 0.75, 1.0]) { axisValue in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel {
                    if let v = axisValue.as(Double.self) {
                        let isThreshold = v == vulnerabilityThreshold
                        Text(isThreshold ? "40 %" : "\(Int(v * 100)) %")
                            .font(.system(size: 9,
                                          weight: isThreshold ? .semibold : .regular))
                            .foregroundStyle(isThreshold ? Color.orange : Color.secondary)
                    }
                }
            }
        }
        .frame(height: 240)
    }

    // MARK: Chart sub-views

    /// Floating callout for the current-position dot.
    private var nowCallout: some View {
        VStack(spacing: 1) {
            Text("NOW")
                .font(.system(size: 7, weight: .black))
                .tracking(0.5)
            Text("\(Int(currentConc * 100)) %")
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(isVulnerable ? Color.orange : Color.blue)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.95))
                .shadow(color: .black.opacity(0.09), radius: 5, y: 2)
        }
    }

    /// Badge placed inside the food noise vulnerability zone.
    private var foodNoiseOverlay: some View {
        VStack(spacing: 3) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.orange)

            Text("Food Noise")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.orange)

            Text("Vulnerability Zone")
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Color.orange.opacity(0.75))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.11))
                .strokeBorder(Color.orange.opacity(0.28), lineWidth: 0.5)
        }
    }

    // MARK: Stats strip

    private var statsView: some View {
        HStack(spacing: 10) {
            statPill(
                icon:  "drop.fill",
                label: "Current level",
                value: "\(Int(currentConc * 100)) %",
                color: isVulnerable ? .orange : .blue
            )
            statPill(
                icon:  "exclamationmark.triangle.fill",
                label: "Vulnerability from",
                value: crossoverDay
                    .map { String(format: "Day %.1f", $0) }
                    ?? "None this week",
                color: .orange
            )
            statPill(
                icon:  "clock.fill",
                label: "Half-life",
                value: String(format: "%.0f days", medication.halfLifeDays),
                color: Color(.systemGray)
            )
        }
    }

    private func statPill(
        icon: String, label: String, value: String, color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Previews

#Preview("Semaglutide — Day 5 (approaching zone)") {
    let shot = Calendar.current.date(byAdding: .day, value: -5, to: .now)!
    let med  = GLP1Medication(
        medicationType: .semaglutide,
        shotDate:        shot,
        doseMg:          1.0,
        halfLifeDays:    7.0     // clinical semaglutide half-life
    )
    return MedicationConcentrationChart(medication: med)
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Tirzepatide — Day 4 (in vulnerability zone)") {
    let shot = Calendar.current.date(byAdding: .day, value: -4, to: .now)!
    let med  = GLP1Medication(
        medicationType: .tirzepatide,
        shotDate:        shot,
        doseMg:          5.0,
        halfLifeDays:    5.0     // clinical tirzepatide half-life
    )
    return MedicationConcentrationChart(medication: med)
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Shot day — no vulnerability yet") {
    let med = GLP1Medication(
        medicationType: .semaglutide,
        shotDate:        .now,
        doseMg:          0.5,
        halfLifeDays:    7.0
    )
    return MedicationConcentrationChart(medication: med)
        .padding()
        .background(Color(.systemGroupedBackground))
}
