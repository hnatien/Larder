import Foundation
import LarderCore

/// A recipe read from structured page data, with the tags and photo address the parsed form has no room for.
nonisolated struct StructuredRecipe: Hashable, Sendable {
    var recipe: ParsedRecipe
    var tags: RecipeTags
    /// The first `image` address as the page wrote it, possibly relative; `nil` when there is none.
    var imageAddress: String? = nil
}

/// Reads schema.org Recipe data from `<script type="application/ld+json">` blocks.
nonisolated enum JSONLDRecipeParser {
    /// Why a page yielded no recipe.
    enum ParseError: Error, Hashable, Sendable {
        case noRecipe
    }

    /// The first Recipe in `html`; throws `ParseError.noRecipe` when there is none or it has no title, ingredients and steps.
    static func parse(html: String) throws(ParseError) -> ParsedRecipe {
        try parseStructured(html: html).recipe
    }

    /// Like `parse(html:)`, also returning cuisine, meal types and the photo address.
    static func parseStructured(html: String) throws(ParseError) -> StructuredRecipe {
        for block in jsonBlocks(in: html) {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data)
            else { continue }
            let all = nodes(in: json)
            guard let node = all.first(where: isRecipe), var structured = recipe(from: node) else { continue }
            let nodesByID = Dictionary(
                all.compactMap { node in (node["@id"] as? String).map { ($0, node) } },
                uniquingKeysWith: { first, _ in first }
            )
            structured.imageAddress = imageAddress(node["image"], nodesByID: nodesByID)
            return structured
        }
        throw .noRecipe
    }

    private static func jsonBlocks(in html: String) -> [String] {
        var blocks: [String] = []
        var cursor = html.startIndex
        while let open = html.range(of: "<script", options: .caseInsensitive, range: cursor..<html.endIndex),
              let openEnd = html[open.upperBound...].firstIndex(of: ">") {
            let attributes = html[open.upperBound..<openEnd]
            let contentStart = html.index(after: openEnd)
            let close = html.range(of: "</script", options: .caseInsensitive, range: contentStart..<html.endIndex)
            if attributes.range(of: "application/ld+json", options: .caseInsensitive) != nil {
                blocks.append(clean(html[contentStart..<(close?.lowerBound ?? html.endIndex)]))
            }
            guard let close else { break }
            cursor = close.upperBound
        }
        return blocks
    }

    private static func clean(_ block: Substring) -> String {
        var text = block.trimmingCharacters(in: .whitespacesAndNewlines)
        for wrapper in ["<!--", "//<![CDATA[", "<![CDATA["] where text.hasPrefix(wrapper) {
            text = String(text.dropFirst(wrapper.count))
        }
        for wrapper in ["-->", "//]]>", "]]>"] where text.hasSuffix(wrapper) {
            text = String(text.dropLast(wrapper.count))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nodes(in json: Any) -> [[String: Any]] {
        switch json {
        case let array as [Any]:
            return array.flatMap(nodes(in:))
        case let object as [String: Any]:
            return [object] + (object["@graph"].map(nodes(in:)) ?? [])
        default:
            return []
        }
    }

    private static func isRecipe(_ node: [String: Any]) -> Bool {
        let types: [String] = switch node["@type"] {
        case let type as String: [type]
        case let types as [String]: types
        default: []
        }
        return types.contains { $0.split(whereSeparator: { $0 == "/" || $0 == ":" }).last == "Recipe" }
    }

    private static func recipe(from node: [String: Any]) -> StructuredRecipe? {
        guard let title = text(node["name"]) else { return nil }
        let ingredients = strings(node["recipeIngredient"] ?? node["ingredients"]).map { line in
            let parsed = IngredientLineParser.parse(line)
            return ParsedIngredient(rawText: line, name: parsed.name, quantity: parsed.quantity, unit: parsed.unit)
        }
        let steps = instructions(node["recipeInstructions"]).map {
            RecipeStep(text: $0, timerSeconds: TimerDetector.seconds(in: $0))
        }
        guard !ingredients.isEmpty || !steps.isEmpty else { return nil }

        let (prep, cook) = minutes(
            prep: duration(node["prepTime"]), cook: duration(node["cookTime"]), total: duration(node["totalTime"])
        )
        let parsed = ParsedRecipe(
            title: title,
            servings: servings(node["recipeYield"]),
            prepMinutes: prep,
            cookMinutes: cook,
            ingredients: ingredients,
            steps: steps
        )
        let tags = RecipeTags(
            cuisine: strings(node["recipeCuisine"]).first,
            mealTypes: mealTypes(strings(node["recipeCategory"]))
        )
        return StructuredRecipe(recipe: parsed, tags: tags)
    }

    /// The first address in an `image` value: a URL string, an ImageObject, an `@id` reference to an ImageObject
    /// elsewhere in the page's graph, or an array of any of these.
    private static func imageAddress(_ value: Any?, nodesByID: [String: [String: Any]], followsReferences: Bool = true) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let array as [Any]:
            return array.lazy.compactMap { imageAddress($0, nodesByID: nodesByID, followsReferences: followsReferences) }.first
        case let object as [String: Any]:
            if let address = imageAddress(object["url"] ?? object["contentUrl"], nodesByID: [:], followsReferences: false) {
                return address
            }
            // One hop only, so a reference cycle cannot loop.
            guard followsReferences, let id = object["@id"] as? String, let target = nodesByID[id] else { return nil }
            return imageAddress(target, nodesByID: [:], followsReferences: false)
        default:
            return nil
        }
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let plain = HTMLText.plain(string)
        return plain.isEmpty ? nil : plain
    }

    /// A string or an array of strings as clean, non-empty strings.
    private static func strings(_ value: Any?) -> [String] {
        switch value {
        case let string as String: [text(string)].compactMap { $0 }
        case let array as [Any]: array.flatMap { strings($0) }
        default: []
        }
    }

    private static func duration(_ value: Any?) -> Int? {
        (value as? String).flatMap(ISO8601Duration.minutes(from:))
    }

    private static func minutes(prep: Int?, cook: Int?, total: Int?) -> (prep: Int?, cook: Int?) {
        guard let total else { return (prep, cook) }
        switch (prep, cook) {
        case (nil, nil): return (0, total)
        case (let prep?, nil): return (prep, max(total - prep, 0))
        case (nil, let cook?): return (max(total - cook, 0), cook)
        default: return (prep, cook)
        }
    }

    private static func servings(_ value: Any?) -> Int? {
        let count: Int? = switch value {
        case let number as Int: number
        case let string as String: firstNumber(in: string)
        case let array as [Any]: array.lazy.compactMap { servings($0) }.first
        default: nil
        }
        return count.flatMap { (1...999).contains($0) ? $0 : nil }
    }

    private static func firstNumber(in text: String) -> Int? {
        guard let amount = QuantityText.scan(Substring(text.drop { !$0.isNumber })) else { return nil }
        return Int(amount.value.rounded(.up))
    }

    private static func instructions(_ value: Any?) -> [String] {
        switch value {
        case let string as String:
            return HTMLText.visibleText(from: string, limit: .max)
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        case let array as [Any]:
            return array.flatMap(instructions)
        case let object as [String: Any]:
            if let items = object["itemListElement"] { return instructions(items) }
            return [text(object["text"]) ?? text(object["name"])].compactMap { $0 }
        default:
            return []
        }
    }

    private static func mealTypes(_ categories: [String]) -> Set<MealType> {
        let keywords: [(String, MealType)] = [
            ("breakfast", .breakfast), ("brunch", .breakfast), ("lunch", .lunch), ("dinner", .dinner),
            ("supper", .dinner), ("main", .dinner), ("entree", .dinner), ("snack", .snack), ("appetizer", .snack),
        ]
        let joined = categories.joined(separator: " ").lowercased()
        return Set(keywords.filter { joined.contains($0.0) }.map(\.1))
    }
}
