import Foundation

/// Names and derivatives that reveal an allergen in ingredient text ("tahini" is sesame, "ghee" is milk).
///
/// Matching is whole-word and case-insensitive with simple plurals, so "peanutless" does not match "peanut"
/// and "eggplant" does not match "egg". A term directly followed by "free" ("gluten-free") does not match.
///
/// Exceptions are whole phrases that name a food without the allergen ("peanut butter", "oyster mushroom").
/// A term occurrence that overlaps an exception does not match; other occurrences in the same text still do,
/// so "peanut butter and milk" matches milk. Exceptions only apply to this text path: a food's `AllergenTags`
/// are checked on the data path and are never suppressed.
public struct AllergenLexicon: Hashable, Sendable {
    /// Terms per allergen.
    public var terms: [Allergen: [String]]
    /// Phrases per allergen inside which a term does not count.
    public var exceptions: [Allergen: [String]]

    /// Creates a lexicon from explicit terms and exceptions.
    public init(terms: [Allergen: [String]], exceptions: [Allergen: [String]] = [:]) {
        self.terms = terms
        self.exceptions = exceptions
    }

    /// The most specific term for `allergen` found in `text` outside its exceptions, or `nil`.
    public func match(in text: String, for allergen: Allergen) -> String? {
        TermMatcher.firstMatch(of: terms[allergen] ?? [], in: text, except: exceptions[allergen] ?? [])
    }

    /// The built-in lexicon covering every `Allergen`.
    public static let standard = AllergenLexicon(terms: [
        .milk: [
            "milk", "ghee", "whey", "casein", "caseinate", "paneer", "butter", "buttermilk", "cream", "yoghurt",
            "yogurt", "cheese", "lactose", "kefir", "curd", "custard", "mascarpone", "ricotta", "parmesan",
            "mozzarella", "feta", "halloumi", "creme fraiche",
        ],
        .egg: ["egg", "albumen", "albumin", "ovalbumin", "mayonnaise", "mayo", "meringue", "aioli", "eggnog"],
        .fish: [
            "fish", "anchovy", "worcestershire", "cod", "salmon", "tuna", "haddock", "sardine", "mackerel", "trout",
            "pollock", "tilapia", "bonito", "dashi", "nam pla", "nuoc mam",
        ],
        .crustacean: [
            "crustacean", "shellfish", "prawn", "shrimp", "crab", "lobster", "langoustine", "crayfish", "crawfish",
            "scampi", "krill",
        ],
        .mollusc: [
            "mollusc", "mollusk", "shellfish", "mussel", "clam", "oyster", "squid", "scallop", "octopus", "calamari",
            "cuttlefish", "snail", "escargot", "whelk", "cockle", "abalone",
        ],
        .treeNut: [
            "tree nut", "nut", "almond", "cashew", "walnut", "pecan", "pistachio", "hazelnut", "filbert", "macadamia",
            "brazil nut", "pine nut", "marzipan", "praline", "frangipane", "gianduja",
        ],
        .peanut: ["peanut", "groundnut", "satay", "monkey nut", "arachis"],
        .wheat: [
            "wheat", "seitan", "couscous", "bulgur", "bulghur", "semolina", "farina", "durum", "spelt", "einkorn",
            "emmer", "kamut", "freekeh", "panko",
        ],
        .gluten: [
            "gluten", "wheat", "barley", "rye", "spelt", "malt", "malted", "seitan", "couscous", "bulgur", "semolina",
            "farina", "durum", "triticale", "kamut", "freekeh", "panko",
        ],
        .soy: ["soy", "soya", "tofu", "tempeh", "edamame", "miso", "shoyu", "tamari", "natto", "yuba"],
        .sesame: ["sesame", "tahini", "tahina", "halva", "halvah", "benne", "gomasio", "gomashio", "zaatar", "furikake"],
        .celery: ["celery", "celeriac", "mirepoix", "soffritto"],
        .mustard: ["mustard", "dijon", "piccalilli", "mostarda"],
        .lupin: ["lupin", "lupine", "lupini"],
        .sulphites: [
            "sulphite", "sulfite", "sulphur dioxide", "sulfur dioxide", "metabisulphite", "metabisulfite", "e220",
            "dried apricot", "sultana", "wine",
        ],
    ], exceptions: standardExceptions)

    /// Compound names that contain a term but not the allergen.
    ///
    /// Coconut is not a tree nut here: the FDA stopped treating coconut as a tree nut in its January 2025
    /// allergen guidance update. "Buttermilk", "oyster sauce", "egg noodles" and "fish sauce" contain their
    /// allergen and are deliberately absent.
    static let standardExceptions: [Allergen: [String]] = [
        .milk: [
            "coconut milk", "coconut cream", "coconut butter", "almond milk", "oat milk", "rice milk", "cashew milk",
            "soy milk", "peanut butter", "almond butter", "cocoa butter", "shea butter", "butternut", "milk thistle",
        ],
        .treeNut: [
            "coconut", "coconut milk", "coconut oil", "nutmeg", "butternut", "water chestnut", "chestnut mushroom",
            "donut", "doughnut", "peanut",
        ],
        .mollusc: ["oyster mushroom"],
        .egg: ["eggplant"],
        .wheat: ["buckwheat", "wheatgrass"],
        .gluten: ["buckwheat", "wheatgrass"],
    ]
}

extension Allergen {
    var readableName: String {
        switch self {
        case .milk: "milk"
        case .egg: "egg"
        case .fish: "fish"
        case .crustacean: "crustaceans"
        case .mollusc: "molluscs"
        case .treeNut: "tree nuts"
        case .peanut: "peanuts"
        case .wheat: "wheat"
        case .gluten: "gluten"
        case .soy: "soy"
        case .sesame: "sesame"
        case .celery: "celery"
        case .mustard: "mustard"
        case .lupin: "lupin"
        case .sulphites: "sulphites"
        }
    }
}
