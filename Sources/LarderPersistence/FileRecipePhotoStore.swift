import Foundation
import LarderCore

/// Recipe photos as JPEG files in one directory, named after the recipe so a new photo replaces the old one.
public struct FileRecipePhotoStore: RecipePhotoStore {
    /// The directory the photos live in; views resolve a recipe's `photoFileName` against it.
    public let directory: URL

    /// A store over `directory`, which is created on the first save.
    public init(directory: URL) {
        self.directory = directory
    }

    /// `Application Support/Larder/RecipePhotos`, next to the database.
    public static func defaultDirectory() throws -> URL {
        try LarderDatabase.defaultURL()
            .deletingLastPathComponent()
            .appending(path: "RecipePhotos", directoryHint: .isDirectory)
    }

    public func save(_ jpeg: Data, for recipeID: RecipeID) async throws -> String {
        let fileName = recipeID.rawValue.uuidString + ".jpg"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpeg.write(to: try url(for: fileName), options: .atomic)
        return fileName
    }

    public func delete(_ fileName: String) async throws {
        do {
            try FileManager.default.removeItem(at: try url(for: fileName))
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    /// Deletes every photo, for "Delete all data".
    public func deleteAll() throws {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    /// The file for `fileName`; throws for a name that is not a single file in the directory.
    func url(for fileName: String) throws -> URL {
        guard Self.isPlainFileName(fileName) else { throw CocoaError(.fileWriteInvalidFileName) }
        return directory.appending(path: fileName, directoryHint: .notDirectory)
    }

    /// Whether `fileName` names a file directly inside a directory: no separators, no `.` or `..`.
    static func isPlainFileName(_ fileName: String) -> Bool {
        !fileName.isEmpty && fileName != "." && fileName != ".." && !fileName.contains("/") && !fileName.contains("\0")
    }
}
