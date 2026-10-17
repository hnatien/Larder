#if os(iOS)
import LarderDesign
import PhotosUI
import SwiftUI
import VisionKit

/// What the scanner looks for.
enum ScanMode: Hashable, CaseIterable {
    case barcode
    case receipt
}

/// The live camera scanner for Add food: barcodes add a line each as they come into view; a receipt is read from a
/// still. Every result lands in the Add food list for checking. Without a usable camera, a photo can be chosen instead.
struct PantryScannerSheet: View {
    @Bindable var model: ShelvesModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode = ScanMode.barcode
    @State private var camera = ScannerCamera()
    @State private var pickedPhoto: PhotosPickerItem?

    private var modes: [ScanMode] { model.canReadReceipts ? ScanMode.allCases : [.barcode] }
    private var showsLiveScanner: Bool { LiveScanner.isUsable && !camera.failedToStart }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LarderSpacing.l) {
                    if modes.count > 1 {
                        Picker(ShelvesCopy.scanMode, selection: $mode) {
                            Text(ShelvesCopy.barcode).tag(ScanMode.barcode)
                            Text(ShelvesCopy.receipt).tag(ScanMode.receipt)
                        }
                        .pickerStyle(.segmented)
                    }
                    Text(mode == .barcode ? ShelvesCopy.barcodeHint : ShelvesCopy.receiptHint)
                        .font(LarderFont.body(.body))
                        .foregroundStyle(LarderColor.ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    viewfinder
                    status
                    actions
                }
                .padding(LarderSpacing.l)
            }
            .background(LarderColor.surface.canvas)
            .navigationTitle(ShelvesCopy.scannerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                await read(data)
            }
        }
        .onChange(of: mode) { model.clearScanNotice() }
        .onChange(of: model.lastScannedName) { _, name in
            if let name { AccessibilityNotification.Announcement(ShelvesCopy.scanned(name)).post() }
        }
        .onChange(of: model.scanNotice) { _, notice in
            if let notice { AccessibilityNotification.Announcement(ShelvesCopy.message(for: notice)).post() }
        }
        .sensoryFeedback(.success, trigger: model.pendingLines.count) { old, new in new > old }
    }

    @ViewBuilder private var viewfinder: some View {
        if showsLiveScanner {
            LiveScanner(mode: mode, camera: camera) { code in
                Task { await model.addBarcode(code) }
            }
            .id(mode)
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: LarderRadius.panel, style: .continuous))
            .accessibilityHidden(true)
        } else {
            Label {
                Text(ShelvesCopy.scannerUnavailable)
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "camera")
                    .foregroundStyle(LarderColor.status(.info))
            }
        }
    }

    @ViewBuilder private var status: some View {
        if model.isParsing {
            HStack(spacing: LarderSpacing.s) {
                ProgressView()
                Text(ShelvesCopy.readingReceipt)
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        if let notice = model.scanNotice {
            Label {
                Text(ShelvesCopy.message(for: notice))
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(LarderColor.status(.info))
            }
        } else if let error = model.error {
            ErrorBanner(error: error, onDismiss: model.clearError)
        }
        if !model.pendingLines.isEmpty {
            Text(ShelvesCopy.waiting(model.pendingLines.count))
                .font(LarderFont.body(.subheadline, weight: .semibold))
                .foregroundStyle(LarderColor.ink.secondary)
        }
    }

    private var actions: some View {
        VStack(spacing: LarderSpacing.m) {
            if mode == .receipt, showsLiveScanner {
                Button {
                    Task {
                        guard let data = await camera.capture() else { return }
                        await model.readReceipt(data)
                    }
                } label: {
                    Text(ShelvesCopy.readReceipt)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.larderPrimary)
                .disabled(model.isParsing)
            }
            if mode == .receipt || model.canReadBarcodePhotos {
                PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                    Text(ShelvesCopy.choosePhoto)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.larderSecondary)
                .disabled(model.isParsing)
            }
        }
    }

    private func read(_ data: Data) async {
        switch mode {
        case .barcode: await model.readBarcodes(inPhoto: data)
        case .receipt: await model.readReceipt(data)
        }
    }
}

/// Holds the running scanner so a button outside it can take a still.
@Observable
final class ScannerCamera {
    @ObservationIgnored weak var scanner: DataScannerViewController?
    /// Whether the camera refused to start, for example because access was turned off in Settings.
    var failedToStart = false

    /// A JPEG still from the camera, or `nil` when there is no running scanner or the capture failed.
    func capture() async -> Data? {
        guard let scanner, scanner.isScanning else { return nil }
        do {
            return try await scanner.capturePhoto().jpegData(compressionQuality: 0.9)
        } catch {
            return nil
        }
    }
}

/// `DataScannerViewController` showing barcodes or receipt text, reporting each new barcode once it is recognised.
private struct LiveScanner: UIViewControllerRepresentable {
    let mode: ScanMode
    let camera: ScannerCamera
    let onBarcode: (String) -> Void

    /// Whether this device has a scanner and the camera may be used.
    static var isUsable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let types: Set<DataScannerViewController.RecognizedDataType> = switch mode {
        case .barcode: [.barcode(symbologies: [.ean13, .ean8, .upce])]
        case .receipt: [.text()]
        }
        let scanner = DataScannerViewController(
            recognizedDataTypes: types,
            qualityLevel: mode == .receipt ? .accurate : .balanced,
            recognizesMultipleItems: mode == .receipt,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        camera.scanner = scanner
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !scanner.isScanning else { return }
        do {
            try scanner.startScanning()
        } catch {
            Task { @MainActor in camera.failedToStart = true }
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onBarcode: onBarcode)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onBarcode: (String) -> Void

        init(onBarcode: @escaping (String) -> Void) {
            self.onBarcode = onBarcode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in addedItems {
                if let payload = barcode.payloadStringValue { onBarcode(payload) }
            }
        }
    }
}
#endif
