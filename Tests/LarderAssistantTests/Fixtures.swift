import Foundation
import Synchronization
import LarderCore
@testable import LarderAssistant

/// A clock tests can move forward.
final class TestClock: DateProvider {
    private let current: Mutex<Date>

    init(_ date: Date = Fixtures.now) {
        current = Mutex(date)
    }

    var now: Date { current.withLock { $0 } }

    func advance(by interval: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

enum Fixtures {
    /// 2026-10-16T09:00:00Z.
    static let now = Date(timeIntervalSince1970: 1_792_141_200)
    static let sessionPath = "/v1/session"
    static let challengePath = "/v1/challenge"
    static let explainPath = "/v1/assist/explain"
    static let pantryPath = "/v1/assist/parse-pantry"
    static let recipePath = "/v1/assist/parse-recipe"
    static let adjustPath = "/v1/assist/adjust"

    static func sessionReply(token: String = "token-1", expiresAt: String = "2026-10-16T10:00:00.000Z") -> Stub.Reply {
        .json(200, #"{"token":"\#(token)","expiresAt":"\#(expiresAt)"}"#)
    }

    static func challengeReply(_ challenge: String = "challenge-1") -> Stub.Reply {
        .json(200, #"{"challenge":"\#(challenge)","expiresAt":"2026-10-16T09:05:00.000Z"}"#)
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            preconditionFailure("Invalid fixture date \(year)-\(month)-\(day)")
        }
        return date
    }

    static func client(
        _ stub: Stub,
        clock: TestClock = TestClock(),
        secret: String? = "dev-secret",
        entitlement: String? = nil,
        appAttest: AppAttestConfiguration? = nil
    ) -> ProxyClient {
        let configuration = ProxyConfiguration(
            baseURL: stub.baseURL,
            clientSecretProvider: { secret },
            entitlementProvider: { entitlement },
            appAttest: appAttest
        )
        return ProxyClient(configuration: configuration, urlSession: stub.session(), dateProvider: clock)
    }

    static func backend(
        _ stub: Stub,
        context: ExplainContext = explainContext(),
        entitlement: String? = nil
    ) -> ProxyAssistantBackend {
        let clock = TestClock()
        return ProxyAssistantBackend(
            client: client(stub, clock: clock, entitlement: entitlement),
            dateProvider: clock,
            explainContext: { context }
        )
    }

    static let profile = UserProfile(
        birthYear: 1987,
        sex: .female,
        heightCm: 168.5,
        weightKg: 71.3,
        activityLevel: .moderate,
        goal: .lessWaste,
        householdSize: 3,
        weeklyBudget: 120,
        currencyCode: "EUR",
        maxCookMinutes: 30,
        equipment: [.stovetop],
        showsNumbers: false,
        consents: Consents(aiProcessing: true)
    )

    static let sensitiveConstraints: [DietaryConstraint] = [
        DietaryConstraint(axis: .medical, kind: .medical(.coeliacDisease), strictness: .hard, source: .clinician, lastConfirmed: now),
        DietaryConstraint(axis: .medical, kind: .allergen(.peanut), strictness: .hard, source: .user, lastConfirmed: now),
        DietaryConstraint(axis: .religious, kind: .religious(.halal), strictness: .hard, source: .user, lastConfirmed: now),
        DietaryConstraint(axis: .ethical, kind: .diet(.vegetarian), strictness: .soft, source: .user, lastConfirmed: now),
    ]

    static func explainContext(recipeMinutes: [String: Int] = ["Lentil soup": 35, "Fried rice": 20]) -> ExplainContext {
        ExplainContext(
            profile: profile,
            constraints: sensitiveConstraints,
            recipeMinutes: recipeMinutes,
            groupsLight: [.legumes],
            groupsHeavy: [.grains]
        )
    }

    static let spinach = FoodID()

    static let plan = PlanExplainRequest(
        meals: [
            .init(dayOffset: 0, slot: .dinner, recipeTitle: "Lentil soup", reasonCodes: [
                .usesExpiring(food: spinach, bestBy: date(2026, 10, 18)),
                .pantryOverlap(count: 4),
            ]),
            .init(dayOffset: 1, slot: .lunch, recipeTitle: "Fried rice", reasonCodes: [.quick(minutes: 20)]),
            .init(dayOffset: 1, slot: .dinner, recipeTitle: "Bean tacos", reasonCodes: [.quick(minutes: 25), .underBudget]),
        ],
        foodNames: [spinach: "spinach"]
    )

    static let explainReply = Stub.Reply.json(200, """
        {"headline":"Spinach gets used before Sunday.","perDay":[\
        {"date":"2026-10-16","sentence":"Soup uses the spinach."},\
        {"date":"2026-10-17","sentence":"Two quick meals."},\
        {"date":"2030-01-01","sentence":"Not in the plan."}],\
        "swapsOffered":[\
        {"date":"2026-10-17","slot":"dinner","alternativeTitle":"Bean chilli","reason":"Uses the same beans."},\
        {"date":"2026-10-17","slot":"breakfast","alternativeTitle":"Porridge","reason":"No such slot."}]}
        """)

    static let pantryReply = Stub.Reply.json(200, """
        {"lines":[{"rawName":"onions","quantity":2,"unit":null,"location":null,"bestByHint":null},\
        {"rawName":"chicken thighs","quantity":500,"unit":"grams","location":"freezer","bestByHint":"next week"},\
        {"rawName":"stock","quantity":1,"unit":"bucket","location":"pantry","bestByHint":null}]}
        """)

    static let recipeReply = Stub.Reply.json(200, """
        {"title":"Dal","servings":4,"prepMinutes":10,"cookMinutes":30,\
        "ingredients":[{"rawText":"1 cup red lentils","quantity":1,"unit":"cup","name":"red lentils","optional":false},\
        {"rawText":"salt","quantity":null,"unit":null,"name":"salt","optional":true}],\
        "steps":[{"text":"Rinse the lentils.","timerSeconds":null},{"text":"Simmer.","timerSeconds":1200}],\
        "tags":{"cuisine":"Indian","mealType":"dinner"}}
        """)

    static let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])
    static let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
    static let webpBytes = Data(Array("RIFF".utf8) + [0x24, 0x00, 0x00, 0x00] + Array("WEBPVP8 ".utf8))
    static let gifBytes = Data(Array("GIF89a".utf8) + [0x01, 0x00])
}
