import LarderCore
import LarderDesign
import PhotosUI
import SwiftUI

/// Import from a web address or a photo of a recipe: preview what was found, then save.
public struct ImportSheet: View {
    @Bindable private var model: ImportModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showsCamera = false

    /// Creates the sheet over `model`, from `RecipesModel.makeImportModel()`.
    public init(model: ImportModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LarderSpacing.xl) {
                    addressField
                    photoSection
                    status
                    if let result = model.preview {
                        PreviewCard(result: result, servings: Binding(get: { result.recipe.servings }, set: { model.setServings($0) }))
                        actions
                    }
                }
                .padding(LarderSpacing.l)
            }
            .background(LarderColor.surface.canvas)
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

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .loading:
            ProgressView(RecipesCopy.readingPage)
        case .readingPhoto:
            ProgressView(RecipesCopy.readingPhoto)
        case .failed(let error):
            Label(RecipesCopy.message(for: error), systemImage: "exclamationmark.triangle.fill")
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.status(.danger))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        case .saving:
            ProgressView()
        case .idle, .preview, .saved:
            EmptyView()
        }
    }

    private var actions: some View {
        VStack(spacing: LarderSpacing.m) {
            Button {
                Task { await model.save() }
            } label: {
                Text(RecipesCopy.save).frame(maxWidth: .infinity)
            }
            .buttonStyle(.larderPrimary)
            Button {
                model.reset()
            } label: {
                Text(RecipesCopy.startOver).frame(maxWidth: .infinity)
            }
            .buttonStyle(.larderSecondary)
        }
    }
}

/// What was found on the page, shown before anything is saved.
private struct PreviewCard: View {
    let result: ImportResult
    @Binding var servings: Int

    var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.l) {
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
            ForEach(Array(result.recipe.steps.enumerated()), id: \.offset) { offset, step in
                Text(RecipesCopy.numberedStep(offset + 1, text: step.text))
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#if DEBUG
#Preview("ImportSheet") {
    ImportSheet(model: PreviewData.model().makeImportModel())
}
#endif
