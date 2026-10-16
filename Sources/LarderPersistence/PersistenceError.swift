import Foundation
import GRDB
import LarderCore

/// Errors the GRDB repositories throw; the UI maps them to `LarderError` through `larderError`.
public enum PersistenceError: Error {
    /// SQLite or GRDB failed to read or write.
    case database(DatabaseError)
    /// A value could not be encoded to, or decoded from, its stored form.
    case encoding(any Error)
    /// The record to update does not exist.
    case notFound

    /// The cross-module error the UI shows for this failure.
    public var larderError: LarderError {
        switch self {
        case .database, .encoding: .storageFailure
        case .notFound: .notFound
        }
    }

    /// Wraps any error raised inside a database access; cancellation passes through unchanged.
    static func wrapping(_ error: any Error) -> any Error {
        switch error {
        case let error as PersistenceError: error
        case let error as DatabaseError: PersistenceError.database(error)
        case RecordError.recordNotFound: PersistenceError.notFound
        case is CancellationError: error
        default: PersistenceError.encoding(error)
        }
    }
}
