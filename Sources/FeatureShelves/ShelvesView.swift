import LarderCore
import LarderDesign
import SwiftUI

/// The Pantry tab: a Use soon list, then one section per storage place. Search narrows both; + adds food.
public struct ShelvesView: View {
    @Bindable private var model: ShelvesModel
    private let onOpenAccount: (() -> Void)?
    @Binding private var isAdding: Bool
    @State private var editing: PantryItem?

    /// Creates the tab root over a model; `isAdding` presents the Add food sheet, and `onOpenAccount` adds the
    /// Settings button to the toolbar.
    public init(model: ShelvesModel, isAdding: Binding<Bool> = .constant(false), onOpenAccount: (() -> Void)? = nil) {
        self.model = model
        self._isAdding = isAdding
        self.onOpenAccount = onOpenAccount
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(Copy.Tab.shelves)
                .navigationSubtitle(ShelvesCopy.subtitle)
                .settingsButton(onOpenAccount)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(Copy.Action.addFood, systemImage: "plus") { isAdding = true }
                    }
                }
                .larderToast(toast, onExpire: model.dismissUndo)
        }
        .task { await model.load() }
        .sheet(isPresented: $isAdding) {
            QuickAddSheet(model: model)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editing) { item in
            ShelfItemEditor(model: model, item: item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.success, trigger: model.undo?.id) { _, new in new != nil }
        .onChange(of: model.error) { _, error in
            if let error, !isAdding {
                AccessibilityNotification.Announcement(ShelvesCopy.message(for: error)).post()
            }
        }
    }

    private var isEmpty: Bool { model.items.isEmpty && !model.isLoading }

    @ViewBuilder private var content: some View {
        if isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: LarderSpacing.l) {
                    errorBanner
                    EmptyShelf(
                        title: ShelvesCopy.emptyTitle,
                        message: Copy.Voice.emptyPantry,
                        illustration: .pantry,
                        systemImage: "refrigerator",
                        action: .init(title: Copy.Action.addWhatYouHave) { isAdding = true }
                    )
                }
                .padding(LarderSpacing.l)
            }
            .background(LarderColor.surface.canvas)
        } else {
            list
                .searchable(text: $model.searchText, prompt: ShelvesCopy.searchPrompt)
        }
    }

    private var list: some View {
        List {
            if model.error != nil, !isAdding {
                errorBanner
                    .listRowBackground(Color.clear)
            }
            if !model.eatFirst.isEmpty {
                Section {
                    sectionHeader(ShelvesCopy.eatFirst, detail: ShelvesCopy.eatFirstDetail, systemImage: "clock")
                    ForEach(model.eatFirst) { row($0, showsLocation: true) }
                }
            }
            ForEach(model.shelves, id: \.0) { location, items in
                Section {
                    sectionHeader(ShelvesCopy.name(of: location), detail: nil, systemImage: Self.symbol(for: location))
                    ForEach(items) { row($0) }
                }
            }
            if model.eatFirst.isEmpty, model.shelves.isEmpty, !model.searchText.isEmpty {
                Text(ShelvesCopy.noMatches)
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .larderGroupedList()
        .larderAnimation(LarderMotion.tap, value: model.items)
    }

    /// A section's heading, drawn as its first row; List section headers are reported by the accessibility audit as
    /// only partly supporting Dynamic Type.
    private func sectionHeader(_ title: String, detail: String?, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LarderSpacing.s) {
            Image(systemName: systemImage)
                .font(LarderFont.body(.headline, weight: .semibold))
                .foregroundStyle(LarderColor.accent.brand)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LarderSpacing.xxs) {
                Text(title)
                    .font(LarderFont.body(.headline, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(LarderFont.body(.footnote))
                        .foregroundStyle(LarderColor.ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .listRowBackground(LarderColor.surface.raised)
        .listRowSeparator(.hidden, edges: .top)
    }

    static func symbol(for location: StorageLocation) -> String {
        switch location {
        case .fridge: "refrigerator"
        case .freezer: "snowflake"
        case .pantry: "cabinet"
        case .other: "basket"
        }
    }

    @ViewBuilder private var errorBanner: some View {
        if let error = model.error, !isAdding {
            ErrorBanner(error: error, onDismiss: model.clearError)
        }
    }

    private func row(_ item: PantryItem, showsLocation: Bool = false) -> some View {
        ShelfRow(
            item: item,
            quantity: model.quantityText(for: item),
            level: model.freshness(for: item),
            showsLocation: showsLocation,
            onEdit: { editing = item },
            onEat: { Task { await model.eat(item) } },
            onLetGo: { Task { await model.letGo(item) } }
        )
        .listRowBackground(LarderColor.surface.raised)
        .listRowSeparatorTint(LarderColor.line.hairline)
        .listRowInsets(EdgeInsets(top: LarderSpacing.xs, leading: LarderSpacing.l, bottom: LarderSpacing.xs, trailing: LarderSpacing.l))
    }

    /// The last removal, with Undo.
    private var toast: LarderToast? {
        model.undo.map { action in
            LarderToast(
                id: action.id,
                ShelvesCopy.removed(action),
                systemImage: action.kind == .eaten ? "checkmark.circle.fill" : "trash.circle.fill",
                actionTitle: ShelvesCopy.undo
            ) {
                Task { await model.undoRemove() }
            }
        }
    }
}

#if DEBUG
#Preview("ShelvesView") {
    ShelvesView(model: PreviewData.model(items: PreviewData.items()))
        .larderTheme()
}

#Preview("ShelvesView empty") {
    ShelvesView(model: PreviewData.model())
        .larderTheme()
}
#endif
