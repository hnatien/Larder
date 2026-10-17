import LarderCore
import LarderDesign
import PhotosUI
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Import from a web address, a photo of a recipe, or by writing it out: preview what was found, then save with the
/// button pinned to the bottom.
public struct ImportSheet: View {
    @Bindable private var model: ImportModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var showsWriteForm = false
    @State private var asksForConsent = false

    /// Creates the sheet over `model`, from `RecipesModel.makeImportModel()`.
    public init(model: ImportModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: LarderSpacing.xl) {
                        if let result = model.preview {
                            PreviewCard(result: result, servings: Binding(get: { result.recipe.servings }, set: { model.setServings($0) }))
                        } else {
                            status { showWriteForm(proxy) }
                            addressField
                            photoSection
                            writeSection
                                .id(Self.writeSectionID)
                        }
                    }
                    .padding(LarderSpacing.l)
                }
                .background(LarderColor.surface.canvas)
            }
            .safeAreaInset(edge: .bottom) {
                if model.preview != nil || model.phase == .saving {
                    actions
                        .padding(.horizontal, LarderSpacing.l)
                        .padding(.vertical, LarderSpacing.s)
                        .background(LarderColor.surface.canvas)
                }
            }
            .navigationTitle(RecipesCopy.importTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .onChange(of: model.phase) { _, phase in
                switch phase {
                case .saved:
                    dismiss()
                case .failed(let error):
                    AccessibilityNotification.Announcement(RecipesCopy.message(for: error)).post()
                case .preview(let result):
                    AccessibilityNotification.Announcement(RecipesCopy.found(result.recipe.title)).post()
                case .idle, .loading, .readingPhoto, .saving:
                    break
                }
            }
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                pickedPhoto = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        model.photoUnavailable()
                        return
                    }
                    await model.readPhoto(data)
                }
            }
            .sheet(isPresented: $asksForConsent) {
                AIConsentSheet {
                    asksForConsent = false
                    Task { await model.allowAIAndRetry() }
                } onDecline: {
                    asksForConsent = false
                }
                .presentationDetents([.medium, .large])
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showsCamera) {
                CameraCapture { data in
                    showsCamera = false
                    if let data { Task { await model.readPhoto(data) } }
                }
                .ignoresSafeArea()
            }
            #endif
        }
    }

    private static let writeSectionID = "write"

    private func showWriteForm(_ proxy: ScrollViewProxy) {
        showsWriteForm = true
        withAnimation(LarderMotion.layout) { proxy.scrollTo(Self.writeSectionID, anchor: .top) }
    }

    /// Writing the recipe out: free, on this device, and always there when a page or photo cannot be read.
    private var writeSection: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.m) {
            Button {
                showsWriteForm.toggle()
            } label: {
                HStack {
                    SectionHeading(RecipesCopy.writeItTitle)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showsWriteForm ? 180 : 0))
                        .foregroundStyle(LarderColor.ink.secondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsWriteForm ? RecipesCopy.shown : RecipesCopy.hidden)
            Text(RecipesCopy.writeItHint)
                .font(LarderFont.body(.footnote))
                .foregroundStyle(LarderColor.ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if showsWriteForm {
                field(RecipesCopy.recipeTitle, text: $model.writtenTitle, lines: 1...2)
                field(RecipesCopy.ingredientLines, text: $model.writtenIngredients, lines: 4...12)
                field(RecipesCopy.stepLines, text: $model.writtenSteps, lines: 4...12)
                LabeledContent(RecipesCopy.totalMinutes) {
                    TextField(RecipesCopy.totalMinutes, value: $model.writtenMinutes, format: .number)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.primary)
                .frame(minHeight: 44)
                Button(RecipesCopy.previewWritten) {
                    Task { await model.readWritten() }
                }
                .buttonStyle(.larderPrimary)
                .disabled(!model.canReadWritten || model.isBusy)
            }
        }
        .larderAnimation(LarderMotion.layout, value: showsWriteForm)
    }

    private func field(_ title: String, text: Binding<String>, lines: ClosedRange<Int>) -> some View {
        TextField(title, text: text, prompt: Text(title).foregroundStyle(LarderColor.ink.tertiary), axis: .vertical)
            .lineLimit(lines)
            .font(LarderFont.body(.body))
            .foregroundStyle(LarderColor.ink.primary)
            .padding(LarderSpacing.m)
            .frame(minHeight: 44)
            .background(LarderColor.surface.raised, in: RoundedRectangle(cornerRadius: LarderRadius.field))
            .overlay {
                RoundedRectangle(cornerRadius: LarderRadius.field)
                    .strokeBorder(LarderColor.line.strong, lineWidth: 1)
            }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.m) {
            SectionHeading(RecipesCopy.fromPhoto)
            Text(RecipesCopy.fromPhotoHint)
                .font(LarderFont.body(.footnote))
                .foregroundStyle(LarderColor.ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            AdaptiveStack(spacing: LarderSpacing.m) {
                #if os(iOS)
                if CameraCapture.isAvailable {
                    Button(RecipesCopy.takePhoto) { showsCamera = true }
                        .buttonStyle(.larderSecondary)
                }
                #endif
                PhotosPicker(RecipesCopy.choosePhoto, selection: $pickedPhoto, matching: .images, photoLibrary: .shared())
                    .buttonStyle(.larderSecondary)
            }
            .disabled(model.isBusy)
        }
    }

    private var addressField: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.m) {
            SectionHeading(RecipesCopy.fromAddress)
            TextField(RecipesCopy.address, text: $model.addressText)
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.primary)
                .padding(LarderSpacing.m)
                .frame(minHeight: 44)
                .background(LarderColor.surface.raised, in: RoundedRectangle(cornerRadius: LarderRadius.field))
                .overlay {
                    RoundedRectangle(cornerRadius: LarderRadius.field)
                        .strokeBorder(LarderColor.line.strong, lineWidth: 1)
                }
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .submitLabel(.go)
                .onSubmit { Task { await model.fetchPreview() } }
            AdaptiveStack(spacing: LarderSpacing.m) { fieldButtons }
        }
    }

    @ViewBuilder private var fieldButtons: some View {
        PasteButton(payloadType: String.self) { strings in
            if let pasted = strings.first { model.addressText = pasted }
        }
        .frame(minHeight: 44)
        Button(RecipesCopy.readPage) {
            Task { await model.fetchPreview() }
        }
        .buttonStyle(.larderPrimary)
        .disabled(model.addressText.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
    }

    /// Progress, or what went wrong with a way on: every failure but a written one offers to write the recipe out.
    @ViewBuilder private func status(onWrite: @escaping () -> Void) -> some View {
        switch model.phase {
        case .loading:
            ProgressView(RecipesCopy.readingPage)
        case .readingPhoto:
            ProgressView(RecipesCopy.readingPhoto)
        case .failed(let error):
            InlineBanner(
                RecipesCopy.message(for: error),
                action: model.canAllowAI
                    ? .init(title: Copy.Consent.allow) { asksForConsent = true }
                    : error == .noWrittenRecipe ? nil : .init(title: RecipesCopy.writeItTitle, perform: onWrite)
            )
        case .saving:
            ProgressView()
        case .idle, .preview, .saved:
            EmptyView()
        }
    }

    private var actions: some View {
        AdaptiveStack(spacing: LarderSpacing.s, stacksFrom: .xLarge) {
            Button {
                Task { await model.save() }
            } label: {
                Text(RecipesCopy.save).frame(maxWidth: .infinity)
            }
            .buttonStyle(.larderPrimary)
            .disabled(model.phase == .saving)
            Button(RecipesCopy.startOver) { model.reset() }
                .buttonStyle(.larderQuiet)
                .disabled(model.phase == .saving)
        }
    }
}

/// What was found on the page, shown before anything is saved: the photo when the page has one, and the first steps
/// with the rest a tap away, so Save stays close.
private struct PreviewCard: View {
    /// Steps shown before "Show every step".
    static let stepsShown = 3

    let result: ImportResult
    @Binding var servings: Int
    @State private var showsAllSteps = false

    private var steps: [RecipeStep] {
        showsAllSteps ? result.recipe.steps : Array(result.recipe.steps.prefix(Self.stepsShown))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.l) {
            #if os(iOS)
            if let data = result.photo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: LarderRadius.panel, style: .continuous))
                    .accessibilityHidden(true)
            }
            #endif
            Text(result.recipe.title)
                .font(LarderFont.display(.title))
                .foregroundStyle(LarderColor.ink.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Stamp(text: Copy.Ledger.minutes(result.recipe.prepMinutes + result.recipe.cookMinutes))
            switch result.source {
            case .assistant: ReasonLine(text: RecipesCopy.assistantNote)
            case .photo: ReasonLine(text: RecipesCopy.photoNote)
            case .written: ReasonLine(text: RecipesCopy.writtenNote)
            case .structuredData: EmptyView()
            }
            Stepper(value: $servings, in: 1...RecipeDetailView.maximumServings) {
                HStack {
                    Text(RecipesCopy.servings)
                    Spacer()
                    Text(servings, format: .number)
                        .font(LarderFont.mono(.body))
                }
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.primary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(RecipesCopy.servings)
                .accessibilityValue(RecipesCopy.spokenServings(servings))
            }
            SectionHeading(RecipesCopy.ingredients)
            ForEach(result.ingredients) { ingredient in
                Text(ingredient.rawText)
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            SectionHeading(RecipesCopy.method)
            ForEach(Array(steps.enumerated()), id: \.offset) { offset, step in
                Text(RecipesCopy.numberedStep(offset + 1, text: step.text))
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if result.recipe.steps.count > Self.stepsShown, !showsAllSteps {
                Button(RecipesCopy.showAllSteps) { showsAllSteps = true }
                    .buttonStyle(.larderQuiet)
            }
        }
    }
}

#if DEBUG
#Preview("ImportSheet") {
    ImportSheet(model: PreviewData.model().makeImportModel())
}
#endif
