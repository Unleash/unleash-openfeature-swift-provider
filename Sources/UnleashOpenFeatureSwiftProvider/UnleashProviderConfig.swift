import Foundation
import UnleashProxyClientSwift

/// Configuration for ``UnleashProvider``.
///
/// The provider constructs and owns its `UnleashClientBase` internally from
/// this configuration, mirroring the commonly used subset of the Unleash
/// Swift SDK's client options.
public struct UnleashProviderConfig {
    /// URL to the Unleash Frontend API or Unleash Edge, e.g.
    /// `https://unleash.example.com/api/frontend`.
    public var unleashUrl: String
    /// Client-side (frontend) API token.
    public var clientKey: String
    /// Flag polling interval in seconds. `0` disables the polling timer.
    public var refreshInterval: Int
    /// Metrics reporting interval in seconds.
    public var metricsInterval: Int
    /// Disables usage metrics reporting when `true`.
    public var disableMetrics: Bool
    /// Application name, sent to Unleash and set on the Unleash context.
    public var appName: String
    /// Environment name set on the Unleash context.
    public var environment: String?
    /// Initial flag configuration used before (or instead of) the first fetch.
    public var bootstrap: Bootstrap
    /// Extra headers to send with flag requests.
    public var customHeaders: [String: String]
    /// Session used for flag polling. Defaults to `URLSession.shared`;
    /// injectable for custom networking or testing.
    public var pollerSession: PollerSession

    public init(
        unleashUrl: String,
        clientKey: String,
        refreshInterval: Int = 15,
        metricsInterval: Int = 30,
        disableMetrics: Bool = false,
        appName: String = "unleash-openfeature-swift-provider",
        environment: String? = nil,
        bootstrap: Bootstrap = .toggles([]),
        customHeaders: [String: String] = [:],
        pollerSession: PollerSession = URLSession.shared
    ) {
        self.unleashUrl = unleashUrl
        self.clientKey = clientKey
        self.refreshInterval = refreshInterval
        self.metricsInterval = metricsInterval
        self.disableMetrics = disableMetrics
        self.appName = appName
        self.environment = environment
        self.bootstrap = bootstrap
        self.customHeaders = customHeaders
        self.pollerSession = pollerSession
    }
}
