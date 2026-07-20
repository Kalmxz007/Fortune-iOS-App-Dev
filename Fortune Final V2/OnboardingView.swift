//
//  OnboardingView.swift
//  Fortune
//
//  Nine step onboarding: welcome, name, experience, goal, frequency,
//

import SwiftUI

struct OnboardingView: View {
    let onComplete: (OnboardingData) -> Void

    @State private var step = 0
    @State private var forward = true
    @State private var data = OnboardingData()

    private let totalPersonalSteps = 7  // steps 1–7

    // MARK: Option data

    private let experiences: [(id: String, label: String, desc: String, icon: String, tip: String)] = [
        ("beginner", "Beginner", "Just getting started — I'm here to learn", "🌱", "We'll guide you step by step"),
        ("intermediate", "Intermediate", "I know the basics and want to sharpen my edge", "📈", "Personalized tips for your level"),
        ("pro", "Pro Trader", "Years of experience — here for the simulation", "⚡", "Advanced data & full control"),
    ]
    private let goals: [(id: String, label: String, desc: String, icon: String)] = [
        ("learn", "Learn Markets", "Understand how stocks & trading work", "📚"),
        ("grow", "Grow Wealth", "Build long-term portfolio habits", "💰"),
        ("beat", "Beat the Market", "Compete and climb the leaderboard", "🏆"),
        ("fun", "Just for Fun", "Experiment with zero risk", "🎯"),
    ]
    private let frequencies: [(id: String, label: String, desc: String, icon: String)] = [
        ("active", "Active Trader", "I check markets daily and trade often", "⚡"),
        ("swing", "Swing Trader", "I hold positions for days or weeks", "📊"),
        ("casual", "Long-term Holder", "I invest and let positions breathe for months", "🌿"),
    ]
    private let capitals: [(id: String, label: String, desc: String, hex: UInt)] = [
        ("1k", "$1,000", "Starting small, learning the ropes", 0x4ADE80),
        ("10k", "$10,000", "A balanced, realistic starting pot", 0x38D4FF),
        ("100k", "$100,000", "Simulate serious portfolio moves", 0x6D74FF),
        ("1m", "$1,000,000", "Go full whale mode 🐳", 0xB06AFF),
    ]
    private let risks: [(id: String, label: String, desc: String, icon: String, hex: UInt)] = [
        ("conservative", "Conservative", "Capital preservation first. Slow & steady.", "🛡️", 0x4ADE80),
        ("balanced", "Balanced", "Mix of growth and safety. Best of both.", "⚖️", 0x6D74FF),
        ("aggressive", "Aggressive", "Max returns. High volatility accepted.", "🔥", 0xF87171),
    ]
    private let sectorList = ["Tech", "AI & ML", "Finance", "Energy", "Healthcare", "Consumer", "EV & Auto", "Crypto", "Biotech", "Defense", "Real Estate", "Media"]

    private var progress: Double {
        step <= 1 ? 0 : Double(step - 1) / Double(totalPersonalSteps)
    }
    private var stepLabel: String {
        (step > 0 && step < 8) ? "STEP \(step) OF \(totalPersonalSteps)" : ""
    }

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x020408), location: 0),
                    .init(color: Color(hex: 0x04040F), location: 0.30),
                    .init(color: Color(hex: 0x020208), location: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if step > 0 && step < 8 { progressBar }

                ZStack {
                    stepContent
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                        ))
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Progress bar

    private var progressBar: some View {
        HStack(spacing: 12) {
            Button {
                forward = false
                withAnimation(.easeInOut(duration: 0.22)) { step -= 1 }
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
            }
            GeometryReader { geo in
                Capsule().fill(.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.brandGradient).frame(width: geo.size.width * progress)
                    }
            }
            .frame(height: 4)
            Text("\(step) / \(totalPersonalSteps)").font(.mono(10)).foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
    }

    // MARK: Step router

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: nameStep
        case 2: experienceStep
        case 3: goalStep
        case 4: frequencyStep
        case 5: capitalStep
        case 6: riskStep
        case 7: sectorsStep
        default: doneStep
        }
    }

    // MARK: Step 0 — Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()
            LogoView(size: 96)
            Text("FORTUNE").font(.system(size: 34, weight: .heavy)).tracking(4)
                .foregroundStyle(Theme.brandGradient).padding(.top, 8)
            VStack(spacing: 4) {
                Text("The simulated trading experience.").font(.system(size: 14)).foregroundStyle(.white.opacity(0.4))
                Text("No real money. Just real skill-building.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.25))
            }
            .padding(.top, 8).padding(.bottom, 40)

            VStack(spacing: 12) {
                gradientButton("Create Profile") { advance(to: 1) }
                Text("Mock capital only · No financial advice").font(.system(size: 11)).foregroundStyle(.white.opacity(0.22))
            }
            Spacer()
        }
    }

    // MARK: Step 1 — Name

    private var nameStep: some View {
        stepScaffold {
            stepHeader("First, what's your name?", "We'll personalise your dashboard and leaderboard profile.")
            HStack(spacing: 12) {
                Image(systemName: "person").foregroundStyle(.white.opacity(0.3))
                TextField("", text: $data.name, prompt: Text("Your name or nickname").foregroundColor(.white.opacity(0.22)))
                    .foregroundStyle(.white).font(.system(size: 16))
                    .onSubmit { if canContinueName { advance(to: 2) } }
            }
            .padding(.horizontal, 16).padding(.vertical, 16)
            .background(.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10)))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } button: {
            gradientButton("Continue →", disabled: !canContinueName) { advance(to: 2) }
        }
    }
    private var canContinueName: Bool { !data.name.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Step 2 — Experience

    private var experienceStep: some View {
        stepScaffold {
            stepHeader("What's your trading experience?", "This helps us tailor tips and challenge difficulty.")
            VStack(spacing: 10) {
                ForEach(experiences, id: \.id) { e in
                    SelectCard(selected: data.experience == e.id) { data.experience = e.id } content: {
                        HStack(spacing: 14) {
                            Text(e.icon).font(.system(size: 28))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(e.label).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                    Spacer()
                                    if data.experience == e.id {
                                        Text(e.tip).font(.system(size: 10, weight: .medium)).foregroundStyle(Color(hex: 0xA5B4FC))
                                    }
                                }
                                Text(e.desc).font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                }
            }
        } button: {
            gradientButton("Continue →", disabled: data.experience.isEmpty) { advance(to: 3) }
        }
    }

    // MARK: Step 3 — Goal

    private var goalStep: some View {
        stepScaffold {
            stepHeader("What's your primary goal?", "We'll highlight features that matter most to you.")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(goals, id: \.id) { g in
                    SelectCard(selected: data.goal == g.id) { data.goal = g.id } content: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(g.icon).font(.system(size: 24))
                            Text(g.label).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            Text(g.desc).font(.system(size: 11)).foregroundStyle(.white.opacity(0.38))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
                    }
                }
            }
        } button: {
            gradientButton("Continue →", disabled: data.goal.isEmpty) { advance(to: 4) }
        }
    }

    // MARK: Step 4 — Frequency

    private var frequencyStep: some View {
        stepScaffold {
            stepHeader("How often do you plan to trade?", "This shapes your leaderboard category and alerts.")
            VStack(spacing: 10) {
                ForEach(frequencies, id: \.id) { f in
                    SelectCard(selected: data.frequency == f.id) { data.frequency = f.id } content: {
                        HStack(spacing: 14) {
                            Text(f.icon).font(.system(size: 26))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.label).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                Text(f.desc).font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                }
            }
        } button: {
            gradientButton("Continue →", disabled: data.frequency.isEmpty) { advance(to: 5) }
        }
    }

    // MARK: Step 5 — Capital

    private var capitalStep: some View {
        stepScaffold {
            stepHeader("Choose your starting mock capital", "This is simulated money — pick whatever you want to practice with.")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(capitals, id: \.id) { c in
                    let on = data.capital == c.id
                    let color = Color(hex: c.hex)
                    Button { data.capital = c.id } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.label).font(.mono(18, weight: .heavy)).foregroundStyle(on ? color : .white.opacity(0.8))
                            Text(c.desc).font(.system(size: 11)).foregroundStyle(.white.opacity(0.38))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(on ? color.opacity(0.08) : .white.opacity(0.03))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(on ? color.opacity(0.5) : .white.opacity(0.08)))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: on ? color.opacity(0.12) : .clear, radius: 20, y: 4)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        } button: {
            gradientButton("Continue →", disabled: data.capital.isEmpty) { advance(to: 6) }
        }
    }

    // MARK: Step 6 — Risk

    private var riskStep: some View {
        stepScaffold {
            stepHeader("What's your risk appetite?", "Sets default stop-loss suggestions and trade alerts.")
            VStack(spacing: 10) {
                ForEach(risks, id: \.id) { r in
                    let color = Color(hex: r.hex)
                    SelectCard(selected: data.risk == r.id) { data.risk = r.id } content: {
                        HStack(spacing: 14) {
                            Text(r.icon).font(.system(size: 26))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.label).font(.system(size: 14, weight: .bold)).foregroundStyle(data.risk == r.id ? color : .white)
                                Text(r.desc).font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                            }
                            Spacer()
                            if data.risk == r.id {
                                Circle().fill(color).frame(width: 8, height: 8)
                            }
                        }
                    }
                }
            }
        } button: {
            gradientButton("Continue →", disabled: data.risk.isEmpty) { advance(to: 7) }
        }
    }

    // MARK: Step 7 — Sectors

    private var sectorsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader("Which sectors interest you?", "We'll surface relevant stocks and news. Pick as many as you like.")
                .padding(.top, 8)
            ScrollView(showsIndicators: false) {
                FlowLayout(spacing: 8) {
                    ForEach(sectorList, id: \.self) { sector in
                        let on = data.sectors.contains(sector)
                        Button { toggleSector(sector) } label: {
                            Text("\(on ? "✓ " : "")\(sector)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(on ? Color(hex: 0xA5B4FC) : .white.opacity(0.45))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(on ? Theme.indigo.opacity(0.2) : .white.opacity(0.04))
                                .overlay(Capsule().stroke(on ? Theme.indigo.opacity(0.55) : .white.opacity(0.1)))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            gradientButton(data.sectors.isEmpty ? "Skip →" : "Continue with \(data.sectors.count) selected →") {
                advance(to: 8)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: Step 8 — Done

    private var doneStep: some View {
        let archetype = getArchetype()
        let capital = capitals.first { $0.id == data.capital }
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Text("🎉").font(.system(size: 48)).padding(.bottom, 12)
                VStack(spacing: 2) {
                    Text("You're all set,").font(.system(size: 24, weight: .heavy)).foregroundStyle(.white)
                    Text(data.name.isEmpty ? "Trader" : data.name)
                        .font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.brandGradient)
                }
                .padding(.bottom, 12)
                HStack(spacing: 8) {
                    Text(archetype.icon).font(.system(size: 16))
                    Text(archetype.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.white.opacity(0.05)).overlay(Capsule().stroke(.white.opacity(0.12))).clipShape(Capsule())
                .padding(.bottom, 20)

                // Summary card
                VStack(spacing: 10) {
                    summaryRow("Experience", experiences.first { $0.id == data.experience }?.label ?? "")
                    summaryRow("Goal", goals.first { $0.id == data.goal }?.label ?? "")
                    summaryRow("Style", frequencies.first { $0.id == data.frequency }?.label ?? "")
                    summaryRow("Risk", risks.first { $0.id == data.risk }?.label ?? "")
                    Divider().overlay(.white.opacity(0.08))
                    HStack {
                        Text("Starting Capital").font(.mono(11)).foregroundStyle(.white.opacity(0.35))
                        Spacer()
                        Text(capital?.label ?? "").font(.mono(13, weight: .heavy))
                            .foregroundStyle(Color(hex: capital?.hex ?? 0x6D74FF))
                    }
                }
                .padding(16)
                .background(.white.opacity(0.04)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.bottom, 16)

                if !data.sectors.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(data.sectors, id: \.self) { s in
                            Text(s).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(.white.opacity(0.04)).overlay(Capsule().stroke(.white.opacity(0.1))).clipShape(Capsule())
                        }
                    }
                    .padding(.bottom, 20)
                }

                gradientButton("Enter Fortune →") { finish() }
            }
            .padding(.vertical, 24)
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.mono(11)).foregroundStyle(.white.opacity(0.35))
            Spacer()
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: Archetype

    private func getArchetype() -> (label: String, icon: String) {
        let exp = data.experience, risk = data.risk, freq = data.frequency
        if exp == "pro" && risk == "aggressive" { return ("Power Trader", "⚡") }
        if exp == "pro" && risk == "balanced" { return ("Precision Trader", "🎯") }
        if exp == "pro" { return ("Strategic Pro", "💎") }
        if exp == "intermediate" && freq == "active" { return ("Swing Trader", "📈") }
        if exp == "intermediate" { return ("Strategic Investor", "🧠") }
        if risk == "aggressive" { return ("Bold Explorer", "🚀") }
        if freq == "active" { return ("Eager Learner", "⚡") }
        return ("Rising Trader", "🌟")
    }

    // MARK: Helpers

    private func advance(to next: Int) {
        forward = true
        withAnimation(.easeInOut(duration: 0.22)) { step = next }
    }

    private func toggleSector(_ s: String) {
        if let i = data.sectors.firstIndex(of: s) { data.sectors.remove(at: i) }
        else { data.sectors.append(s) }
    }

    private func finish() {
        onComplete(data)
    }

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !stepLabel.isEmpty {
                Text(stepLabel).font(.mono(11)).tracking(1.5).foregroundStyle(.white.opacity(0.35))
            }
            Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Standard vertically-centred step with content + a pinned bottom button.
    private func stepScaffold<Content: View, Footer: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder button: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            content()
            Spacer()
            button()
        }
    }

    private func gradientButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Theme.brandGradient).clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(disabled).opacity(disabled ? 0.25 : 1)
    }
}

// MARK: - Select card

private struct SelectCard<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Theme.indigo.opacity(0.13) : .white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Theme.indigo.opacity(0.55) : .white.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: selected ? Theme.indigo.opacity(0.12) : .clear, radius: 24, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

#Preview {
    OnboardingView { _ in }
}
