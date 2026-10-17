import LarderCore
import LarderDesign
import SwiftUI

/// The first run: a welcome screen that says what Larder does, then three optional questions, ending in a saved profile.
public struct OnboardingFlow: View {
    @Bindable private var model: OnboardingModel
    private let onFinish: () -> Void
    @AccessibilityFocusState private var isHeadingFocused: Bool
    @ScaledSpacing(.l) private var gutter

    /// Creates the flow; `onFinish` runs once everything is saved.
    public init(model: OnboardingModel, onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    public var body: some View {
        Group {
            if model.step == .welcome {
                WelcomeView { model.next() }
            } else {
                question
            }
        }
        .background(LarderColor.surface.canvas)
        .onChange(of: model.step) {
            isHeadingFocused = true
        }
        .onChange(of: model.isFinished) { _, finished in
            if finished { onFinish() }
        }
        .onChange(of: model.error) { _, error in
            if error != nil {
                AccessibilityNotification.Announcement(AccountCopy.Onboarding.saveFailed).post()
            }
        }
    }

    private var question: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: LarderSpacing.xl) {
                    VStack(alignment: .leading, spacing: LarderSpacing.s) {
                        Text(model.progressText)
                            .font(LarderFont.body(.subheadline, weight: .semibold))
                            .foregroundStyle(LarderColor.accent.brand)
                        Text(title)
                            .font(LarderFont.display(.title))
                            .foregroundStyle(LarderColor.ink.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($isHeadingFocused)
                        HintText(detail)
                    }
                    content
                    if model.error != nil {
                        InlineBanner(AccountCopy.Onboarding.saveFailed)
                    }
                }
                .padding(gutter)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
    }

    private var topBar: some View {
        HStack(spacing: LarderSpacing.m) {
            Button {
                model.back()
            } label: {
                Image(systemName: "chevron.left")
                    .font(LarderFont.body(.body, weight: .semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(LarderColor.ink.primary)
            .accessibilityLabel(AccountCopy.back)
            ProgressView(value: model.progress)
                .tint(LarderColor.accent.brand)
                .accessibilityHidden(true)
            Button(AccountCopy.Onboarding.setUpLater) { Task { await model.setUpLater() } }
                .buttonStyle(.larderQuiet)
                .fixedSize()
                .layoutPriority(1)
                .disabled(model.isSaving)
        }
        .padding(.horizontal, LarderSpacing.s)
        .padding(.top, LarderSpacing.xs)
    }

    private var title: String {
        switch model.step {
        case .welcome: AccountCopy.Onboarding.welcomeTitle
        case .leaveOut: AccountCopy.Onboarding.leaveOutTitle
        case .eatBy: AccountCopy.Onboarding.eatByTitle
        case .household: AccountCopy.Onboarding.householdTitle
        }
    }

    private var detail: String {
        switch model.step {
        case .welcome: AccountCopy.Onboarding.welcomeSubtitle
        case .leaveOut: AccountCopy.Onboarding.leaveOutDetail
        case .eatBy: AccountCopy.Onboarding.eatByDetail
        case .household: AccountCopy.Onboarding.householdDetail
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome: EmptyView()
        case .leaveOut: leaveOut
        case .eatBy: eatBy
        case .household: household
        }
    }

    private var leaveOut: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.xl) {
            ChoiceList(
                choices: OnboardingModel.allergenChoices,
                title: AccountCopy.name(of:),
                isSelected: { model.allergens.contains($0) },
                toggle: { model.allergens.formSymmetricDifference([$0]) }
            )
            VStack(alignment: .leading, spacing: LarderSpacing.s) {
                Text(AccountCopy.Onboarding.intoleranceLabel)
                    .font(LarderFont.body(.body, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.primary)
                TextField(AccountCopy.Onboarding.intolerancePrompt, text: $model.intoleranceText, axis: .vertical)
                    .font(LarderFont.body(.body))
                    .padding(LarderSpacing.m)
                    .frame(minHeight: 44)
                    .background(LarderColor.surface.raised, in: RoundedRectangle(cornerRadius: LarderRadius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: LarderRadius.card, style: .continuous)
                            .strokeBorder(LarderColor.line.hairline, lineWidth: 1)
                    }
                    .accessibilityLabel(AccountCopy.Onboarding.intoleranceLabel)
            }
        }
    }

    private var eatBy: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.xl) {
            ChoiceList(
                choices: EatByChoice.all,
                title: { choice in
                    switch choice {
                    case .diet(let diet): AccountCopy.name(of: diet)
                    case .religious(let rule): AccountCopy.name(of: rule)
                    }
                },
                isSelected: { model.eatBy.contains($0) },
                toggle: { model.eatBy.formSymmetricDifference([$0]) }
            )
            VStack(alignment: .leading, spacing: LarderSpacing.m) {
                VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                    Text(AccountCopy.Onboarding.carefulTitle)
                        .font(LarderFont.display(.title2))
                        .foregroundStyle(LarderColor.ink.primary)
                        .accessibilityAddTraits(.isHeader)
                    HintText(AccountCopy.Onboarding.carefulDetail)
                }
                ChipFlow {
                    ForEach(OnboardingModel.medicalChoices, id: \.self) { flag in
                        ChoiceChip(AccountCopy.name(of: flag), isSelected: model.medicalFlags.contains(flag)) {
                            model.toggleMedical(flag)
                        }
                    }
                    ChoiceChip(AccountCopy.preferNotToSay, isSelected: model.medicalPreferNotToSay) {
                        model.preferNotToSayMedical()
                    }
                }
                ReasonLine(text: Copy.Medical.disclaimer)
            }
        }
    }

    private var household: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.xl) {
            PaperCard {
                HStack(spacing: LarderSpacing.l) {
                    CountButton(systemImage: "minus", label: AccountCopy.Onboarding.fewerPeople) {
                        model.householdSize = max(model.householdSize - 1, OnboardingModel.householdRange.lowerBound)
                    }
                    .disabled(model.householdSize <= OnboardingModel.householdRange.lowerBound)
                    Text(AccountCopy.Onboarding.household(model.householdSize))
                        .font(LarderFont.display(.title))
                        .foregroundStyle(LarderColor.ink.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.numericText())
                    CountButton(systemImage: "plus", label: AccountCopy.Onboarding.morePeople) {
                        model.householdSize = min(model.householdSize + 1, OnboardingModel.householdRange.upperBound)
                    }
                    .disabled(model.householdSize >= OnboardingModel.householdRange.upperBound)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(AccountCopy.Onboarding.householdTitle)
                .accessibilityValue(AccountCopy.Onboarding.household(model.householdSize))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: model.householdSize = min(model.householdSize + 1, OnboardingModel.householdRange.upperBound)
                    case .decrement: model.householdSize = max(model.householdSize - 1, OnboardingModel.householdRange.lowerBound)
                    @unknown default: break
                    }
                }
            }
            VStack(alignment: .leading, spacing: LarderSpacing.m) {
                Text(AccountCopy.Onboarding.cookTimeLabel)
                    .font(LarderFont.body(.body, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                ChoiceList(
                    choices: OnboardingModel.cookMinuteChoices,
                    title: { Copy.Ledger.spokenMinutes($0) },
                    isSelected: { model.maxCookMinutes == $0 },
                    toggle: { model.maxCookMinutes = $0 }
                )
            }
        }
    }

    private var footer: some View {
        Button {
            if model.isLastStep {
                Task { await model.finish() }
            } else {
                model.next()
            }
        } label: {
            Text(model.isLastStep ? AccountCopy.Onboarding.startPlanning : AccountCopy.Onboarding.continueLabel)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.larderPrimary)
        .padding(.horizontal, gutter)
        .padding(.vertical, LarderSpacing.m)
        .disabled(model.isSaving)
        // An edge and the canvas behind it, so the question never reads through under the button.
        .frame(maxWidth: .infinity)
        .background(LarderColor.surface.canvas)
        .overlay(alignment: .top) {
            Divider().overlay(LarderColor.line.hairline)
        }
    }
}

/// A round plus or minus button for the household count.
private struct CountButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(LarderFont.body(.title3, weight: .semibold))
                .frame(minWidth: 48, minHeight: 48)
                .background(LarderColor.accent.brand.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(LarderColor.accent.brand)
        .accessibilityLabel(label)
    }
}

/// The first screen: what Larder is for and how it works, in one view, with one way forward.
struct WelcomeView: View {
    let onStart: () -> Void
    @ScaledSpacing(.l) private var gutter
    @ScaledMetric(relativeTo: .largeTitle) private var markSide: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var pointIconSide: CGFloat = 44

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LarderSpacing.xl) {
                HStack(spacing: LarderSpacing.m) {
                    // The app's jar mark from the app bundle's asset catalogue, as on the launch screen.
                    Image("LaunchMark", bundle: .main)
                        .resizable()
                        .scaledToFit()
                        .frame(width: markSide, height: markSide)
                        .accessibilityHidden(true)
                    Text(verbatim: "Larder")
                        .font(LarderFont.display(.title2))
                        .foregroundStyle(LarderColor.ink.primary)
                }
                if LarderIllustration.welcome.isAvailable {
                    LarderIllustration.welcome.image
                        .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: LarderSpacing.m) {
                    Text(AccountCopy.Onboarding.welcomeTitle)
                        .font(LarderFont.display(.largeTitle))
                        .foregroundStyle(LarderColor.ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    BodyText(AccountCopy.Onboarding.welcomeSubtitle)
                        .foregroundStyle(LarderColor.ink.secondary)
                }
                PaperCard {
                    VStack(alignment: .leading, spacing: LarderSpacing.l) {
                        ForEach(AccountCopy.Onboarding.welcomePoints, id: \.title) { point in
                            HStack(alignment: .top, spacing: LarderSpacing.m) {
                                Image(systemName: point.symbol)
                                    .font(LarderFont.body(.title3, weight: .medium))
                                    .foregroundStyle(LarderColor.accent.second)
                                    .frame(width: pointIconSide, height: pointIconSide)
                                    .background(LarderColor.accent.second.opacity(0.12), in: Circle())
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: LarderSpacing.xxs) {
                                    Text(point.title)
                                        .font(LarderFont.body(.body, weight: .semibold))
                                        .foregroundStyle(LarderColor.ink.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HintText(point.detail)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .padding(gutter)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: LarderSpacing.s) {
                Button(action: onStart) {
                    Text(AccountCopy.Onboarding.getStarted).frame(maxWidth: .infinity)
                }
                .buttonStyle(.larderPrimary)
                Text(AccountCopy.Onboarding.welcomeNote)
                    .font(LarderFont.body(.footnote))
                    .foregroundStyle(LarderColor.ink.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, LarderSpacing.m)
            .background(LarderColor.surface.canvas)
        }
    }
}

/// Body copy in primary ink that wraps.
struct BodyText: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(LarderFont.body(.body))
            .foregroundStyle(LarderColor.ink.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Secondary explanatory copy that wraps.
struct HintText: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(LarderFont.body(.footnote))
            .foregroundStyle(LarderColor.ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A toggle whose label carries a one-line explanation, read together by VoiceOver.
struct LabelledToggle: View {
    private let title: String
    private let hint: String
    @Binding private var isOn: Bool

    init(_ title: String, hint: String, isOn: Binding<Bool>) {
        self.title = title
        self.hint = hint
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                Text(title)
                    .font(LarderFont.body(.body, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.primary)
                HintText(hint)
            }
        }
        .tint(LarderColor.accent.second)
        .frame(minHeight: 44)
    }
}

#if DEBUG
#Preview("Onboarding welcome") {
    OnboardingFlow(
        model: OnboardingModel(
            profiles: PreviewSupport.Store(),
            preferences: ComfortPreferences(store: PreviewSupport.Flags()),
            dates: PreviewSupport.Dates()
        ),
        onFinish: {}
    )
}

#Preview("Onboarding, allergens") {
    let model = OnboardingModel(
        profiles: PreviewSupport.Store(),
        preferences: ComfortPreferences(store: PreviewSupport.Flags()),
        dates: PreviewSupport.Dates()
    )
    model.next()
    return OnboardingFlow(model: model, onFinish: {})
}
#endif
