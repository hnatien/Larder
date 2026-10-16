import LarderCore
import LarderDesign
import StoreKit
import SwiftUI

/// Profile, what Larder leaves out, Plus, data and about. Embed in a `NavigationStack`.
public struct SettingsView: View {
    private let model: SettingsModel
    private let entitlements: EntitlementStore
    @State private var showsPaywall = false
    @State private var showsManageSubscription = false
    @State private var intoleranceDraft = ""
    @State private var dislikeDraft = ""

    /// Creates the settings screen.
    public init(model: SettingsModel, entitlements: EntitlementStore) {
        self.model = model
        self.entitlements = entitlements
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LarderSpacing.xl) {
                if let error = model.error {
                    Label(AccountCopy.message(for: error), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(LarderColor.status(.danger))
                }
                if let profile = model.profile {
                    profileSection(profile)
                    ForEach(SettingsModel.editableAxes, id: \.self) { axis in
                        constraintSection(axis)
                    }
                }
                plusSection
                dataSection
                aboutSection
            }
            .padding(LarderSpacing.l)
        }
        .background(LarderColor.surface.canvas)
        .navigationTitle(AccountCopy.Settings.title)
        .task { await model.load() }
        .onChange(of: model.error) { _, error in
            if let error {
                AccessibilityNotification.Announcement(AccountCopy.message(for: error)).post()
            }
        }
        .confirmationDialog(
            AccountCopy.Settings.removeTitle(model.pendingRemoval.map { AccountCopy.name(of: $0.kind) } ?? ""),
            isPresented: Binding(get: { model.pendingRemoval != nil }, set: { if !$0 { model.cancelRemoval() } }),
            titleVisibility: .visible
        ) {
            Button(AccountCopy.Settings.removeConfirm, role: .destructive) {
                Task { await model.confirmRemoval() }
            }
            Button(AccountCopy.Settings.keep, role: .cancel) { model.cancelRemoval() }
        } message: {
            Text(AccountCopy.Settings.removeMessage)
        }
        .confirmationDialog(
            AccountCopy.Settings.deleteTitle,
            isPresented: Binding(get: { model.isConfirmingDelete }, set: { if !$0 { model.cancelDeleteAll() } }),
            titleVisibility: .visible
        ) {
            Button(AccountCopy.Settings.deleteConfirm, role: .destructive) {
                Task { await model.deleteAllData() }
            }
            Button(AccountCopy.cancel, role: .cancel) { model.cancelDeleteAll() }
        } message: {
            Text(AccountCopy.Settings.deleteMessage)
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView(entitlements: entitlements) { showsPaywall = false }
        }
        #if os(iOS)
        .manageSubscriptionsSheet(isPresented: $showsManageSubscription)
        #endif
    }

    private func profileSection(_ profile: UserProfile) -> some View {
        SettingsGroup(AccountCopy.Settings.profile) {
            StackedPicker(AccountCopy.Settings.goal, selection: binding(profile.goal) { await model.setGoal($0) }) {
                ForEach(Goal.allCases, id: \.self) { Text(AccountCopy.name(of: $0)).tag($0) }
            }
            Stepper(
                value: binding(profile.householdSize) { await model.setHouseholdSize($0) },
                in: ProfileDefaults.householdRange
            ) {
                Text(AccountCopy.Onboarding.household(profile.householdSize))
            }
            StackedPicker(
                AccountCopy.Onboarding.cookTimeLabel,
                selection: binding(profile.maxCookMinutes) { await model.setMaxCookMinutes($0) }
            ) {
                ForEach(ProfileDefaults.cookMinuteChoices, id: \.self) { Text(Copy.Ledger.spokenMinutes($0)).tag($0) }
            }
            DisclosureGroup(AccountCopy.Settings.equipment) {
                ForEach(Equipment.allCases, id: \.self) { item in
                    Toggle(
                        AccountCopy.name(of: item),
                        isOn: binding(profile.equipment.contains(item)) { await model.setEquipment(item, included: $0) }
                    )
                }
            }
            StackedPicker(
                AccountCopy.Onboarding.birthYearLabel,
                selection: binding(model.displayedBirthYear) { await model.setBirthYear($0) }
            ) {
                Text(AccountCopy.preferNotToSay).tag(Int?.none)
                ForEach(model.birthYearChoices, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
            }
            LabelledToggle(
                AccountCopy.Numbers.label,
                hint: AccountCopy.Numbers.hint,
                isOn: binding(profile.showsNumbers) { await model.setShowsNumbers($0) }
            )
            LabelledToggle(
                AccountCopy.Onboarding.consentLabel,
                hint: AccountCopy.Onboarding.consentExplanation,
                isOn: binding(profile.consents.aiProcessing) { await model.setAIConsent($0) }
            )
            LabelledToggle(
                AccountCopy.Onboarding.simpleLayoutLabel,
                hint: AccountCopy.Onboarding.simpleLayoutHint,
                isOn: Binding(get: { model.prefersSimpleLayout }, set: { model.setPrefersSimpleLayout($0) })
            )
            LabelledToggle(
                AccountCopy.Onboarding.timersLabel,
                hint: AccountCopy.Onboarding.timersHint,
                isOn: Binding(get: { model.timersFlashAndVibrate }, set: { model.setTimersFlashAndVibrate($0) })
            )
        }
    }

    private func constraintSection(_ axis: ConstraintAxis) -> some View {
        SettingsGroup(AccountCopy.name(of: axis), footer: axis == .medical ? Copy.Medical.disclaimer : nil) {
            let current = model.constraints(on: axis)
            if current.isEmpty {
                HintText(AccountCopy.Settings.nothingLeftOut)
            }
            ForEach(current) { constraint in
                let name = AccountCopy.name(of: constraint.kind)
                HStack {
                    Text(name)
                    Spacer()
                    Button(AccountCopy.Settings.removeShort) {
                        Task { await model.requestRemoval(constraint) }
                    }
                    .buttonStyle(.larderQuiet)
                    .accessibilityLabel(AccountCopy.remove(name))
                    .accessibilityInputLabels([AccountCopy.remove(name), AccountCopy.Settings.removeShort])
                }
            }
            addControls(for: axis)
        }
    }

    @ViewBuilder
    private func addControls(for axis: ConstraintAxis) -> some View {
        let options = Self.addableKinds(on: axis).filter { !model.contains($0) }
        if !options.isEmpty {
            Menu(AccountCopy.Settings.add) {
                ForEach(options, id: \.self) { kind in
                    Button(AccountCopy.name(of: kind)) { Task { await model.add(kind) } }
                }
            }
            .frame(minHeight: 44)
        }
        switch axis {
        case .medical:
            DraftField(AccountCopy.Settings.addIntolerance, text: $intoleranceDraft) {
                await model.add(.intolerance($0))
            }
        case .preference:
            DraftField(AccountCopy.Settings.addDislike, text: $dislikeDraft) {
                await model.add(.dislike(.name($0)))
            }
        case .religious, .ethical, .goal:
            EmptyView()
        }
    }

    private var plusSection: some View {
        SettingsGroup(AccountCopy.Settings.plus) {
            Stamp(text: plusStatus)
            if entitlements.tier == .plus {
                #if os(iOS)
                Button(AccountCopy.Settings.manage) { showsManageSubscription = true }
                    .buttonStyle(.larderQuiet)
                #endif
            } else {
                Button(AccountCopy.Settings.seePlus) { showsPaywall = true }
                    .buttonStyle(.larderQuiet)
            }
        }
    }

    private var plusStatus: String {
        guard entitlements.tier == .plus, let record = entitlements.activeRecord else { return AccountCopy.Settings.free }
        guard let expiry = record.expirationDate else { return AccountCopy.Settings.plusActive }
        return AccountCopy.Settings.plusUntil(expiry.formatted(date: .abbreviated, time: .omitted))
    }

    private var dataSection: some View {
        SettingsGroup(AccountCopy.Settings.data, footer: AccountCopy.Settings.exportHint) {
            ShareLink(item: model.exportDocument, preview: SharePreview(AccountCopy.Settings.exportName)) {
                Label(AccountCopy.Settings.export, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.larderSecondary)
            Button(AccountCopy.Settings.delete, role: .destructive) { model.requestDeleteAll() }
                .buttonStyle(.larderSecondary)
        }
    }

    private var aboutSection: some View {
        SettingsGroup(AccountCopy.Settings.about) {
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text(AccountCopy.Settings.version(version))
            }
            Text(AccountCopy.Settings.grdbLicence)
            if LarderFont.hasBundledFonts {
                Text(AccountCopy.Settings.fontLicence)
            }
            Text(AccountCopy.Settings.usdaAttribution)
        }
        .font(LarderFont.body(.footnote))
        .foregroundStyle(LarderColor.ink.secondary)
    }

    /// A binding that shows `value` and saves changes through `save`.
    private func binding<Value: Sendable>(_ value: Value, save: @escaping (Value) async -> Void) -> Binding<Value> {
        Binding(get: { value }, set: { newValue in Task { await save(newValue) } })
    }

    /// The kinds offered under "Add" for an axis; an eating-disorder history is never offered.
    static func addableKinds(on axis: ConstraintAxis) -> [ConstraintKind] {
        switch axis {
        case .medical:
            OnboardingModel.allergenChoices.map(ConstraintKind.allergen) + OnboardingModel.medicalChoices.map(ConstraintKind.medical)
        case .religious:
            ReligiousRule.allCases.map(ConstraintKind.religious)
        case .ethical:
            DietPattern.allCases.map(ConstraintKind.diet)
        case .preference, .goal:
            []
        }
    }
}

/// A titled card of settings rows; the title is secondary ink so it keeps its contrast on the paper canvas.
private struct SettingsGroup<Content: View>: View {
    private let title: String
    private let footer: String?
    private let content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            Text(title)
                .font(LarderFont.body(.subheadline, weight: .semibold))
                .foregroundStyle(LarderColor.ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            PaperCard {
                VStack(alignment: .leading, spacing: LarderSpacing.l) { content }
            }
            if let footer {
                HintText(footer)
            }
        }
    }
}

/// A menu picker with its label above it, so a long label or value wraps instead of clipping.
private struct StackedPicker<Value: Hashable, Options: View>: View {
    private let label: String
    @Binding private var selection: Value
    private let options: Options

    init(_ label: String, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.label = label
        self._selection = selection
        self.options = options()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.xs) {
            Text(label)
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            Picker(label, selection: $selection) { options }
                .labelsHidden()
                .pickerStyle(.menu)
        }
    }
}

/// A text field with an Add button that submits trimmed, non-empty text and clears itself.
private struct DraftField: View {
    private let label: String
    @Binding private var text: String
    private let submit: (String) async -> Void

    init(_ label: String, text: Binding<String>, submit: @escaping (String) async -> Void) {
        self.label = label
        self._text = text
        self.submit = submit
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HStack {
            TextField(label, text: $text)
                .onSubmit(send)
                .padding(LarderSpacing.m)
                .frame(minHeight: 44)
                .background(LarderColor.surface.sunken, in: RoundedRectangle(cornerRadius: LarderRadius.field))
            Button(AccountCopy.Settings.add, action: send)
                .buttonStyle(.larderQuiet)
                .disabled(trimmed.isEmpty)
                .accessibilityLabel(label)
                .accessibilityInputLabels([label, AccountCopy.Settings.add])
        }
    }

    private func send() {
        let value = trimmed
        guard !value.isEmpty else { return }
        text = ""
        Task { await submit(value) }
    }
}

#if DEBUG
#Preview("Settings, free") {
    NavigationStack {
        SettingsView(model: PreviewSupport.settingsModel(), entitlements: PreviewSupport.entitlements())
    }
}

#Preview("Settings, Plus") {
    let entitlements = PreviewSupport.entitlements(plusUntil: Date().addingTimeInterval(30 * 86_400))
    NavigationStack {
        SettingsView(model: PreviewSupport.settingsModel(), entitlements: entitlements)
    }
    .task { await entitlements.start() }
}
#endif
