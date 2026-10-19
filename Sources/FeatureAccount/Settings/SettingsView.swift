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
                if !model.hasLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, LarderSpacing.xxl)
                } else {
                    if let profile = model.profile {
                        // What Larder leaves out comes first: it is the safety setting, and setup may have been left for later.
                        ForEach(SettingsModel.editableAxes, id: \.self) { axis in
                            constraintSection(axis)
                        }
                        profileSection(profile)
                    }
                    plusSection
                    dataSection
                    aboutSection
                    deleteSection
                }
            }
            .padding(LarderSpacing.l)
        }
        .background(LarderColor.surface.canvas)
        .safeAreaInset(edge: .top, spacing: 0) { SettingsErrorBanner(model: model) }
        .larderToast(removalToast, onExpire: model.dismissRemovalUndo)
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

    @ViewBuilder
    private func profileSection(_ profile: UserProfile) -> some View {
        SettingsGroup(AccountCopy.Settings.household) {
            Stepper(
                value: binding(profile.householdSize) { await model.setHouseholdSize($0) },
                in: ProfileDefaults.householdRange
            ) {
                Text(AccountCopy.Onboarding.household(profile.householdSize))
            }
            StackedPicker(
                AccountCopy.Onboarding.cookTimeLabel,
                value: Copy.Ledger.spokenMinutes(profile.maxCookMinutes),
                selection: binding(profile.maxCookMinutes) { await model.setMaxCookMinutes($0) }
            ) {
                ForEach(ProfileDefaults.cookMinuteChoices, id: \.self) { Text(Copy.Ledger.spokenMinutes($0)).tag($0) }
            }
            StackedPicker(
                AccountCopy.Settings.goal,
                value: AccountCopy.name(of: profile.goal),
                selection: binding(profile.goal) { await model.setGoal($0) }
            ) {
                ForEach(Goal.allCases, id: \.self) { Text(AccountCopy.name(of: $0)).tag($0) }
            }
            NavigationLink {
                EquipmentSettings(model: model)
            } label: {
                DrillInRow(AccountCopy.Settings.equipment, detail: Self.equipmentSummary(profile.equipment))
            }
            .buttonStyle(.plain)
        }
        SettingsGroup(AccountCopy.Settings.nutrition) {
            LabelledToggle(
                AccountCopy.Numbers.label,
                hint: AccountCopy.Numbers.hint,
                isOn: binding(profile.showsNumbers) { await model.setShowsNumbers($0) }
            )
            VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                StackedPicker(
                    AccountCopy.Onboarding.birthYearLabel,
                    value: model.displayedBirthYear.map(String.init) ?? AccountCopy.preferNotToSay,
                    selection: binding(model.displayedBirthYear) { await model.setBirthYear($0) }
                ) {
                    Text(AccountCopy.preferNotToSay).tag(Int?.none)
                    ForEach(model.birthYearChoices, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                }
                HintText(AccountCopy.Onboarding.birthYearExplanation)
            }
        }
        SettingsGroup(AccountCopy.Settings.cooking) {
            LabelledToggle(
                AccountCopy.Onboarding.timersLabel,
                hint: AccountCopy.Onboarding.timersHint,
                isOn: Binding(get: { model.timersFlashAndVibrate }, set: { model.setTimersFlashAndVibrate($0) })
            )
        }
        SettingsGroup(AccountCopy.Settings.assistant) {
            LabelledToggle(
                AccountCopy.Onboarding.consentLabel,
                hint: AccountCopy.Onboarding.consentExplanation,
                isOn: binding(profile.consents.aiProcessing) { await model.setAIConsent($0) }
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
            Menu {
                ForEach(Self.menuSections(options), id: \.title) { section in
                    if let title = section.title {
                        Section(title) { addButtons(section.kinds) }
                    } else {
                        addButtons(section.kinds)
                    }
                }
            } label: {
                Label(AccountCopy.Settings.add(to: AccountCopy.name(of: axis)), systemImage: "plus.circle")
                    .foregroundStyle(LarderColor.accent.second)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        switch axis {
        case .medical:
            DraftField(AccountCopy.Settings.addIntolerance, text: $intoleranceDraft, isListed: { model.contains(.intolerance($0)) }) {
                await model.add(.intolerance($0))
            }
        case .preference:
            DraftField(AccountCopy.Settings.addDislike, text: $dislikeDraft, isListed: { model.contains(.dislike(.name($0))) }) {
                await model.add(.dislike(.name($0)))
            }
        case .religious, .ethical, .goal:
            EmptyView()
        }
    }

    private func addButtons(_ kinds: [ConstraintKind]) -> some View {
        ForEach(kinds, id: \.self) { kind in
            Button(AccountCopy.name(of: kind)) { Task { await model.add(kind) } }
        }
    }

    private var plusSection: some View {
        SettingsGroup(AccountCopy.Settings.plus) {
            if entitlements.tier == .plus {
                Pill(plusStatus, systemImage: "checkmark.seal", tone: .second)
                #if os(iOS)
                Button(AccountCopy.Settings.manage) { showsManageSubscription = true }
                    .buttonStyle(.larderSecondary)
                #endif
            } else {
                HintText(AccountCopy.Settings.freeStatus)
                if let available = model.freeWeekAvailable {
                    Label(
                        available ? AccountCopy.Settings.freeWeekLeft : AccountCopy.Settings.freeWeekUsed,
                        systemImage: available ? "calendar.badge.plus" : "calendar.badge.checkmark"
                    )
                    .font(LarderFont.body(.subheadline))
                    .foregroundStyle(LarderColor.ink.primary)
                }
                Button(AccountCopy.Settings.seePlus) { showsPaywall = true }
                    .buttonStyle(.larderSecondary)
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
        }
    }

    private var deleteSection: some View {
        SettingsGroup(AccountCopy.Settings.dangerZone, footer: AccountCopy.Settings.deleteFooter) {
            Button(role: .destructive) {
                model.requestDeleteAll()
            } label: {
                Label(AccountCopy.Settings.delete, systemImage: "trash")
                    .font(LarderFont.body(.body, weight: .semibold))
                    .foregroundStyle(LarderColor.status(.danger))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutSection: some View {
        SettingsGroup(AccountCopy.Settings.about) {
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
               let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                Text(AccountCopy.Settings.version(version, build: build))
                    .foregroundStyle(LarderColor.ink.secondary)
                    .textSelection(.enabled)
            }
            NavigationLink {
                AcknowledgementsView()
            } label: {
                DrillInRow(AccountCopy.Settings.acknowledgements)
            }
            .buttonStyle(.plain)
            if let terms = LegalLinks.terms {
                ExternalLinkRow(AccountCopy.Settings.terms, destination: terms)
            }
            if let privacy = LegalLinks.privacy {
                ExternalLinkRow(AccountCopy.Settings.privacy, destination: privacy)
            }
        }
    }

    /// The last rule taken off, with Undo.
    private var removalToast: LarderToast? {
        model.lastRemoved.map { removed in
            LarderToast(id: removed.id.rawValue, AccountCopy.Settings.removedRule, systemImage: "minus.circle.fill", actionTitle: AccountCopy.Settings.undo) {
                Task { await model.undoRemoval() }
            }
        }
    }

    /// A binding that shows `value` and saves changes through `save`.
    private func binding<Value: Sendable>(_ value: Value, save: @escaping (Value) async -> Void) -> Binding<Value> {
        Binding(get: { value }, set: { newValue in Task { await save(newValue) } })
    }

    /// The equipment that is on, as a sentence-style list, or "Not set" when plans don't check equipment at all.
    static func equipmentSummary(_ equipment: Set<Equipment>) -> String {
        let names = Equipment.allCases.filter(equipment.contains).map { AccountCopy.name(of: $0) }
        return names.isEmpty ? AccountCopy.Settings.equipmentNotSet : names.formatted(.list(type: .and))
    }

    /// The Add menu's groups: allergens and health conditions apart, every other axis in one untitled group.
    static func menuSections(_ kinds: [ConstraintKind]) -> [(title: String?, kinds: [ConstraintKind])] {
        let allergens = kinds.filter { if case .allergen = $0 { true } else { false } }
        let conditions = kinds.filter { if case .medical = $0 { true } else { false } }
        guard !allergens.isEmpty || !conditions.isEmpty else { return [(nil, kinds)] }
        return [(AccountCopy.Settings.allergies, allergens), (AccountCopy.Settings.conditions, conditions)].filter { !$0.kinds.isEmpty }
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

/// A card of settings rows with a hairline between rows, like an inset grouped list; the optional title is secondary
/// ink so it keeps its contrast on the paper canvas.
struct SettingsGroup<Content: View>: View {
    private let title: String?
    private let footer: String?
    private let content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            if let title {
                Text(title)
                    .font(LarderFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, LarderSpacing.l)
                    .accessibilityAddTraits(.isHeader)
            }
            PaperCard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Group(subviews: content) { rows in
                        ForEach(rows.indices, id: \.self) { index in
                            rows[index]
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.horizontal, LarderSpacing.l)
                                .padding(.vertical, LarderSpacing.m)
                            if index < rows.count - 1 {
                                Divider()
                                    .overlay(LarderColor.line.hairline)
                                    .padding(.leading, LarderSpacing.l)
                            }
                        }
                    }
                }
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.primary)
            }
            if let footer {
                HintText(footer)
                    .padding(.horizontal, LarderSpacing.l)
            }
        }
    }
}

/// The settings error, pinned above the scroll view so a failed save far down the page is still seen.
private struct SettingsErrorBanner: View {
    let model: SettingsModel

    var body: some View {
        if let error = model.error {
            InlineBanner(
                AccountCopy.message(for: error),
                action: error == .loadFailed ? .init(title: AccountCopy.Settings.tryAgain) { Task { await model.load() } } : nil,
                dismissTitle: AccountCopy.Settings.dismiss,
                onDismiss: model.clearError
            )
            .padding(.horizontal, LarderSpacing.l)
            .padding(.vertical, LarderSpacing.s)
            .background(LarderColor.surface.canvas)
        }
    }
}

/// A menu picker with its label above it, so a long label or value wraps instead of clipping. The value is drawn here
/// rather than by the system picker so it lines up with the label.
private struct StackedPicker<Value: Hashable, Options: View>: View {
    private let label: String
    private let value: String
    @Binding private var selection: Value
    private let options: Options

    init(_ label: String, value: String, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.label = label
        self.value = value
        self._selection = selection
        self.options = options()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.xs) {
            Text(label)
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            Menu {
                Picker(label, selection: $selection) { options }
                    .pickerStyle(.inline)
                    .labelsHidden()
            } label: {
                HStack(spacing: LarderSpacing.xs) {
                    Text(value)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(LarderColor.accent.second)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(label)
            .accessibilityValue(value)
        }
    }
}

/// A row that opens another settings page: a title, an optional summary under it and a chevron.
private struct DrillInRow: View {
    private let title: String
    private let detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(spacing: LarderSpacing.m) {
            VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                Text(title)
                    .foregroundStyle(LarderColor.ink.primary)
                if let detail {
                    HintText(detail)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(LarderFont.body(.footnote, weight: .semibold))
                .foregroundStyle(LarderColor.ink.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A row that opens a web page outside Larder, marked with an arrow so it reads as a link.
private struct ExternalLinkRow: View {
    private let title: String
    private let destination: URL

    init(_ title: String, destination: URL) {
        self.title = title
        self.destination = destination
    }

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: LarderSpacing.m) {
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(LarderFont.body(.footnote, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(LarderColor.accent.second)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(.isLink)
    }
}

/// A text field with an Add button that submits trimmed, non-empty text and clears itself; text already on the list
/// is not added and says so.
private struct DraftField: View {
    private let label: String
    @Binding private var text: String
    private let isListed: (String) -> Bool
    private let submit: (String) async -> Void

    init(_ label: String, text: Binding<String>, isListed: @escaping (String) -> Bool, submit: @escaping (String) async -> Void) {
        self.label = label
        self._text = text
        self.isListed = isListed
        self.submit = submit
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDuplicate: Bool { !trimmed.isEmpty && isListed(trimmed) }

    var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.xs) {
            HStack {
                // Vertical so it grows with Dynamic Type instead of clipping; Return adds rather than starting a new line.
                TextField(label, text: $text, axis: .vertical)
                    .onSubmit(send)
                    .onChange(of: text) { _, new in
                        if new.contains("\n") {
                            text = new.replacingOccurrences(of: "\n", with: "")
                            send()
                        }
                    }
                    .padding(LarderSpacing.m)
                    .frame(minHeight: 44)
                    .background(LarderColor.surface.sunken, in: RoundedRectangle(cornerRadius: LarderRadius.field))
                Button(AccountCopy.Settings.add, action: send)
                    .buttonStyle(.larderQuiet)
                    .disabled(trimmed.isEmpty || isDuplicate)
                    .accessibilityLabel(label)
                    .accessibilityInputLabels([label, AccountCopy.Settings.add])
            }
            if isDuplicate {
                HintText(AccountCopy.Settings.alreadyListed)
            }
        }
        .onChange(of: isDuplicate) { _, duplicate in
            if duplicate { AccessibilityNotification.Announcement(AccountCopy.Settings.alreadyListed).post() }
        }
    }

    private func send() {
        let value = trimmed
        guard !value.isEmpty, !isListed(value) else { return }
        text = ""
        Task { await submit(value) }
    }
}

/// The equipment switches on their own page, so the list doesn't stretch the main settings page.
private struct EquipmentSettings: View {
    let model: SettingsModel

    var body: some View {
        ScrollView {
            if let profile = model.profile {
                SettingsGroup(footer: AccountCopy.Settings.equipmentHint) {
                    ForEach(Equipment.allCases, id: \.self) { item in
                        Toggle(
                            AccountCopy.name(of: item),
                            isOn: Binding(
                                get: { profile.equipment.contains(item) },
                                set: { included in Task { await model.setEquipment(item, included: included) } }
                            )
                        )
                        .tint(LarderColor.accent.second)
                    }
                }
                .padding(LarderSpacing.l)
            }
        }
        .background(LarderColor.surface.canvas)
        .safeAreaInset(edge: .top, spacing: 0) { SettingsErrorBanner(model: model) }
        .navigationTitle(AccountCopy.Settings.equipment)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
