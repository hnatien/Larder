import LarderCore
import LarderDesign
import SwiftUI

/// The pantry tab: an Eat first shelf, then one section per storage location.
public struct ShelvesView: View {
    private let model: ShelvesModel
    private let onOpenAccount: (() -> Void)?
    @State private var isAdding = false

    /// Creates the tab root over a model; `onOpenAccount` adds an Account button to the toolbar.
    public init(model: ShelvesModel, onOpenAccount: (() -> Void)? = nil) {
        self.model = model
        self.onOpenAccount = onOpenAccount
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(Copy.Tab.shelves)
                .toolbar {
                    if let onOpenAccount {
                        ToolbarItem(placement: .navigation) {
                            Button(Copy.Tab.account, systemImage: "gearshape", action: onOpenAccount)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .task { await model.load() }
        .task(id: model.undo?.id) {
            guard model.undo != nil else { return }
            do {
                try await Task.sleep(for: UndoAction.lifetime)
            } catch {
                return
            }
            model.dismissUndo()
        }
        .sheet(isPresented: $isAdding) {
            QuickAddSheet(model: model)
        }
        .onChange(of: model.undo) { _, action in
            if let action {
                AccessibilityNotification.Announcement(ShelvesCopy.removed(action)).post()
            }
        }
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
                        action: .init(title: Copy.Action.addWhatYouHave) { isAdding = true }
                    )
                }
                .padding(LarderSpacing.l)
            }
            .background(LarderColor.surface.canvas)
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if model.error != nil, !isAdding {
                errorBanner
                    .listRowBackground(Color.clear)
            }
            if !model.eatFirst.isEmpty {
                eatFirstShelf
            }
            ForEach(model.shelves, id: \.0) { location, items in
                Section {
                    SectionHeading(ShelvesCopy.name(of: location))
                        .listRowBackground(LarderColor.surface.canvas)
                        .listRowSeparator(.hidden)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(items) { row($0) }
                }
            }
        }
        .listStyle(.plain)
        .larderList()
        .larderAnimation(LarderMotion.tap, value: model.items)
    }

    @ViewBuilder private var errorBanner: some View {
        if let error = model.error, !isAdding {
            ErrorBanner(error: error, onDismiss: model.clearError)
        }
    }

    private var eatFirstShelf: some View {
        Section {
            PaperCard {
                VStack(alignment: .leading, spacing: LarderSpacing.s) {
                    SectionHeading(ShelvesCopy.eatFirst)
                    ForEach(model.eatFirst) { item in
                        Divider().overlay(LarderColor.line.hairline)
                        row(item)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: LarderSpacing.s, leading: LarderSpacing.l, bottom: LarderSpacing.s, trailing: LarderSpacing.l))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func row(_ item: PantryItem) -> some View {
        ShelfRow(
            item: item,
            level: model.freshness(for: item),
            onEat: { Task { await model.eat(item) } },
            onLetGo: { Task { await model.letGo(item) } }
        )
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(LarderColor.line.hairline)
    }

    private var bottomBar: some View {
        VStack(alignment: .trailing, spacing: LarderSpacing.m) {
            if let action = model.undo {
                UndoBar(action: action) { Task { await model.undoRemove() } }
                    .transition(.opacity)
            }
            if !isEmpty {
                FloatingAction(Copy.Action.addWhatYouHave, systemImage: "plus") { isAdding = true }
            }
        }
        .padding(.horizontal, LarderSpacing.l)
        .padding(.bottom, LarderSpacing.s)
        .larderAnimation(LarderMotion.tap, value: model.undo?.id)
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
