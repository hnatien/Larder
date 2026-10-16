import LarderCore
import LarderDesign
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Cooking mode: one step per screen, large Back and Next buttons, named timers, and the screen kept awake.
public struct CookingModeView: View {
    @State private var session: CookingSession
    @State private var isFlashing = false
    @AccessibilityFocusState private var focusedStep: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates cooking mode for `recipe`; `ingredients` are the lines to match against each step.
    public init(recipe: Recipe, ingredients: [Ingredient]) {
        _session = State(initialValue: CookingSession(recipe: recipe, ingredients: ingredients))
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if session.steps.isEmpty {
                Text(RecipesCopy.noSteps)
                    .font(LarderFont.body(.title2))
                    .foregroundStyle(LarderColor.ink.primary)
                    .padding(LarderSpacing.l)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                otherTimers
                pager
                controls
            }
        }
        .background(LarderColor.surface.canvas)
        .overlay {
            if isFlashing {
                LarderColor.accent.spot
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.success, trigger: session.finishCount)
        .task(id: session.finishCount) { await announceFinish() }
        .task(id: session.stepIndex) {
            try? await Task.sleep(for: .milliseconds(250))
            focusedStep = session.stepIndex
        }
        .accessibilityRotor(RecipesCopy.stepsRotor) {
            ForEach(session.steps.indices, id: \.self) { index in
                AccessibilityRotorEntry(RecipesCopy.stepPosition(index + 1, of: session.steps.count), id: index) {
                    session.go(to: index)
                }
            }
        }
        .onAppear { setScreenAwake(true) }
        .onDisappear {
            setScreenAwake(false)
            session.stopTimers()
        }
    }

    private var header: some View {
        HStack {
            if !session.steps.isEmpty {
                Text(RecipesCopy.stepPosition(session.stepIndex + 1, of: session.steps.count))
                    .stamp()
                    .foregroundStyle(LarderColor.ink.secondary)
            }
            Spacer()
            Button(RecipesCopy.close) { dismiss() }
                .buttonStyle(.larderQuiet)
        }
        .padding(.horizontal, LarderSpacing.l)
        .padding(.top, LarderSpacing.s)
    }

    @ViewBuilder private var otherTimers: some View {
        let active = session.otherActiveTimers
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                ForEach(active, id: \.step) { entry in
                    OtherTimerRow(name: RecipesCopy.stepTimerName(entry.step + 1), timer: entry.timer) {
                        session.go(to: entry.step)
                    }
                }
            }
            .padding(.horizontal, LarderSpacing.l)
        }
    }

    private var pager: some View {
        #if os(iOS)
        TabView(selection: Binding(get: { session.stepIndex }, set: { session.go(to: $0) })) {
            ForEach(session.steps.indices, id: \.self) { index in
                page(index).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        page(session.stepIndex)
        #endif
    }

    private func page(_ index: Int) -> some View {
        StepPage(
            number: index + 1,
            count: session.steps.count,
            step: session.steps[index],
            summary: session.ingredientSummary(forStep: index),
            timer: session.timer(forStep: index),
            focus: $focusedStep,
            index: index
        )
    }

    private var controls: some View {
        AdaptiveStack(alignment: .center, spacing: LarderSpacing.m) { navigationButtons }
        .padding(LarderSpacing.l)
    }

    @ViewBuilder private var navigationButtons: some View {
        Button {
            session.back()
        } label: {
            Text(RecipesCopy.back)
                .font(LarderFont.body(.title3, weight: .semibold))
                .padding(.vertical, LarderSpacing.s)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.larderSecondary)
        .disabled(session.isFirst)
        Button {
            if session.isLast { dismiss() } else { session.next() }
        } label: {
            Text(session.isLast ? RecipesCopy.finish : RecipesCopy.next)
                .font(LarderFont.body(.title3, weight: .semibold))
                .padding(.vertical, LarderSpacing.s)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.larderPrimary)
    }

    private func announceFinish() async {
        guard session.finishCount > 0 else { return }
        AccessibilityNotification.Announcement(RecipesCopy.timerDone).post()
        guard !reduceMotion else { return }
        isFlashing = true
        try? await Task.sleep(for: .seconds(1))
        if !Task.isCancelled { isFlashing = false }
    }

    private func setScreenAwake(_ awake: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = awake
        #endif
    }
}

/// One step: the ingredients it names, the step text, and its timer.
private struct StepPage: View {
    let number: Int
    let count: Int
    let step: RecipeStep
    let summary: String?
    let timer: TimerModel?
    var focus: AccessibilityFocusState<Int?>.Binding
    let index: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LarderSpacing.l) {
                if let summary {
                    Text(summary)
                        .font(LarderFont.body(.subheadline))
                        .foregroundStyle(LarderColor.ink.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(step.text)
                    .font(LarderFont.body(.title2))
                    .foregroundStyle(LarderColor.ink.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(RecipesCopy.stepPosition(number, of: count) + ". " + step.text)
                    .accessibilityFocused(focus, equals: index)
                if let timer {
                    TimerControl(timer: timer, name: RecipesCopy.stepTimerName(number))
                }
            }
            .padding(LarderSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A one-line reminder of a timer on another step; tapping jumps to that step.
private struct OtherTimerRow: View {
    let name: String
    let timer: TimerModel
    let jump: () -> Void

    var body: some View {
        Button(action: jump) {
            HStack(spacing: LarderSpacing.s) {
                Image(systemName: timer.state == .finished ? "checkmark.circle.fill" : "timer")
                    .accessibilityHidden(true)
                Text(name)
                Spacer()
                Text(timer.state == .finished ? RecipesCopy.timerDone : TimerFormat.clock(timer.remainingSeconds))
                    .font(LarderFont.mono(.body))
            }
            .font(LarderFont.body(.body))
            .foregroundStyle(LarderColor.ink.primary)
            .padding(.vertical, LarderSpacing.s)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(timer.state == .finished ? RecipesCopy.timerDone : TimerFormat.spoken(timer.remainingSeconds))
    }
}

#if DEBUG
#Preview("CookingModeView") {
    CookingModeView(
        recipe: PreviewData.chanaMasala,
        ingredients: PreviewData.ingredients[PreviewData.chanaMasala.id] ?? []
    )
}

#Preview("CookingModeView no steps") {
    CookingModeView(recipe: Recipe(title: "Empty", origin: .generated, servings: 1, prepMinutes: 0, cookMinutes: 0), ingredients: [])
}
#endif
