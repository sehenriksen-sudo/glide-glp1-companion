// OnboardingView.swift
//
// First-launch onboarding — shown once, then never again.
// GlideApp checks @AppStorage("onboardingComplete") and presents this
// as a fullScreenCover when false.

import SwiftUI
import SwiftData

// MARK: - Step enum

private enum OnboardingStep: Int, CaseIterable {
    case welcome        // 0 — hero + value props
    case medication     // 1 — which drug + dose
    case lastShot       // 2 — injection date
    case goals          // 3 — current / target weight + cost
    case healthKit      // 4 — request HK permission
    case notifications  // 5 — request notification permission
    case paywall        // 6 — soft premium upsell
    case allSet         // 7 — confirmation + CTA
}

// MARK: - Onboarding View

struct OnboardingView: View {

    @Environment(\.modelContext)    private var context
    @Environment(HealthKitManager.self) private var hkManager

    @AppStorage("onboardingComplete") private var onboardingComplete = false

    // Navigation
    @State private var step:      OnboardingStep = .welcome
    @State private var direction: Int            = 1   // 1 = forward, -1 = back

    // Collected data
    @State private var medicationType = GLP1MedicationType.semaglutide
    @State private var dose            = 1.0
    @State private var injectionDate   = Date.now
    @State private var currentWeight   = ""
    @State private var targetWeight    = ""
    @State private var monthlyCost     = ""

    // Transient UI state
    @State private var notificationsGranted = false
    @State private var showPaywall          = false

    // MARK: Body

    var body: some View {
        ZStack {
            // Background — shifts color per step
            stepBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar
                if step != .welcome && step != .allSet {
                    progressBar
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }

                // Step content
                stepContent
                    .id(step.rawValue)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                            removal:   .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
                        )
                    )

                // Navigation controls
                if step != .welcome && step != .allSet {
                    bottomControls
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
            }
        }
        .animation(.spring(duration: 0.42, bounce: 0.2), value: step)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: Progress bar

    private var progressBar: some View {
        // Steps 1-6 map to progress (skip welcome + allSet)
        let progressSteps: [OnboardingStep] = [.medication, .lastShot, .goals, .healthKit, .notifications, .paywall]
        let total   = progressSteps.count
        let current = progressSteps.firstIndex(of: step).map { $0 + 1 } ?? total

        return HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < current ? Color.white : Color.white.opacity(0.25))
                    .frame(height: 3)
                    .animation(.spring(duration: 0.3), value: current)
            }
        }
    }

    // MARK: Bottom controls

    private var bottomControls: some View {
        HStack {
            // Back button
            if step.rawValue > OnboardingStep.medication.rawValue {
                Button {
                    go(to: OnboardingStep(rawValue: step.rawValue - 1)!, direction: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.15), in: Circle())
                }
            } else {
                Spacer().frame(width: 44)
            }

            Spacer()

            // Skip (only on optional steps)
            if step == .notifications || step == .paywall {
                Button("Skip") { advance() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: Step background gradient

    @ViewBuilder
    private var stepBackground: some View {
        switch step {
        case .welcome:
            LinearGradient(colors: [Color(hex: "1a1a2e"), Color(hex: "16213e"), Color(hex: "0f3460")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .medication, .lastShot:
            LinearGradient(colors: [Color.indigo.opacity(0.9), Color.blue.opacity(0.8)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .goals:
            LinearGradient(colors: [Color(hex: "134e5e"), Color(hex: "71b280")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .healthKit:
            LinearGradient(colors: [Color.pink.opacity(0.8), Color.red.opacity(0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .notifications:
            LinearGradient(colors: [Color(hex: "373b44"), Color(hex: "4286f4")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .paywall:
            LinearGradient(colors: [Color(hex: "0f2027"), Color(hex: "203a43"), Color(hex: "2c5364")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .allSet:
            LinearGradient(colors: [Color(hex: "11998e"), Color(hex: "38ef7d")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: Step content router

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:       WelcomeStep(onStart: advance)
        case .medication:    MedicationStep(type: $medicationType, dose: $dose, onNext: advance)
        case .lastShot:      LastShotStep(date: $injectionDate, medicationType: medicationType, onNext: advance)
        case .goals:         GoalsStep(currentWeight: $currentWeight, targetWeight: $targetWeight, monthlyCost: $monthlyCost, onNext: advance)
        case .healthKit:     HealthKitStep(hkManager: hkManager, onNext: advance)
        case .notifications: NotificationsStep(granted: $notificationsGranted, onNext: advance)
        case .paywall:       PaywallTeaser(onUpgrade: { showPaywall = true }, onSkip: advance)
        case .allSet:        AllSetStep(onFinish: finish)
        }
    }

    // MARK: Navigation

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { finish(); return }
        go(to: next, direction: 1)
    }

    private func go(to target: OnboardingStep, direction d: Int) {
        direction = d
        withAnimation { step = target }
    }

    private func finish() {
        // Persist collected data
        let cw   = Double(currentWeight.replacingOccurrences(of: ",", with: "."))  ?? 0
        let tw   = Double(targetWeight.replacingOccurrences(of: ",", with: "."))   ?? 0
        let cost = Double(monthlyCost.replacingOccurrences(of: ",", with: "."))    ?? 0

        context.insert(UserConfiguration(
            selectedMedication:    medicationType.rawValue,
            targetWeight:          tw,
            currentWeight:         cw,
            monthlyMedicationCost: cost
        ))
        context.insert(MedicationLog(
            date:           injectionDate,
            doseMg:         dose,
            medicationType: medicationType.rawValue
        ))
        // Seed the shared App Group store so the widget shows data immediately
        AppGroup.save(SharedMedicationSnapshot(
            medicationType: medicationType.rawValue,
            shotDate:       injectionDate,
            doseMg:         dose,
            halfLifeDays:   medicationType.typicalHalfLifeDays
        ))
        if cw > 0 {
            context.insert(WeightLog(date: injectionDate, weight: cw))
        }
        try? context.save()

        onboardingComplete = true
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Step 0 — Welcome

private struct WelcomeStep: View {
    let onStart: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            ZStack {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 90, height: 90)
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.white)
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)

            Spacer().frame(height: 32)

            VStack(spacing: 10) {
                Text("Glide")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Your GLP-1 companion")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)

            Spacer().frame(height: 48)

            // Feature pills
            VStack(spacing: 12) {
                featurePill(icon: "waveform.path.ecg",      text: "Track your concentration curve daily")
                featurePill(icon: "fork.knife.circle.fill", text: "Predict and manage food noise")
                featurePill(icon: "figure.run",             text: "Log workouts & sync with Apple Health")
                featurePill(icon: "scalemass.fill",         text: "Monitor progress toward your goal weight")
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 30)

            Spacer()

            // CTA
            Button(action: onStart) {
                Text("Get Started")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "1a1a2e"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            }
            .padding(.horizontal, 32)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)

            Spacer().frame(height: 48)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.3).delay(0.15)) { appeared = true }
        }
    }

    private func featurePill(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Step 1 — Medication type + dose

private struct MedicationStep: View {
    @Binding var type: GLP1MedicationType
    @Binding var dose: Double
    let onNext: () -> Void

    var body: some View {
        StepShell(
            icon: "syringe.fill",
            title: "Your Medication",
            subtitle: "Which GLP-1 are you currently taking?",
            primaryLabel: "Continue",
            onPrimary: onNext
        ) {
            // Type selector
            VStack(spacing: 10) {
                ForEach(GLP1MedicationType.allCases) { med in
                    MedicationTypeCard(med: med, isSelected: type == med) {
                        withAnimation(.spring(duration: 0.25)) { type = med }
                    }
                }
            }
            .padding(.horizontal, 24)

            // Dose picker
            VStack(alignment: .leading, spacing: 12) {
                Text("Dose")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(type.availableDoses, id: \.self) { d in
                            Button {
                                withAnimation { dose = d }
                            } label: {
                                Text("\(d.formatted()) mg")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(dose == d ? Color(hex: "16213e") : .white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        dose == d ? Color.white : Color.white.opacity(0.15),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .onChange(of: type) { dose = type.availableDoses.first ?? 1.0 }
        }
    }
}

private struct MedicationTypeCard: View {
    let med:        GLP1MedicationType
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.white : Color.white.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: "syringe.fill")
                        .foregroundStyle(isSelected ? Color.indigo : .white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(med.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(med.brandNames.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 20))
                }
            }
            .padding(16)
            .background(
                isSelected ? Color.white.opacity(0.20) : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.6) : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Step 2 — Last injection date

private struct LastShotStep: View {
    @Binding var date:             Date
    let medicationType:            GLP1MedicationType
    let onNext:                    () -> Void

    var body: some View {
        StepShell(
            icon: "calendar.badge.clock",
            title: "Last Injection",
            subtitle: "When did you last take your \(medicationType.rawValue) shot?",
            primaryLabel: "Continue",
            onPrimary: onNext
        ) {
            VStack(spacing: 16) {
                // Date picker
                DatePicker(
                    "Injection date",
                    selection: $date,
                    in: ...Date.now,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .tint(.white)
                .colorScheme(.dark)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)

                // Live preview
                let days = max(0, Date.now.timeIntervalSince(date) / 86_400)
                let med  = GLP1Medication(medicationType: medicationType, doseMg: 1.0, shotDate: date,
                                          halfLifeDays: medicationType.typicalHalfLifeDays)
                let conc = med.remainingConcentration().fraction

                HStack(spacing: 20) {
                    previewStat(value: String(format: "%.1f", days), label: "Days ago")
                    previewStat(value: "\(Int(conc * 100))%", label: "Remaining")
                    previewStat(value: conc < 0.40 ? "At risk" : "Protected", label: "Status",
                                color: conc < 0.40 ? .orange : .green)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func previewStat(value: String, label: String, color: Color = .white) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Step 3 — Goals

private struct GoalsStep: View {
    @Binding var currentWeight: String
    @Binding var targetWeight:  String
    @Binding var monthlyCost:   String
    let onNext:                 () -> Void
    @FocusState private var focus: Field?
    private enum Field { case current, target, cost }

    private var projectedWeeks: Int? {
        guard let cw = Double(currentWeight.replacingOccurrences(of: ",", with: ".")),
              let tw = Double(targetWeight.replacingOccurrences(of: ",", with: ".")),
              cw > tw else { return nil }
        return Int((cw - tw) / 0.5)
    }

    var body: some View {
        StepShell(
            icon: "target",
            title: "Your Goals",
            subtitle: "We'll use these to calculate your progress and estimated timeline.",
            primaryLabel: "Continue",
            onPrimary: onNext
        ) {
            VStack(spacing: 14) {
                inputRow(icon: "scalemass.fill",     label: "Current weight", unit: "kg",
                         text: $currentWeight, field: .current)
                inputRow(icon: "flag.checkered",     label: "Target weight",  unit: "kg",
                         text: $targetWeight,  field: .target)
                inputRow(icon: "dollarsign.circle",  label: "Monthly cost",   unit: "$",
                         text: $monthlyCost,   field: .cost)

                if let weeks = projectedWeeks {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Estimated timeline: ~\(weeks) weeks at 0.5 kg/week")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(14)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 24)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
        }
        .focused($focus, equals: nil)
    }

    private func inputRow(icon: String, label: String, unit: String,
                          text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 22)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.white)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.white)
                .frame(width: 72)
                .focused($focus, equals: field)
            Text(unit)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20, alignment: .leading)
        }
        .padding(14)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Step 4 — HealthKit

private struct HealthKitStep: View {
    let hkManager: HealthKitManager
    let onNext:    () -> Void
    @State private var requested = false

    var body: some View {
        StepShell(
            icon: "heart.fill",
            title: "Apple Health",
            subtitle: "Glide can import your workouts automatically from the Health app.",
            primaryLabel: requested ? "Continue" : "Allow Health Access",
            onPrimary: {
                if requested { onNext() }
                else {
                    Task {
                        await hkManager.requestAuthorization()
                        requested = true
                    }
                }
            }
        ) {
            VStack(spacing: 12) {
                healthPermRow(icon: "figure.run",         text: "Workouts & activity")
                healthPermRow(icon: "flame.fill",         text: "Active calories burned")
                healthPermRow(icon: "arrow.forward.circle", text: "Distance travelled")

                Spacer().frame(height: 8)

                Text("Glide only reads data — it never writes to Health.\nYou can change this in Settings › Privacy › Health.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                if requested {
                    Label("Permission granted", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.white.opacity(0.15), in: Capsule())
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func healthPermRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.pink)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Step 5 — Notifications

private struct NotificationsStep: View {
    @Binding var granted: Bool
    let onNext:           () -> Void
    @State private var requested = false

    var body: some View {
        StepShell(
            icon: "bell.badge.fill",
            title: "Stay on Track",
            subtitle: "Get reminders before your food noise window so you're always prepared.",
            primaryLabel: requested ? "Continue" : "Enable Reminders",
            onPrimary: {
                if requested { onNext() }
                else { Task { await requestNotifications() } }
            }
        ) {
            VStack(spacing: 12) {
                notifRow(icon: "syringe.fill",            text: "Weekly injection reminders")
                notifRow(icon: "fork.knife.circle.fill",  text: "Food noise zone alert")
                notifRow(icon: "scalemass.fill",          text: "Weekly weigh-in nudge")

                Spacer().frame(height: 8)

                Text("You can customise or turn off notifications at any time in Settings.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                if requested {
                    Label(
                        granted ? "Notifications enabled" : "Notifications skipped",
                        systemImage: granted ? "checkmark.circle.fill" : "bell.slash"
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.white.opacity(0.15), in: Capsule())
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        let result = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        granted   = result ?? false
        requested = true
        try? await Task.sleep(for: .milliseconds(600))
        onNext()
    }

    private func notifRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
        }
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Step 6 — Paywall teaser (soft upsell — not the full paywall)

private struct PaywallTeaser: View {
    let onUpgrade: () -> Void
    let onSkip:    () -> Void

    private let benefits: [(icon: String, text: String)] = [
        ("waveform.path.ecg",      "Full 7-day concentration curve"),
        ("fork.knife.circle.fill", "Food noise predictions & alerts"),
        ("chart.bar.fill",         "Weekly progress insights"),
        ("star.fill",              "Unlimited medication logs"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 90, height: 90)
                    Image(systemName: "star.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 8) {
                    Text("Unlock Full Access")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Try Glide Premium free for 7 days.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }

                VStack(spacing: 10) {
                    ForEach(benefits, id: \.text) { b in
                        HStack(spacing: 12) {
                            Image(systemName: b.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                            Text(b.text)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.9))
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .padding(16)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 28)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button(action: onUpgrade) {
                    Text("Start Free Trial")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(hex: "0f2027"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Button("Maybe later") { onSkip() }
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Step 7 — All set

private struct AllSetStep: View {
    let onFinish:  () -> Void
    @State private var appeared = false
    @State private var checkScale: [Bool] = Array(repeating: false, count: 4)

    private let items = [
        ("syringe.fill",            "Medication logged"),
        ("scalemass.fill",          "Goals saved"),
        ("heart.fill",              "Health access set up"),
        ("bell.fill",               "Reminders configured"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Animated checkmark
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 110, height: 110)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                        .scaleEffect(appeared ? 1 : 0.3)
                        .opacity(appeared ? 1 : 0)
                }

                VStack(spacing: 8) {
                    Text("You're all set!")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Glide is ready to track your journey.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }

                VStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        HStack(spacing: 14) {
                            Image(systemName: item.0)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                            Text(item.1)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white)
                                .scaleEffect(checkScale[i] ? 1 : 0)
                                .opacity(checkScale[i] ? 1 : 0)
                        }
                    }
                }
                .padding(16)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 28)
            }

            Spacer()

            Button(action: onFinish) {
                Text("Open Glide")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "11998e"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 52)
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.4)) { appeared = true }
            for i in items.indices {
                withAnimation(.spring(duration: 0.4).delay(0.4 + Double(i) * 0.12)) {
                    checkScale[i] = true
                }
            }
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Shared step shell

private struct StepShell<Content: View>: View {
    let icon:         String
    let title:        String
    let subtitle:     String
    let primaryLabel: String
    let onPrimary:    () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 24)

                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 28)

            // Scrollable content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    content()
                }
                .padding(.bottom, 16)
            }

            // Primary CTA
            Button(action: onPrimary) {
                Text(primaryLabel)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Color hex helper

private extension Color {
    init(hex: String) {
        let v = Int(hex, radix: 16) ?? 0
        let r = Double((v >> 16) & 0xff) / 255
        let g = Double((v >>  8) & 0xff) / 255
        let b = Double( v        & 0xff) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - UserNotifications import

import UserNotifications

// MARK: - Previews
// Each preview jumps directly to that step by starting OnboardingView with
// the step pre-set via a thin wrapper, so the private step structs stay
// encapsulated and the full background + progress bar render correctly.

/// Wrapper that forces OnboardingView to start at a specific step.
private struct OnboardingPreview: View {
    let startStep: OnboardingStep

    // Pre-filled sample data so data-dependent steps look realistic
    @State private var medicationType = GLP1MedicationType.semaglutide
    @State private var dose            = 1.0
    @State private var injectionDate   = Calendar.current.date(byAdding: .day, value: -3, to: .now)!
    @State private var currentWeight   = "95.0"
    @State private var targetWeight    = "78.0"
    @State private var monthlyCost     = "350"

    var body: some View {
        // Inject state into a forced-step variant of the flow
        _OnboardingStepPreview(
            step:           startStep,
            medicationType: $medicationType,
            dose:           $dose,
            injectionDate:  $injectionDate,
            currentWeight:  $currentWeight,
            targetWeight:   $targetWeight,
            monthlyCost:    $monthlyCost
        )
    }
}

/// Renders just the step content + background, mirroring OnboardingView's layout.
private struct _OnboardingStepPreview: View {
    let step: OnboardingStep
    @Binding var medicationType: GLP1MedicationType
    @Binding var dose:           Double
    @Binding var injectionDate:  Date
    @Binding var currentWeight:  String
    @Binding var targetWeight:   String
    @Binding var monthlyCost:    String
    @Environment(HealthKitManager.self) private var hkManager
    @State private var notificationsGranted = false

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 0) {
                if step != .welcome && step != .allSet {
                    progressBar(for: step)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }
                stepContent
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            WelcomeStep(onStart: {})
        case .medication:
            MedicationStep(type: $medicationType, dose: $dose, onNext: {})
        case .lastShot:
            LastShotStep(date: $injectionDate, medicationType: medicationType, onNext: {})
        case .goals:
            GoalsStep(currentWeight: $currentWeight, targetWeight: $targetWeight,
                      monthlyCost: $monthlyCost, onNext: {})
        case .healthKit:
            HealthKitStep(hkManager: hkManager, onNext: {})
        case .notifications:
            NotificationsStep(granted: $notificationsGranted, onNext: {})
        case .paywall:
            PaywallTeaser(onUpgrade: {}, onSkip: {})
        case .allSet:
            AllSetStep(onFinish: {})
        }
    }

    @ViewBuilder
    private var background: some View {
        switch step {
        case .welcome:
            LinearGradient(colors: [Color(hex: "1a1a2e"), Color(hex: "16213e"), Color(hex: "0f3460")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .medication, .lastShot:
            LinearGradient(colors: [Color.indigo.opacity(0.9), Color.blue.opacity(0.8)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .goals:
            LinearGradient(colors: [Color(hex: "134e5e"), Color(hex: "71b280")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .healthKit:
            LinearGradient(colors: [Color.pink.opacity(0.8), Color.red.opacity(0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .notifications:
            LinearGradient(colors: [Color(hex: "373b44"), Color(hex: "4286f4")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .paywall:
            LinearGradient(colors: [Color(hex: "0f2027"), Color(hex: "203a43"), Color(hex: "2c5364")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .allSet:
            LinearGradient(colors: [Color(hex: "11998e"), Color(hex: "38ef7d")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func progressBar(for step: OnboardingStep) -> some View {
        let progressSteps: [OnboardingStep] = [.medication, .lastShot, .goals, .healthKit, .notifications, .paywall]
        let total   = progressSteps.count
        let current = progressSteps.firstIndex(of: step).map { $0 + 1 } ?? total
        return HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < current ? Color.white : Color.white.opacity(0.25))
                    .frame(height: 3)
            }
        }
    }
}

// ── Individual step previews ──────────────────────────────────────────────

#Preview("Step 0 — Welcome") {
    OnboardingPreview(startStep: .welcome)
        .modelContainer(for: [UserConfiguration.self, MedicationLog.self, WeightLog.self], inMemory: true)
        .environment(HealthKitManager())
}

#Preview("Step 1 — Medication") {
    OnboardingPreview(startStep: .medication)
        .modelContainer(for: [UserConfiguration.self, MedicationLog.self, WeightLog.self], inMemory: true)
        .environment(HealthKitManager())
}

#Preview("Step 2 — Last Shot") {
    OnboardingPreview(startStep: .lastShot)
        .modelContainer(for: [UserConfiguration.self, MedicationLog.self, WeightLog.self], inMemory: true)
        .environment(HealthKitManager())
}

#Preview("Step 3 — Goals") {
    OnboardingPreview(startStep: .goals)
        .modelContainer(for: [UserConfiguration.self, MedicationLog.self, WeightLog.self], inMemory: true)
        .environment(HealthKitManager())
}

#Preview("Step 4 — Apple Health") {
    OnboardingPreview(startStep: .healthKit)
        .modelContainer(for: [UserConfiguration.self, MedicationLog.self, WeightLog.self], inMemory: true)
        .environment(HealthKitManager())
}

#Preview("Step 5 — Notifications") {
    OnboardingPreview(startStep: .notifications)
        .modelContainer(for: [UserConfiguration.self, MedicationLog.self, WeightLog.self], inMemory: true)
        .environment(HealthKitManager())
}

#Preview("Step 6 — Paywall Teaser") {
    OnboardingPreview(startStep: .paywall)
        .modelContainer(for: [UserConfiguration.self, MedicationLog.self, WeightLog.self], inMemory: true)
        .environment(HealthKitManager())
}

#Preview("Step 7 — All Set") {
    OnboardingPreview(startStep: .allSet)
        .modelContainer(for: [UserConfiguration.self, MedicationLog.self, WeightLog.self], inMemory: true)
        .environment(HealthKitManager())
}
