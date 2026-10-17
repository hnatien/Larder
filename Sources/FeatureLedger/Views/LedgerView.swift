import LarderCore
import LarderDesign
import SwiftUI

/// What the meal sheet is open on.
enum LedgerSheet: Identifiable, Hashable {
    case meal(PlannedMealID, swapping: Bool)
    case openSlot(Date, MealType)

    var id: String {
        switch self {
        case .meal(let meal, _): meal.rawValue.uuidString
        case .openSlot(let date, let slot): "\(date.timeIntervalSinceReferenceDate)-\(slot.rawValue)"
        }
    }
}

/// The Plan tab: the week as a list of days, a meal row per dinner, a leftovers row per leftover, and the week's balance.
public struct LedgerView: View {
    private let model: LedgerModel
    private let onOpenRecipe: (RecipeID) -> Void
    private let onShowPaywall: () -> Void
    private let onOpenAccount: (() -> Void)?
    @State private var sheet: LedgerSheet?
    @State private var isConfirmingReplan = false
    @State private var showsSavedToast = false
    @AccessibilityFocusState private var headingFocused: Bool
    @Namespace private var dayRotor

    /// Creates the tab root; `onShowPaywall` runs when a free user has no free week left, and `onOpenAccount`
    /// adds the Settings button to the toolbar.
    public init(
        model: LedgerModel,
        onOpenRecipe: @escaping (RecipeID) -> Void,
        onShowPaywall: @escaping () -> Void = {},
        onOpenAccount: (() -> Void)? = nil
    ) {
        self.model = model
        self.onOpenRecipe = onOpenRecipe
        self.onShowPaywall = onShowPaywall
        self.onOpenAccount = onOpenAccount
    }

    public var body: some View {
        NavigationStack {
            list
                .navigationTitle(Copy.Tab.ledger)
                .navigationSubtitle(LedgerCopy.planSubtitle)
                .settingsButton(onOpenAccount)
                .toolbar {
                    if model.plan != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button(LedgerCopy.replan, systemImage: "arrow.triangle.2.circlepath") {
                                isConfirmingReplan = true
                            }
                            .disabled(model.isPlanning)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if showsSavedToast {
                        ToastBar(LedgerCopy.planSaved)
                            .padding(.horizontal, LarderSpacing.l)
                            .padding(.bottom, LarderSpacing.s)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .confirmationDialog(LedgerCopy.replanQuestion, isPresented: $isConfirmingReplan, titleVisibility: .visible) {
                    Button(LedgerCopy.replan) { Task { await model.replan(keepingLocked: true) } }
                    Button(Copy.Action.notNow, role: .cancel) {}
                } message: {
                    Text(LedgerCopy.replanMessage)
                }
        }
        .task { await model.load() }
        .sheet(item: $sheet) { target in
            MealSheet(model: model, target: target, onOpenRecipe: onOpenRecipe)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: model.paywallRequested) { _, requested in
            guard requested else { return }
            model.paywallRequested = false
            onShowPaywall()
        }
        .onChange(of: model.savedPlanCount) {
            AccessibilityNotification.Announcement(Copy.Voice.planSaved).post()
            headingFocused = true
            showsSavedToast = true
        }
        .task(id: showsSavedToast) {
            guard showsSavedToast else { return }
            try? await Task.sleep(for: .seconds(3))
            showsSavedToast = false
        }
        .sensoryFeedback(.success, trigger: model.savedPlanCount)
        .larderAnimation(LarderMotion.tap, value: showsSavedToast)
    }

    private var list: some View {
        List {
            header
                .ledgerListRow()
            if model.showsExplanation, model.plan != nil {
                explanationCard
                    .ledgerListRow()
            }
            if model.plan != nil {
                AdjustWeekCard(model: model, onOpenSettings: onOpenAccount)
                    .ledgerListRow()
            }
            ForEach(model.days) { day in
                dayRow(day)
            }
            if let balance = model.shelfBalance, !balance.levels.isEmpty {
                ShelfBalanceCard(balance: balance, sentence: model.balanceSentence, averages: model.averages)
                    .ledgerListRow()
            }
        }
        .listStyle(.plain)
        .larderList()
        .accessibilityRotor(LedgerCopy.daysRotor) {
            ForEach(model.days) { day in
                AccessibilityRotorEntry(Text(Self.spokenDay(day.date)), id: day.id, in: dayRotor)
            }
        }
        .larderAnimation(LarderMotion.layout, value: model.meals)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.m) {
            if model.isPlanning {
                HStack(spacing: LarderSpacing.s) {
                    ProgressView()
                    Text(LedgerCopy.planning)
                        .font(LarderFont.body(.body))
                        .foregroundStyle(LarderColor.ink.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityFocused($headingFocused)
            }
            if let error = model.error {
                LedgerNotice(error: error, onDismiss: model.clearError)
            }
            if model.plan == nil, !model.isPlanning {
                EmptyShelf(
                    title: LedgerCopy.noPlanTitle,
                    message: LedgerCopy.noPlanMessage,
                    illustration: .plan,
                    systemImage: "calendar.badge.plus",
                    action: .init(title: Copy.Action.planMyWeek) { Task { await model.planWeek() } }
                )
            }
            if model.plan != nil {
                Button {
                    if model.showsExplanation {
                        model.hideExplanation()
                    } else {
                        Task { await model.requestExplanation() }
                    }
                } label: {
                    Text(LedgerCopy.whyThisWeek)
                }
                .buttonStyle(.larderQuiet)
                .accessibilityValue(model.showsExplanation ? Text(LedgerCopy.shown) : Text(LedgerCopy.hidden))
                .accessibilityFocused($headingFocused)
            }
        }
    }

    private var explanationCard: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: LarderSpacing.m) {
                if model.isExplaining {
                    HStack(spacing: LarderSpacing.s) {
                        ProgressView()
                        Text(LedgerCopy.explaining)
                            .font(LarderFont.body(.body))
                            .foregroundStyle(LarderColor.ink.secondary)
                    }
                    .accessibilityElement(children: .combine)
                } else if let explanation = model.explanation {
                    Text(explanation.summary)
                        .font(LarderFont.body(.body))
                        .foregroundStyle(LarderColor.ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(model.days) { day in
                    ForEach(day.meals) { entry in
                        if let line = model.explanationNote(for: entry.meal) ?? model.reasons(for: entry.meal, limit: 1).first {
                            ReasonLine(text: LedgerCopy.dayNote(day: Self.shortDay(day.date), text: line))
                        }
                    }
                }
            }
        }
    }

    private func dayRow(_ day: LedgerDay) -> some View {
        LedgerRow(day: Self.dayHeading(day.date), isToday: day.isToday) {
            ForEach(Array(day.meals.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Divider().overlay(LarderColor.line.hairline)
                }
                mealLabel(entry)
            }
            ForEach(day.openSlots, id: \.self) { slot in
                OpenSlotLabel(slot: slot) { sheet = .openSlot(day.date, slot) }
            }
        }
        .accessibilityRotorEntry(id: day.id, in: dayRotor)
        .ledgerListRow()
        .swipeActions(edge: .leading) {
            if let meal = day.meals.first?.meal {
                Button(Copy.Action.markCooked, systemImage: "checkmark") { Task { await model.markCooked(meal) } }
                    .tint(LarderColor.accent.second)
            }
        }
        .swipeActions(edge: .trailing) {
            if let meal = day.meals.first?.meal {
                Button(Copy.Action.skip, systemImage: "forward") { Task { await model.skip(meal) } }
                    .tint(LarderColor.ink.secondary)
                Button(Copy.Action.swap, systemImage: "arrow.left.arrow.right") { sheet = .meal(meal.id, swapping: true) }
                    .tint(LarderColor.accent.brand)
            }
        }
    }

    private func mealLabel(_ entry: LedgerMeal) -> some View {
        let meal = entry.meal
        return Button {
            sheet = .meal(meal.id, swapping: false)
        } label: {
            Group {
                if let tag = entry.leftoverTag {
                    TapeLabel(text: tag)
                } else {
                    JarLabel(title: entry.title, minutes: entry.minutes, slot: LedgerCopy.name(of: meal.slot), photoFileName: entry.photoFileName) {
                        StatusPills(meal: meal)
                    }
                }
            }
            .opacity(meal.status == .skipped ? Self.skippedOpacity : 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(Copy.Action.swap, systemImage: "arrow.left.arrow.right") { sheet = .meal(meal.id, swapping: true) }
            Button(Copy.Action.markCooked, systemImage: "checkmark") { Task { await model.markCooked(meal) } }
            Button(Copy.Action.skip, systemImage: "forward") { Task { await model.skip(meal) } }
            Button(meal.isLocked ? LedgerCopy.unlock : LedgerCopy.lock, systemImage: meal.isLocked ? "lock.open" : "lock") {
                Task { meal.isLocked ? await model.unlock(meal) : await model.lock(meal) }
            }
            Button(LedgerCopy.seeRecipe, systemImage: "book") { onOpenRecipe(meal.recipeID) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.leftoverTag ?? [LedgerCopy.name(of: meal.slot), entry.title, Copy.Ledger.spokenMinutes(entry.minutes)].joined(separator: ", "))
        .accessibilityValue(Self.statusWords(meal).joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Copy.Action.swap) { sheet = .meal(meal.id, swapping: true) }
        .accessibilityAction(named: Copy.Action.skip) { Task { await model.skip(meal) } }
        .accessibilityAction(named: Copy.Action.markCooked) { Task { await model.markCooked(meal) } }
        .accessibilityAction(named: meal.isLocked ? LedgerCopy.unlock : LedgerCopy.lock) {
            Task { meal.isLocked ? await model.unlock(meal) : await model.lock(meal) }
        }
        .accessibilityAction(named: LedgerCopy.moveToAnotherDay) { sheet = .meal(meal.id, swapping: false) }
        .accessibilityActions {
            if meal.leftoverOf != nil {
                Button(LedgerCopy.removeLeftover) { Task { await model.removeLeftover(meal) } }
            }
        }
    }

    /// Skipped meals dim; they are never marked as a failure.
    static let skippedOpacity = 0.6

    static func statusWords(_ meal: PlannedMeal) -> [String] {
        var words: [String] = []
        switch meal.status {
        case .cooked: words.append(LedgerCopy.cooked)
        case .skipped: words.append(LedgerCopy.skipped)
        case .planned: break
        }
        if meal.isLocked { words.append(LedgerCopy.locked) }
        return words
    }

    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// The visible day heading, such as "Saturday 17 October".
    static func dayHeading(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    static func spokenDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// The statuses a meal carries, as small badges with icons.
private struct StatusPills: View {
    let meal: PlannedMeal

    var body: some View {
        let cooked = meal.status == .cooked
        let skipped = meal.status == .skipped
        if cooked || skipped || meal.isLocked {
            HStack(spacing: LarderSpacing.xs) {
                if cooked { Pill(LedgerCopy.cooked, systemImage: "checkmark", tone: .second) }
                if skipped { Pill(LedgerCopy.skipped, systemImage: "forward", tone: .neutral) }
                if meal.isLocked { Pill(LedgerCopy.locked, systemImage: "lock", tone: .neutral) }
            }
            .padding(.top, LarderSpacing.xxs)
        }
    }
}

/// A dashed placeholder for a day with no dinner, with a way to choose one.
private struct OpenSlotLabel: View {
    @Environment(\.displayScale) private var displayScale
    let slot: MealType
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: LarderSpacing.m) {
                Image(systemName: "plus")
                    .font(LarderFont.body(.body, weight: .semibold))
                    .foregroundStyle(LarderColor.accent.brand)
                    .frame(width: 44, height: 44)
                    .background(LarderColor.accent.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: LarderRadius.tile, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: LarderSpacing.xxs) {
                    Text(LedgerCopy.pickOne)
                        .font(LarderFont.body(.body, weight: .semibold))
                        .foregroundStyle(LarderColor.accent.brand)
                    Text([LedgerCopy.name(of: slot), LedgerCopy.nothingFits].joined(separator: " \u{B7} "))
                        .font(LarderFont.body(.subheadline))
                        .foregroundStyle(LarderColor.ink.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LedgerCopy.name(of: slot) + ", " + LedgerCopy.nothingFits)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(LedgerCopy.pickOne)
    }
}

private extension View {
    /// A plan list row on the canvas, inset from the edges; the row draws its own card.
    func ledgerListRow() -> some View {
        listRowInsets(EdgeInsets(top: LarderSpacing.s, leading: LarderSpacing.l, bottom: LarderSpacing.s, trailing: LarderSpacing.l))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

#if DEBUG
#Preview("LedgerView") {
    LedgerView(model: PreviewKitchen.ledgerModel(), onOpenRecipe: { _ in })
        .larderTheme()
}

#Preview("LedgerView no plan") {
    LedgerView(model: PreviewKitchen.ledgerModel(withPlan: false), onOpenRecipe: { _ in })
        .larderTheme()
}

#Preview("LedgerView dark") {
    LedgerView(model: PreviewKitchen.ledgerModel(), onOpenRecipe: { _ in })
        .larderTheme()
        .preferredColorScheme(.dark)
}
#endif
