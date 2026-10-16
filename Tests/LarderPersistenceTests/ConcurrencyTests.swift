import Foundation
import GRDB
import LarderCore
import Testing
@testable import LarderPersistence

struct ConcurrencyTests {
    @Test(.timeLimit(.minutes(1)))
    func readsWhileWritingOnAFilePoolDoNotDeadlock() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "larder-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(filePath: url.path(percentEncoded: false) + suffix))
            }
        }
        let database = try LarderDatabase.onDisk(at: url)
        let journalMode = try await database.writer.read { db in try String.fetchOne(db, sql: "PRAGMA journal_mode") }
        #expect(journalMode == "wal")

        let foods = GRDBFoodRepository(database: database)
        let batches = 40
        let readCounts = try await withThrowingTaskGroup(of: [Int].self) { group in
            group.addTask {
                for batch in 0..<batches {
                    try await foods.upsert((0..<10).map { Fixtures.food("Bean \(batch)-\($0)") })
                }
                return []
            }
            for _ in 0..<4 {
                group.addTask {
                    var counts: [Int] = []
                    for _ in 0..<batches {
                        counts.append(try await foods.search(text: "bean", limit: 1000).count)
                    }
                    return counts
                }
            }
            var all: [[Int]] = []
            for try await counts in group where !counts.isEmpty {
                all.append(counts)
            }
            return all
        }

        #expect(readCounts.count == 4)
        for counts in readCounts {
            #expect(counts == counts.sorted())
            #expect(counts.allSatisfy { $0.isMultiple(of: 10) })
        }
        #expect(try await foods.search(text: "bean", limit: 1000).count == batches * 10)
    }

    @Test func openingAFileInAMissingDirectoryFails() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "larder-missing-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "larder.sqlite")
        do {
            _ = try LarderDatabase.onDisk(at: url)
            Issue.record("Opening a database in a missing directory succeeded")
        } catch LarderPersistence.PersistenceError.database(let databaseError) {
            #expect(databaseError.resultCode == .SQLITE_CANTOPEN)
        }
    }
}
