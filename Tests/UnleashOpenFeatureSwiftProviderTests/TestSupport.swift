import Foundation
import OpenFeature
import UnleashProxyClientSwift

@testable import UnleashOpenFeatureSwiftProvider

/// A `PollerSession` stub that answers every flag request with a canned
/// status code (304 by default, so bootstrapped toggles stay untouched)
/// and records requests for assertions. No network is ever hit.
final class StubPollerSession: PollerSession, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private let statusCode: Int

    init(statusCode: Int = 304) {
        self.statusCode = statusCode
    }

    var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    var lastRequestUrl: URL? {
        requests.last?.url
    }

    func perform(_ request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) {
        lock.withLock { _requests.append(request) }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://unleash.test")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: [:]
        )
        completionHandler(Data(), response, nil)
    }
}

func makeProvider(
    toggles: [Toggle] = [],
    session: StubPollerSession = StubPollerSession()
) throws -> UnleashProvider {
    try UnleashProvider(
        config: UnleashProviderConfig(
            unleashUrl: "https://unleash.test/api/frontend",
            clientKey: "test-key",
            refreshInterval: 0,
            disableMetrics: true,
            appName: "provider-tests",
            bootstrap: .toggles(toggles),
            pollerSession: session
        )
    )
}

func variantToggle(_ name: String, payloadType: String, payloadValue: String) -> Toggle {
    Toggle(
        name: name,
        enabled: true,
        variant: Variant(
            name: "\(name)-variant",
            enabled: true,
            featureEnabled: true,
            payload: Payload(type: payloadType, value: payloadValue)
        )
    )
}

// Computed because Toggle predates Sendable; a stored global of a
// non-Sendable type is rejected under strict concurrency.
var fixtureToggles: [Toggle] {
    [
    Toggle(name: "bool-flag", enabled: true),
    Toggle(name: "bool-flag-off", enabled: false),
    variantToggle("string-flag", payloadType: "string", payloadValue: "hello"),
    variantToggle("int-flag", payloadType: "number", payloadValue: "42"),
    variantToggle("double-flag", payloadType: "number", payloadValue: "3.25"),
    variantToggle(
        "json-flag",
        payloadType: "json",
        payloadValue: #"{"title": "welcome", "count": 2, "ratio": 0.5, "on": true, "tags": ["a", "b"], "missing": null}"#
    ),
    variantToggle("csv-flag", payloadType: "csv", payloadValue: "a,b,c"),
    variantToggle("bad-int-flag", payloadType: "number", payloadValue: "not-a-number"),
    variantToggle("bad-json-flag", payloadType: "json", payloadValue: "{not json"),
    Toggle(
        name: "disabled-variant-flag",
        enabled: true,
        variant: Variant(name: "disabled", enabled: false, featureEnabled: true)
    ),
    Toggle(
        name: "no-payload-flag",
        enabled: true,
        variant: Variant(name: "plain", enabled: true, featureEnabled: true)
    ),
    ]
}
