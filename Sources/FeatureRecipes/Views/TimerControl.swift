import LarderDesign
import SwiftUI

/// A named timer: remaining time in mono, with start, pause and reset.
struct TimerControl: View {
    let timer: TimerModel
    let name: String

    private var primaryTitle: String {
        switch timer.state {
        case .idle, .finished: RecipesCopy.start
        case .running: RecipesCopy.pause
        case .paused: RecipesCopy.resume
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.m) {
            Text(name)
                .font(LarderFont.body(.headline))
                .foregroundStyle(LarderColor.ink.secondary)
            Text(TimerFormat.clock(timer.remainingSeconds))
                .font(LarderFont.mono(.largeTitle))
                .foregroundStyle(LarderColor.ink.primary)
                .accessibilityLabel(name)
                .accessibilityValue(TimerFormat.spoken(timer.remainingSeconds))
            if let status {
                Label(status.title, systemImage: status.symbol)
                    .font(LarderFont.body(.body, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.primary)
            }
            AdaptiveStack(alignment: .center, spacing: LarderSpacing.m) { buttons }
        }
        .padding(LarderSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LarderColor.surface.sunken, in: RoundedRectangle(cornerRadius: LarderRadius.card))
        .accessibilityElement(children: .contain)
    }

    private var status: (title: String, symbol: String)? {
        switch timer.state {
        case .finished: (RecipesCopy.timerDone, "checkmark.circle.fill")
        case .paused: (RecipesCopy.timerPaused, "pause.circle.fill")
        case .idle, .running: nil
        }
    }

    @ViewBuilder private var buttons: some View {
        Button {
            if timer.state == .running { timer.pause() } else { timer.start() }
        } label: {
            Text(primaryTitle).frame(maxWidth: .infinity)
        }
        .buttonStyle(.larderPrimary)
        .accessibilityLabel(RecipesCopy.timerAction(primaryTitle, name: name))
        Button {
            timer.reset()
        } label: {
            Text(RecipesCopy.reset).frame(maxWidth: .infinity)
        }
        .buttonStyle(.larderSecondary)
        .disabled(timer.state == .idle)
        .accessibilityLabel(RecipesCopy.timerAction(RecipesCopy.reset, name: name))
    }
}

#if DEBUG
#Preview("TimerControl") {
    VStack(spacing: LarderSpacing.l) {
        TimerControl(timer: TimerModel(seconds: 900), name: RecipesCopy.stepTimerName(2))
        TimerControl(timer: TimerModel(seconds: 3725), name: RecipesCopy.stepTimerName(4))
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
#endif
