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

/// The week as a ledger: a row per day, a jar label per meal, a tape label per leftover, and the week's shelf.
public struct LedgerView: View {
    private let model: LedgerModel
    private let onOpenRecipe: (RecipeID) -> Void
    private let onShowPaywall: () -> Void
    private let onOpenAccount: (() -> Void)?
    @State private var sheet: LedgerSheet?
    @AccessibilityFocusState private var headingFocused: Bool
    @Namespace private var dayRotor

    /// Creates the tab root; `onShowPaywall` runs when a free user has no free week left, and `onOpenAccount`
    /// adds an Account button to the toolbar.
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
                .toolbar {
                    if let onOpenAccount {
                        ToolbarItem(placement: .navigation) {
                            Button(Copy.Tab.account, systemImage: "gearshape", action: onOpenAccount)
                        }
                    }
                    if model.plan != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button(LedgerCopy.replan) {
                                Task { await model.replan(keepingLocked: true) }
                            }
                            .disabled(model.isPlanning)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if model.plan == nil, !model.isPlanning {
                        FloatingAction(Copy.Action.planMyWeek, systemImage: "calendar") {
                            Task { await model.planWeek() }
                        }
                        .padding(.bottom, LarderSpacing.s)
                    }
                }
        }
        .task { await model.load() }
        .sheet(item: $sheet) { target in
            MealSheet(model: model, target: target, onOpenRecipe: onOpenRecipe)
        }
        .onChange(of: model.paywallRequested) { _, requested in
            guard requested else { return }
            model.paywallRequested = false
            onShowPaywall()
        }
        .onChange(of: model.savedPlanCount) {
            AccessibilityNotification.Announcement(Copy.Voice.planSaved).post()
            headingFocused = true
        }
    }

    private var list: some View {
        List {
            header
                .ledgerListRow()
            if model.showsExplanation, model.plan != nil {
                explanationCard
                    .ledgerListRow(horizontal: LarderSpacing.l)
            }
            ForEach(model.days) { day in
                dayRow(day)
            }
            if let balance = model.shelfBalance, !balance.levels.isEmpty {
                ShelfBalanceCard(balance: balance, sentence: model.balanceSentence, averages: model.averages)
                    .ledgerListRow(horizontal: LarderSpacing.l)
            }
        }
        .listStyle(.plain)
        .larderList()
        .accessibilityRotor("Days") {
            ForEach(model.days) { day in
                AccessibilityRotorEntry(Text(Self.spokenDay(day.date)), id: day.id, in: dayRotor)
            }
        }
        .larderAnimation(LarderMotion.layout, value: model.meals)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.m) {
            Text(Copy.Tab.ledger)
                .font(LarderFont.display(.largeTitle))
                .foregroundStyle(LarderColor.ink.primary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
            if model.isPlanning {
                HStack(spacing: LarderSpacing.s) {
                    ProgressView()
                    Text(LedgerCopy.planning)
                        .font(LarderFont.body(.body))
                        .foregroundStyle(LarderColor.ink.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if let error = model.error {
                LedgerNotice(error: error, onDismiss: model.clearError)
            }
            if model.plan == nil, !model.isPlanning {
                EmptyShelf(title: LedgerCopy.noPlanTitle, message: LedgerCopy.noPlanMessage)
            }
            if model.plan != nil {
                Button(LedgerCopy.whyThisWeek) {
                    if model.showsExplanation {
                        model.hideExplanation()
                    } else {
                        Task { await model.requestExplanation() }
                    }
                }
                .buttonStyle(.larderQuiet)
                .accessibilityValue(model.showsExplanation ? Text(LedgerCopy.shown) : Text(LedgerCopy.hidden))
            }
        }
        .padding(.horizontal, LarderSpacing.l)
        .padding(.top, LarderSpacing.s)
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
        LedgerRow(day: Self.shortDay(day.date), isToday: day.isToday) {
            ForEach(day.meals) { entry in
                mealLabel(entry, isToday: day.isToday)
            }
            ForEach(day.openSlots, id: \.self) { slot in
                OpenSlotLabel(slot: slot) { sheet = .openSlot(day.date, slot) }
            }
        }
        .accessibilityRotorEntry(id: day.id, in: dayRotor)
        .ledgerListRow()
        .swipeActions(edge: .leading) {
            if let meal = day.meals.first?.meal {
                Button(Copy.Action.markCooked) { Task { await model.markCooked(meal) } }
                    .tint(LarderColor.accent.second)
            }
        }
        .swipeActions(edge: .trailing) {
            if let meal = day.meals.first?.meal {
                Button(Copy.Action.skip) { Task { await model.skip(meal) } }
                    .tint(LarderColor.ink.secondary)
                Button(Copy.Action.swap) { sheet = .meal(meal.id, swapping: true) }
                    .tint(LarderColor.accent.second)
            }
        }
    }

    private func mealLabel(_ entry: LedgerMeal, isToday: Bool) -> some View {
        let meal = entry.meal
        return Button {
            sheet = .meal(meal.id, swapping: false)
        } label: {
            VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                if let tag = entry.leftoverTag {
                    TapeLabel(text: tag)
                } else {
                    JarLabel(
                        title: entry.title,
                        minutes: entry.minutes,
                        tone: meal.isLocked ? .second : isToday ? .brand : .ink,
                        slot: LedgerCopy.name(of: meal.slot)
                    )
                }
                if !Self.statusWords(meal).isEmpty {
                    Text(Self.statusWords(meal).joined(separator: " \u{B7} "))
                        .stamp()
                        .foregroundStyle(LarderColor.ink.secondary)
                }
            }
            .opacity(meal.status == .skipped ? Self.skippedOpacity : 1)
        }
        .buttonStyle(.plain)
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

    static func spokenDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// A quiet placeholder for a slot nothing fits yet, with a way to pick one.
private struct OpenSlotLabel: View {
    @Environment(\.displayScale) private var displayScale
    let slot: MealType
    let onPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.xxs) {
            Text(LedgerCopy.name(of: slot))
                .stamp()
                .foregroundStyle(LarderColor.ink.secondary)
            Text(LedgerCopy.nothingFits)
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(LedgerCopy.pickOne, action: onPick)
                .buttonStyle(.larderQuiet)
        }
        .padding(.horizontal, LarderSpacing.s)
        .padding(.vertical, LarderSpacing.xs)
        .overlay {
            RoundedRectangle(cornerRadius: LarderRadius.stamp)
                .strokeBorder(LarderColor.line.strong, style: StrokeStyle(lineWidth: 1 / displayScale, dash: [4, 3]))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }
}

private extension View {
    /// A ledger list row: edge to edge on the canvas, with the row drawing its own hairline.
    func ledgerListRow(horizontal: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: LarderSpacing.s, leading: horizontal, bottom: LarderSpacing.s, trailing: horizontal))
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
