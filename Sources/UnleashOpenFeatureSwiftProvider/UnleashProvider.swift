import Combine
import Foundation
import OpenFeature
import UnleashProxyClientSwift

/// OpenFeature provider backed by the Unleash Swift SDK.
///
/// This is a static-context provider: the per-evaluation `context` parameter
/// is ignored, and context changes are applied through the OpenFeature SDK's
/// `setEvaluationContext`, which reaches this provider via ``onContextSet``.
///
/// The OpenFeature Swift SDK has no provider shutdown hook, so call
/// ``onClose()`` when the provider is no longer needed to stop polling and
/// metrics reporting.
public final class UnleashProvider: FeatureProvider, @unchecked Sendable {
    struct Metadata: ProviderMetadata {
        let name: String? = "Unleash"
    }

    private enum PayloadType {
        static let string = "string"
        static let csv = "csv"
        static let number = "number"
        static let json = "json"
    }

    private static let reason = "UNKNOWN"

    public let hooks: [any Hook] = []
    public let metadata: ProviderMetadata = Metadata()

    private let client: UnleashClientBase
    private let bootstrap: Bootstrap

    /// Creates a provider owning an Unleash client built from `config`.
    ///
    /// - Throws: `OpenFeatureError.generalError` if `config.unleashUrl` is not a valid URL
    public init(config: UnleashProviderConfig) throws {
        guard let url = URL(string: config.unleashUrl), url.scheme != nil else {
            // Unleash SDK treats a broken URL as a fatal, we have an appropriate error mechanism
            // in OpenFeature, so let's use that
            throw OpenFeatureError.generalError(message: "Invalid Unleash URL: \(config.unleashUrl)")
        }
        self.bootstrap = config.bootstrap
        self.client = UnleashClientBase(
            unleashUrl: config.unleashUrl,
            clientKey: config.clientKey,
            refreshInterval: config.refreshInterval,
            metricsInterval: config.metricsInterval,
            disableMetrics: config.disableMetrics,
            appName: config.appName,
            environment: config.environment,
            pollerSession: config.pollerSession,
            customHeaders: config.customHeaders,
            bootstrap: config.bootstrap,
            sdkFlavor: ProviderInfo.sdkFlavor,
            sdkFlavorVersion: ProviderInfo.sdkFlavorVersion
        )
    }

    /// This provider defines no events of its own.
    public func observe() -> AnyPublisher<ProviderEvent?, Never> {
        Empty().eraseToAnyPublisher()
    }

    public func initialize(initialContext: EvaluationContext?) async throws {
        if let initialContext {
            // updateContext both applies the context and starts polling.
            try await update(context: ContextMapper.map(initialContext))
        } else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                client.start(bootstrap: bootstrap) { error in
                    continuation.resume(with: Self.result(from: error))
                }
            }
        }
    }

    public func onContextSet(
        oldContext: EvaluationContext?,
        newContext: EvaluationContext
    ) async throws {
        try await update(context: ContextMapper.map(newContext))
    }

    /// Stops flag polling and metrics reporting, reverting the provider to an
    /// uninitialized state. Idempotent. The OpenFeature Swift SDK does not
    /// call this itself. Note that this Provider does not support re-initialization after shutdown.
    public func onClose() {
        client.stop()
    }

    private func update(context: [String: String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.updateContext(context: context) { error in
                continuation.resume(with: Self.result(from: error))
            }
        }
    }

    private static func result(from error: PollerError?) -> Result<Void, Error> {
        guard let error else { return .success(()) }
        switch error {
        case .decoding:
            return .failure(OpenFeatureError.parseError(message: "Could not decode flag response from Unleash"))
        case .url, .network, .noResponse, .unhandledStatusCode:
            return .failure(OpenFeatureError.generalError(message: "Could not fetch flags from Unleash: \(error)"))
        }
    }

    public func getBooleanEvaluation(
        key: String,
        defaultValue: Bool,
        context: EvaluationContext?
    ) throws -> ProviderEvaluation<Bool> {
        // Unleash's isEnabled has no default-value parameter; missing flags
        // resolve to the SDK's internal fallback (false).
        ProviderEvaluation(value: client.isEnabled(name: key), reason: Self.reason)
    }

    public func getStringEvaluation(
        key: String,
        defaultValue: String,
        context: EvaluationContext?
    ) throws -> ProviderEvaluation<String> {
        try variantEvaluation(
            key: key,
            defaultValue: defaultValue,
            payloadTypes: [PayloadType.string, PayloadType.csv]
        ) { payload in
            payload.value
        }
    }

    public func getIntegerEvaluation(
        key: String,
        defaultValue: Int64,
        context: EvaluationContext?
    ) throws -> ProviderEvaluation<Int64> {
        try variantEvaluation(key: key, defaultValue: defaultValue, payloadTypes: [PayloadType.number]) { payload in
            guard let value = Int64(payload.value) else {
                throw OpenFeatureError.parseError(
                    message: "Variant payload for flag \(key) is not an integer: \(payload.value)"
                )
            }
            return value
        }
    }

    public func getDoubleEvaluation(
        key: String,
        defaultValue: Double,
        context: EvaluationContext?
    ) throws -> ProviderEvaluation<Double> {
        try variantEvaluation(key: key, defaultValue: defaultValue, payloadTypes: [PayloadType.number]) { payload in
            guard let value = Double(payload.value) else {
                throw OpenFeatureError.parseError(
                    message: "Variant payload for flag \(key) is not a number: \(payload.value)"
                )
            }
            return value
        }
    }

    public func getObjectEvaluation(
        key: String,
        defaultValue: Value,
        context: EvaluationContext?
    ) throws -> ProviderEvaluation<Value> {
        try variantEvaluation(key: key, defaultValue: defaultValue, payloadTypes: [PayloadType.json]) { payload in
            try ValueConverter.value(fromJson: payload.value)
        }
    }

    /// Shared variant resolution: a disabled variant or absent payload yields
    /// the default value (Unleash cannot distinguish a missing flag from a
    /// disabled one); a payload of the wrong type is a type mismatch.
    private func variantEvaluation<T>(
        key: String,
        defaultValue: T,
        payloadTypes: [String],
        transform: (Payload) throws -> T
    ) throws -> ProviderEvaluation<T> {
        let variant = client.getVariant(name: key)
        guard variant.enabled, let payload = variant.payload else {
            return ProviderEvaluation(value: defaultValue, reason: Self.reason)
        }
        guard payloadTypes.contains(payload.type) else {
            throw OpenFeatureError.typeMismatchError
        }
        return try ProviderEvaluation(
            value: transform(payload),
            variant: variant.name,
            reason: Self.reason
        )
    }
}
