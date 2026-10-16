import LarderCore
import SwiftUI

/// A typographic stand-in for a recipe photo: a food-group tint with a dish symbol, so lists keep a rhythm
/// without stock photography. Decorative; the row beside it carries the words.
public struct RecipeTile: View {
    /// The symbol and food group a dish is drawn with.
    public nonisolated struct Motif: Equatable, Sendable {
        public let symbol: String
        public let group: FoodGroup
    }

    /// Sizes used across the app.
    public enum Size: Sendable {
        case small, medium, large, banner

        var side: CGFloat {
            switch self {
            case .small: 44
            case .medium: 56
            case .large: 72
            case .banner: 96
            }
        }
    }

    /// Keywords in a title, checked in order; the first hit decides the motif.
    nonisolated static let motifs: [(keywords: [String], motif: Motif)] = [
        (["chicken", "turkey", "duck"], Motif(symbol: "bird", group: .protein)),
        (["fish", "cod", "salmon", "tuna", "prawn", "shrimp", "mackerel", "sardine", "haddock"], Motif(symbol: "fish", group: .protein)),
        (["cake", "muffin", "cookie", "brownie", "crumble", "pudding"], Motif(symbol: "birthday.cake", group: .grains)),
        (["porridge", "oat", "granola", "toast", "pancake", "breakfast", "bircher", "yoghurt", "yogurt"], Motif(symbol: "cup.and.saucer", group: .dairy)),
        (["dal", "lentil", "chickpea", "bean", "chana", "hummus", "falafel"], Motif(symbol: "circle.hexagongrid", group: .legumes)),
        (["soup", "stew", "chilli", "chili", "curry", "broth", "masala", "tagine"], Motif(symbol: "flame", group: .legumes)),
        (["salad", "spinach", "greens", "kale", "slaw"], Motif(symbol: "leaf", group: .produce)),
        (["omelette", "frittata", "egg", "stir fry", "stir-fry", "fried"], Motif(symbol: "frying.pan", group: .fats)),
        (["roast", "bake", "baked", "tray", "gratin", "pie", "lasagne", "lasagna"], Motif(symbol: "oven", group: .grains)),
        (["pasta", "noodle", "spaghetti", "rice", "risotto", "pilaf", "pitta", "pita", "wrap", "taco", "burrito", "shawarma"], Motif(symbol: "fork.knife", group: .grains)),
    ]

    /// Used when no keyword matches.
    nonisolated static let fallback = Motif(symbol: "carrot", group: .produce)

    /// The motif for a dish title.
    public nonisolated static func motif(for title: String) -> Motif {
        let lowered = title.lowercased()
        return motifs.first { entry in entry.keywords.contains { lowered.contains($0) } }?.motif ?? fallback
    }

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    private let motif: Motif
    private let size: Size

    /// Creates a tile for a dish title.
    public init(title: String, size: Size = .medium) {
        self.motif = Self.motif(for: title)
        self.size = size
    }

    private var tint: Color { LarderColor.food(motif.group) }

    public var body: some View {
        let side = size.side * min(scale, 1.6)
        // A banner runs edge to edge inside a card, which clips it; a tile has its own corners.
        let shape = RoundedRectangle(cornerRadius: size == .banner ? 0 : LarderRadius.tile, style: .continuous)
        ZStack {
            shape.fill(LarderColor.surface.raised)
            shape.fill(tint.opacity(0.16))
            Image(systemName: motif.symbol)
                .resizable()
                .scaledToFit()
                .fontWeight(.medium)
                .foregroundStyle(tint)
                .frame(width: min(side, size.side * 1.6) * 0.42, height: side * 0.42)
        }
        .frame(width: size == .banner ? nil : side, height: side)
        .frame(maxWidth: size == .banner ? .infinity : nil)
        .accessibilityHidden(true)
    }
}

#Preview("RecipeTile") {
    VStack(alignment: .leading, spacing: LarderSpacing.m) {
        HStack(spacing: LarderSpacing.m) {
            RecipeTile(title: "Spinach red lentil dal")
            RecipeTile(title: "Tomato baked cod")
            RecipeTile(title: "Greek lemon chicken and potatoes")
            RecipeTile(title: "Porridge with berries", size: .small)
        }
        RecipeTile(title: "Chana masala", size: .banner)
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
