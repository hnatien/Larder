import Foundation
import GRDB

/// The Larder SQLite store, migrated to the current schema.
public struct LarderDatabase: Sendable {
    let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter) throws {
        try Migrations.migrator.migrate(writer)
        self.writer = writer
    }

    /// A private in-memory database, for tests and previews.
    public static func inMemory() throws -> LarderDatabase {
        do {
            return try LarderDatabase(writer: DatabaseQueue())
        } catch {
            throw PersistenceError.wrapping(error)
        }
    }

    /// A WAL-mode database file at `url`; the parent directory must exist.
    public static func onDisk(at url: URL) throws -> LarderDatabase {
        do {
            return try LarderDatabase(writer: DatabasePool(path: url.path(percentEncoded: false)))
        } catch {
            throw PersistenceError.wrapping(error)
        }
    }

    /// `Application Support/Larder/larder.sqlite`, creating the `Larder` directory if needed.
    public static func defaultURL() throws -> URL {
        let fileManager = FileManager.default
        let directory = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Larder", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "larder.sqlite", directoryHint: .notDirectory)
    }

    /// Deletes every row and table, then recreates the current schema, for "Delete all data".
    public func eraseAll() async throws {
        do {
            try await writer.erase()
            try Migrations.migrator.migrate(writer)
        } catch {
            throw PersistenceError.wrapping(error)
        }
    }

    func read<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T {
        do {
            return try await writer.read(body)
        } catch {
            throw PersistenceError.wrapping(error)
        }
    }

    func write<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T {
        do {
            return try await writer.write(body)
        } catch {
            throw PersistenceError.wrapping(error)
        }
    }
}
