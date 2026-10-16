import Foundation
import LarderCore
import Testing
@testable import LarderPersistence

struct RecipePhotoStoreTests {
    let directory: URL
    let store: FileRecipePhotoStore

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "RecipePhotoStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = FileRecipePhotoStore(directory: directory)
    }

    private func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
    }

    @Test func saveCreatesTheDirectoryAndNamesTheFileAfterTheRecipe() async throws {
        let id = RecipeID()
        let fileName = try await store.save(Data([1, 2, 3]), for: id)
        #expect(fileName == id.rawValue.uuidString + ".jpg")
        #expect(try Data(contentsOf: directory.appending(path: fileName)) == Data([1, 2, 3]))
        try store.deleteAll()
    }

    @Test func savingAgainReplacesThePhoto() async throws {
        let id = RecipeID()
        _ = try await store.save(Data([1]), for: id)
        let fileName = try await store.save(Data([2]), for: id)
        #expect(try contents() == [fileName])
        #expect(try Data(contentsOf: directory.appending(path: fileName)) == Data([2]))
        try store.deleteAll()
    }

    @Test func deleteRemovesOneFileAndToleratesAMissingOne() async throws {
        let kept = try await store.save(Data([1]), for: RecipeID())
        let removed = try await store.save(Data([2]), for: RecipeID())
        try await store.delete(removed)
        try await store.delete(removed)
        #expect(try contents() == [kept])
        try store.deleteAll()
    }

    @Test func deleteAllRemovesEveryPhotoAndToleratesNoDirectory() async throws {
        _ = try await store.save(Data([1]), for: RecipeID())
        try store.deleteAll()
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
        try store.deleteAll()
        _ = try await store.save(Data([2]), for: RecipeID())
        #expect(try contents().count == 1)
        try store.deleteAll()
    }

    @Test func namesThatLeaveTheDirectoryAreRefused() async throws {
        let outside = directory.deletingLastPathComponent().appending(path: "outside-\(UUID().uuidString).jpg")
        try Data([9]).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        for name in ["../" + outside.lastPathComponent, "a/b.jpg", "..", ".", ""] {
            await #expect(throws: CocoaError.self) { try await store.delete(name) }
        }
        #expect(FileManager.default.fileExists(atPath: outside.path(percentEncoded: false)))
    }
}

