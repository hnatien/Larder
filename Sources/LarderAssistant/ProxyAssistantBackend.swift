import Foundation
import LarderCore

/// On-device context the explain route needs beyond the plan itself.
public struct ExplainContext: Sendable {
    public var profile: UserProfile
    public var constraints: [DietaryConstraint]
    /// Total minutes per recipe title in the plan.
    public var recipeMinutes: [String: Int]
    public var groupsLight: [FoodGroup]
    public var groupsHeavy: [FoodGroup]

    /// Creates an explain context.
    public init(
        profile: UserProfile,
        constraints: [DietaryConstraint],
        recipeMinutes: [String: Int],
        groupsLight: [FoodGroup] = [],
        groupsHeavy: [FoodGroup] = []
    ) {
        self.profile = profile
        self.constraints = constraints
        self.recipeMinutes = recipeMinutes
        self.groupsLight = groupsLight
        self.groupsHeavy = groupsHeavy
    }
}

/// The cloud assistant: translates Core requests to the proxy's wire format, scrubbing them first.
public struct ProxyAssistantBackend: AssistantBackend {
    static let maxImageBase64Length = 7_000_000
    static let adjustContextDays = 7
    /// The proxy's limit on earlier turns sent with an adjust request.
    static let adjustConversationTurns = 8

    private let client: ProxyClient
    private let dateProvider: any DateProvider
    private let sanitizer: PromptSanitizer
    private let explainContext: @Sendable () async throws -> ExplainContext

    /// Creates a proxy backend; `explainContext` supplies the profile, recipe minutes and shelf balance for explain requests.
    public init(
        client: ProxyClient,
        dateProvider: any DateProvider,
        sanitizer: PromptSanitizer = PromptSanitizer(),
        explainContext: @escaping @Sendable () async throws -> ExplainContext
    ) {
        self.client = client
        self.dateProvider = dateProvider
        self.sanitizer = sanitizer
        self.explainContext = explainContext
    }

    public func explain(plan: PlanExplainRequest) async throws -> PlanExplanation {
        let context = try await explainContext()
        let start = dateProvider.now
        let body = ExplainRequestBody(
            plan: planWire(plan, start: start, minutes: context.recipeMinutes),
            shelfBalance: .init(groupsLight: context.groupsLight, groupsHeavy: context.groupsHeavy),
            profileSummary: .make(profile: context.profile, constraints: context.constraints)
        )
        let response = try await send(body, to: .explain, as: ExplainResponseBody.self)
        return explanation(from: response, for: plan, start: start)
    }

    public func parsePantry(text: String) async throws -> [ParsedPantryLine] {
        let scrubbed = sanitizer.scrub(text, limit: sanitizer.pantryLimit)
        guard !scrubbed.isEmpty else { return [] }
        let response = try await send(ParsePantryRequestBody(text: scrubbed), to: .parsePantry, as: ParsePantryResponseBody.self)
        let now = dateProvider.now
        return response.lines.map { line in
            ParsedPantryLine(
                rawText: line.rawName,
                name: line.rawName,
                quantity: line.quantity,
                unit: UnitParser.unit(from: line.unit),
                location: line.location,
                bestBy: BestByHint.date(from: line.bestByHint, now: now)
            )
        }
    }

    public func parseRecipe(text: String, imageData: Data?) async throws -> ParsedRecipe {
        let scrubbed = sanitizer.scrub(text, limit: sanitizer.recipeLimit)
        var body = ParseRecipeRequestBody(text: scrubbed.isEmpty ? nil : scrubbed)
        if let imageData {
            guard let mediaType = ImageMediaType(sniffing: imageData) else { throw LarderError.invalidResponse }
            let encoded = imageData.base64EncodedString()
            guard encoded.utf8.count <= Self.maxImageBase64Length else { throw LarderError.invalidResponse }
            body.imageBase64 = encoded
            body.imageMediaType = mediaType.rawValue
        }
        guard body.text != nil || body.imageBase64 != nil else { throw LarderError.invalidResponse }
        let response = try await send(body, to: .parseRecipe, as: ParseRecipeResponseBody.self)
        return ParsedRecipe(
            title: response.title,
            servings: response.servings,
            prepMinutes: response.prepMinutes,
            cookMinutes: response.cookMinutes,
            ingredients: response.ingredients.map {
                ParsedIngredient(rawText: $0.rawText, name: $0.name, quantity: $0.quantity, unit: UnitParser.unit(from: $0.unit))
            },
            steps: response.steps.map { RecipeStep(text: $0.text, timerSeconds: $0.timerSeconds) }
        )
    }

    public func adjust(request: AdjustRequest) async throws -> ConstraintEdit {
        let instruction = sanitizer.scrub(request.message, limit: sanitizer.instructionLimit)
        guard !instruction.isEmpty else { throw LarderError.invalidResponse }
        let start = dateProvider.now
        let days = (0..<Self.adjustContextDays).map { PlanWire.Day(date: WireDate.string(dayOffset: $0, from: start), meals: []) }
        let body = AdjustRequestBody(
            instruction: instruction,
            conversation: conversation(request.conversation),
            currentConstraints: currentConstraints(request),
            planContext: PlanWire(days: days)
        )
        let response = try await send(body, to: .adjust, as: AdjustResponseBody.self)
        let offsets = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($0.element.date, $0.offset) })
        return constraintEdit(from: response, dayOffsets: offsets)
    }

    private func send<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ body: Body,
        to route: AssistantRoute,
        as response: Response.Type
    ) async throws(LarderError) -> Response {
        do {
            return try await client.send(body, to: route, as: response)
        } catch {
            throw error.toLarderError()
        }
    }

    private func planWire(_ plan: PlanExplainRequest, start: Date, minutes: [String: Int]) -> PlanWire {
        let byOffset = Dictionary(grouping: plan.meals, by: \.dayOffset)
        let days = byOffset.keys.sorted().map { offset in
            PlanWire.Day(
                date: WireDate.string(dayOffset: offset, from: start),
                meals: byOffset[offset, default: []].map { meal in
                    PlanWire.Meal(
                        slot: meal.slot,
                        recipeTitle: sanitizer.scrub(meal.recipeTitle, limit: 120),
                        minutes: min(max(minutes[meal.recipeTitle] ?? Self.quickMinutes(meal) ?? 0, 0), 1440),
                        reasonCodes: meal.reasonCodes.prefix(12).map { ReasonCodeWire($0, foodNames: plan.foodNames) }
                    )
                }
            )
        }
        return PlanWire(days: days)
    }

    private static func quickMinutes(_ meal: PlanExplainRequest.Meal) -> Int? {
        meal.reasonCodes.lazy.compactMap { code in
            if case .quick(let minutes) = code { minutes } else { nil }
        }.first
    }

    private func explanation(from response: ExplainResponseBody, for plan: PlanExplainRequest, start: Date) -> PlanExplanation {
        let dates = plan.meals.map { WireDate.string(dayOffset: $0.dayOffset, from: start) }
        var notes: [PlanExplanation.MealNote] = []
        for day in response.perDay {
            if let index = dates.firstIndex(of: day.date) {
                notes.append(.init(mealIndex: index, text: day.sentence))
            }
        }
        for swap in response.swapsOffered {
            let index = plan.meals.indices.first { dates[$0] == swap.date && plan.meals[$0].slot == swap.slot }
            if let index {
                notes.append(.init(mealIndex: index, text: "Or \(swap.alternativeTitle). \(swap.reason)"))
            }
        }
        return PlanExplanation(summary: response.headline, mealNotes: notes)
    }

    /// The latest turns the proxy accepts, each scrubbed like the instruction; `nil` when none is left.
    private func conversation(_ turns: [AdjustRequest.Turn]) -> [AdjustRequestBody.Turn]? {
        let wire = turns.compactMap { turn -> AdjustRequestBody.Turn? in
            let text = sanitizer.scrub(turn.text, limit: sanitizer.instructionLimit)
            guard !text.isEmpty else { return nil }
            return AdjustRequestBody.Turn(role: turn.role == .person ? "person" : "larder", text: text)
        }
        return wire.isEmpty ? nil : Array(wire.suffix(Self.adjustConversationTurns))
    }

    private func currentConstraints(_ request: AdjustRequest) -> [ConstraintWire] {
        let diets = request.dietPatterns
            .map(\.rawValue)
            .sorted()
            .map { ConstraintWire(axis: ConstraintAxis.ethical.rawValue, kind: "diet:\($0)", strictness: Strictness.soft.rawValue) }
        return diets + [
            ConstraintWire(axis: ConstraintAxis.preference.rawValue, kind: "time:maxMinutes:\(request.maxCookMinutes)", strictness: Strictness.soft.rawValue),
            ConstraintWire(axis: ConstraintAxis.goal.rawValue, kind: "goal:\(request.goal.rawValue)", strictness: Strictness.soft.rawValue),
        ]
    }

    private func constraintEdit(from response: AdjustResponseBody, dayOffsets: [String: Int]) -> ConstraintEdit {
        var changes: [ConstraintEdit.Change] = []
        var dropped: [String] = []
        for edit in response.edits {
            if let mapped = Self.changes(for: edit, dayOffsets: dayOffsets) {
                changes += mapped
            } else {
                dropped.append(edit.constraint.kind)
            }
        }
        var summary: [String] = []
        let question = response.clarifyingQuestion?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let question, !question.isEmpty {
            summary.append(question)
        }
        if !dropped.isEmpty {
            summary.append("Not applied here: \(dropped.joined(separator: ", ")).")
        }
        return ConstraintEdit(
            changes: changes,
            summary: summary.joined(separator: " "),
            clarifyingQuestion: question?.isEmpty == false ? question : nil,
            droppedCount: dropped.count
        )
    }

    private static func changes(for edit: AdjustResponseBody.Edit, dayOffsets: [String: Int]) -> [ConstraintEdit.Change]? {
        guard
            let axis = ConstraintAxis(rawValue: edit.constraint.axis),
            axis != .medical, axis != .religious,
            edit.scope.slots?.isEmpty ?? true
        else { return nil }
        let dates = edit.scope.dates ?? []
        let offsets = dates.compactMap { dayOffsets[$0] }
        guard offsets.count == dates.count else { return nil }
        let scoped: [Int?] = offsets.isEmpty ? [nil] : offsets
        let isRemoval = edit.op == "remove"
        guard isRemoval || edit.op == "add" || edit.op == "replace" else { return nil }

        let parts = edit.constraint.kind.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        let value = parts[1]
        switch (parts[0], isRemoval) {
        case ("diet", false):
            guard let pattern = DietPattern(rawValue: value) else { return nil }
            return scoped.map { .addDiet(pattern, dayOffset: $0) }
        case ("diet", true):
            guard let pattern = DietPattern(rawValue: value), offsets.isEmpty else { return nil }
            return [.removeDiet(pattern)]
        case ("time", false):
            let minuteParts = value.split(separator: ":")
            guard minuteParts.count == 2, minuteParts[0] == "maxMinutes", let minutes = Int(minuteParts[1]), minutes > 0 else { return nil }
            return scoped.map { .setMaxCookMinutes(minutes, dayOffset: $0) }
        case ("dislike", false):
            return offsets.isEmpty ? [.addDislike(value)] : nil
        case ("dislike", true):
            return offsets.isEmpty ? [.removeDislike(value)] : nil
        case ("useUp", false):
            return offsets.isEmpty ? [.useUp(value)] : nil
        case ("goal", false):
            guard let goal = Goal(rawValue: value), offsets.isEmpty else { return nil }
            return [.setGoal(goal)]
        default:
            return nil
        }
    }
}
