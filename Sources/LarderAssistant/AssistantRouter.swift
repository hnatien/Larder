import Foundation
import LarderCore

/// One kind of assistant request, used to ask a backend what it supports.
public enum AssistantRoute: String, CaseIterable, Hashable, Sendable {
    case explain
    case parsePantry
    case parseRecipe
    case adjust
}

/// Reports whether an on-device model can serve requests right now, and which ones.
public protocol OnDeviceAvailability: Sendable {
    /// Whether the on-device model is ready on this device.
    var isAvailable: Bool { get }
    /// The routes the on-device backend can handle.
    var supportedRoutes: Set<AssistantRoute> { get }
}

/// Picks a backend per request: on-device first, the proxy only with consent, and the deterministic parser offline.
///
/// For pantry and recipe parsing, an on-device failure the device cannot get past (input too long, unsupported
/// language, model not ready) falls through as if the model were unavailable. A decline or a cancellation
/// propagates and is never retried elsewhere, so a guardrail decline is not laundered through another model.
public struct AssistantRouter: AssistantBackend {
    private let onDevice: (any AssistantBackend & OnDeviceAvailability)?
    private let proxy: ProxyAssistantBackend
    private let fallback: DeterministicPantryParser
    private let consent: @Sendable () async -> Consents

    /// Creates a router.
    public init(
        onDevice: (any AssistantBackend & OnDeviceAvailability)?,
        proxy: ProxyAssistantBackend,
        fallback: DeterministicPantryParser = DeterministicPantryParser(),
        consent: @escaping @Sendable () async -> Consents
    ) {
        self.onDevice = onDevice
        self.proxy = proxy
        self.fallback = fallback
        self.consent = consent
    }

    public func explain(plan: PlanExplainRequest) async throws -> PlanExplanation {
        if let backend = onDevice(for: .explain) {
            return try await backend.explain(plan: plan)
        }
        guard await consent().aiProcessing else { throw LarderError.consentRequired }
        return try await proxy.explain(plan: plan)
    }

    public func parsePantry(text: String) async throws -> [ParsedPantryLine] {
        if let backend = onDevice(for: .parsePantry) {
            do {
                return try await backend.parsePantry(text: text)
            } catch LarderError.invalidResponse, LarderError.assistantUnavailable {}
        }
        guard await consent().aiProcessing else { return fallback.parse(text) }
        do {
            return try await proxy.parsePantry(text: text)
        } catch LarderError.assistantUnavailable {
            return fallback.parse(text)
        }
    }

    public func parseRecipe(text: String, imageData: Data?) async throws -> ParsedRecipe {
        if let backend = onDevice(for: .parseRecipe) {
            do {
                return try await backend.parseRecipe(text: text, imageData: imageData)
            } catch LarderError.invalidResponse, LarderError.assistantUnavailable {}
        }
        guard await consent().aiProcessing else { throw LarderError.assistantUnavailable }
        return try await proxy.parseRecipe(text: text, imageData: imageData)
    }

    public func adjust(request: AdjustRequest) async throws -> ConstraintEdit {
        if let backend = onDevice(for: .adjust) {
            return try await backend.adjust(request: request)
        }
        guard await consent().aiProcessing else { throw LarderError.assistantUnavailable }
        return try await proxy.adjust(request: request)
    }

    private func onDevice(for route: AssistantRoute) -> (any AssistantBackend)? {
        guard let onDevice, onDevice.isAvailable, onDevice.supportedRoutes.contains(route) else { return nil }
        return onDevice
    }
}
