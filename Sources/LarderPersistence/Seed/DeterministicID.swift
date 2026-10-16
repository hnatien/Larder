import CryptoKit
import Foundation
import LarderCore

/// Stable identifiers derived from seed slugs, so re-seeding updates rows instead of duplicating them.
public enum DeterministicID {
    /// A version-5-shaped UUID from the first 16 bytes of SHA-256 of `name`.
    public static func uuid(for name: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }

    /// The identifier of the seed food with `slug`.
    public static func foodID(slug: String) -> FoodID {
        FoodID(rawValue: uuid(for: slug))
    }

    /// The identifier of the seed recipe with `slug`.
    public static func recipeID(slug: String) -> RecipeID {
        RecipeID(rawValue: uuid(for: slug))
    }

    /// The identifier of the ingredient line at `position` in the seed recipe with `recipeSlug`.
    public static func ingredientID(recipeSlug: String, position: Int) -> IngredientID {
        IngredientID(rawValue: uuid(for: "\(recipeSlug)/ingredient/\(position)"))
    }
}
