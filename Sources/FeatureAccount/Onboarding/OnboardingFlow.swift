import LarderCore
import LarderDesign
import SwiftUI

/// First-run questions, one per screen, ending in a saved profile.
public struct OnboardingFlow: View {
    @Bindable private var model: OnboardingModel
    private let onFinish: () -> Void
    @AccessibilityFocusState private var isHeadingFocused: Bool
    @ScaledSpacing(.l) private var gutter
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Creates the flow; `onFinish` runs once everything is saved.
    public init(model: OnboardingModel, onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: LarderSpacing.xl) {
                    Stamp(text: model.progressText)
                        .accessibilityLabel(model.spokenProgress)
                    SectionHeading(title)
                        .accessibilityFocused($isHeadingFocused)
                    content
                    if model.error != nil {
                        Label(AccountCopy.Onboarding.saveFailed, systemImage: "exclamationmark.triangle")
                            .font(LarderFont.body(.body))
                            .foregroundStyle(LarderColor.status(.danger))
                    }
                }
                .padding(gutter)
            }
            footer
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

    private var title: String {
        switch model.step {
        case .welcome: AccountCopy.Onboarding.welcomeTitle
        case .leaveOut: AccountCopy.Onboarding.leaveOutTitle
        case .eatBy: AccountCopy.Onboarding.eatByTitle
        case .goal: AccountCopy.Onboarding.goalTitle
        case .household: AccountCopy.Onboarding.householdTitle
        case .equipment: AccountCopy.Onboarding.equipmentTitle
        case .easierToUse: AccountCopy.Onboarding.easierTitle
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome: welcome
        case .leaveOut: leaveOut
        case .eatBy: eatBy
        case .goal: goal
        case .household: household
        case .equipment: equipment
        case .easierToUse: easierToUse
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.l) {
            ForEach(AccountCopy.Onboarding.welcomeLines, id: \.self) { line in
                BodyText(line)
            }
            ReasonLine(text: Copy.Medical.disclaimer)
            LabelledToggle(
                AccountCopy.Onboarding.consentLabel,
                hint: AccountCopy.Onboarding.consentExplanation,
                isOn: $model.aiConsent
            )
        }
    }

    private var leaveOut: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.l) {
            ChoiceList(
                choices: OnboardingModel.allergenChoices,
                title: AccountCopy.name(of:),
                isSelected: { model.allergens.contains($0) },
                toggle: { model.allergens.formSymmetricDifference([$0]) }
            )
            VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                Text(AccountCopy.Onboarding.intoleranceLabel)
                    .font(LarderFont.body(.body, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.primary)
                TextField(AccountCopy.Onboarding.intolerancePrompt, text: $model.intoleranceText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(AccountCopy.Onboarding.intoleranceLabel)
            }
        }
    }

    private var eatBy: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.l) {
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
            SectionHeading(AccountCopy.Onboarding.carefulTitle)
            ReasonLine(text: Copy.Medical.disclaimer)
            ChoiceList(
                choices: OnboardingModel.medicalChoices,
                title: AccountCopy.name(of:),
                isSelected: { model.medicalFlags.contains($0) },
                toggle: { model.toggleMedical($0) }
            )
            ChoiceRow<MedicalFlag>(title: AccountCopy.preferNotToSay, isSelected: model.medicalPreferNotToSay, mode: .single) {
                model.preferNotToSayMedical()
            }
        }
    }

    private var goal: some View {
        ChoiceList(
            choices: Goal.allCases,
            mode: .single,
            title: AccountCopy.name(of:),
            isSelected: { model.goal == $0 },
            toggle: { model.goal = $0 }
        )
    }

    private var household: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.xl) {
            Stepper(value: $model.householdSize, in: OnboardingModel.householdRange) {
                BodyText(AccountCopy.Onboarding.household(model.householdSize))
            }
            Picker(AccountCopy.Onboarding.cookTimeLabel, selection: $model.maxCookMinutes) {
                ForEach(OnboardingModel.cookMinuteChoices, id: \.self) { minutes in
                    Text(Copy.Ledger.spokenMinutes(minutes)).tag(minutes)
                }
            }
            .pickerStyle(.menu)
            VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                Picker(AccountCopy.Onboarding.birthYearLabel, selection: $model.birthYear) {
                    Text(AccountCopy.preferNotToSay).tag(Int?.none)
                    ForEach(model.birthYearChoices, id: \.self) { year in
                        Text(String(year)).tag(Int?.some(year))
                    }
                }
                .pickerStyle(.menu)
                HintText(AccountCopy.Onboarding.birthYearExplanation)
            }
        }
    }

    private var equipment: some View {
        ChoiceList(
            choices: Equipment.allCases,
            title: AccountCopy.name(of:),
            isSelected: { model.equipment.contains($0) },
            toggle: { model.equipment.formSymmetricDifference([$0]) }
        )
    }

    private var easierToUse: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.l) {
            VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                BodyText(AccountCopy.Onboarding.largerTextLabel)
                HintText(AccountCopy.Onboarding.largerTextHint)
            }
            .accessibilityElement(children: .combine)
            LabelledToggle(
                AccountCopy.Onboarding.simpleLayoutLabel,
                hint: AccountCopy.Onboarding.simpleLayoutHint,
                isOn: $model.prefersSimpleLayout
            )
            LabelledToggle(
                AccountCopy.Onboarding.timersLabel,
                hint: AccountCopy.Onboarding.timersHint,
                isOn: $model.timersFlashAndVibrate
            )
            LabelledToggle(AccountCopy.Numbers.label, hint: AccountCopy.Numbers.hint, isOn: $model.showsNumbers)
        }
    }

    private var footer: some View {
        AdaptiveStack(spacing: LarderSpacing.m) { footerButtons }
        .padding(gutter)
        .background(LarderColor.surface.raised)
        .disabled(model.isSaving)
    }

    @ViewBuilder
    private var footerButtons: some View {
        if model.canGoBack {
            Button(AccountCopy.back) { model.back() }
                .buttonStyle(.larderSecondary)
        }
        if !typeSize.isAccessibilitySize {
            Spacer(minLength: 0)
        }
        if model.canSkip {
            Button(AccountCopy.skip) { Task { await model.skip() } }
                .buttonStyle(.larderQuiet)
        }
        Button(model.isLastStep ? AccountCopy.finish : AccountCopy.next) {
            if model.isLastStep {
                Task { await model.finish() }
            } else {
                model.next()
            }
        }
        .buttonStyle(.larderPrimary)
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
#Preview("Onboarding") {
    OnboardingFlow(
        model: OnboardingModel(
            profiles: PreviewSupport.Store(),
            preferences: ComfortPreferences(store: PreviewSupport.Flags()),
            dates: PreviewSupport.Dates()
        ),
        onFinish: {}
    )
}

#Preview("Onboarding, careful step") {
    let model = OnboardingModel(
        profiles: PreviewSupport.Store(),
        preferences: ComfortPreferences(store: PreviewSupport.Flags()),
        dates: PreviewSupport.Dates()
    )
    model.next()
    model.next()
    return OnboardingFlow(model: model, onFinish: {})
}
#endif
