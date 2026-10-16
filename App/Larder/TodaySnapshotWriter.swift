import Foundation
import LarderCore
import OSLog
import WidgetKit

/// Writes the Today widget's snapshot after plan changes and asks WidgetKit to reload it.
@MainActor
final class TodaySnapshotWriter {
    private static let logger = Logger(subsystem: "com.larder.Larder", category: "TodaySnapshot")

    private let reader: DinnerReader
    private let dates: any DateProvider
    private let fileURL: URL?
    private var lastWrite: Task<Void, Never>?

    /// Creates a writer; with a `nil` file URL (no App Group container) writing does nothing.
    init(reader: DinnerReader, dates: any DateProvider, fileURL: URL? = TodaySnapshot.fileURL) {
        self.reader = reader
        self.dates = dates
        self.fileURL = fileURL
    }

    /// Rewrites the snapshot from the store; writes run one after another so the newest plan always lands last.
    func write() async {
        let previous = lastWrite
        let task = Task {
            await previous?.value
            await self.writeNow()
        }
        lastWrite = task
        await task.value
    }

    private func writeNow() async {
        guard let fileURL else { return }
        do {
            let snapshot = TodaySnapshot(dinners: try await reader.dinners(from: dates.now))
            try snapshot.write(to: fileURL)
            WidgetCenter.shared.reloadTimelines(ofKind: TodaySnapshot.widgetKind)
        } catch {
            Self.logger.error("Could not write the Today snapshot: \(String(describing: type(of: error)), privacy: .public)")
        }
    }
}
