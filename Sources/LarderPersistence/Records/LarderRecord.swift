import Foundation
import GRDB
import LarderCore

/// A GRDB record of the Larder schema: UUIDs stored as uppercase text, JSON columns with ISO 8601 dates and sorted keys.
protocol LarderRecord: Codable, FetchableRecord, PersistableRecord {}

extension LarderRecord {
    static func databaseJSONEncoder(for column: String) -> JSONEncoder { RecordCoding.encoder }
    static func databaseJSONDecoder(for column: String) -> JSONDecoder { RecordCoding.decoder }
    static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .uppercaseString }
}

enum RecordCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// A stored value that cannot be turned back into its domain type.
struct InvalidStoredValue: Error, Hashable {
    let column: String
    let value: String
}

extension Identifier {
    /// The text form of the identifier used in SQL bindings, matching `LarderRecord`'s UUID strategy.
    var key: String { rawValue.uuidString }
}

extension Set where Element: RawRepresentable, Element.RawValue == String {
    /// The elements in a stable order, so JSON columns do not churn on every save.
    var sortedByRawValue: [Element] { sorted { $0.rawValue < $1.rawValue } }
}
