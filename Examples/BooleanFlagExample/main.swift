import Foundation
import OpenFeature
import UnleashOpenFeatureSwiftProvider

// Evaluate a boolean flag through the OpenFeature Swift SDK, backed by the Unleash provider.

func argument(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: name), index + 1 < args.count else {
        return nil
    }
    return args[index + 1]
}

guard let url = argument("--url"),
    let apiKey = argument("--api-key"),
    let flagKey = argument("--flag-key")
else {
    FileHandle.standardError.write(Data(
        "Usage: boolean-flag-example --url FRONTEND_URL --api-key FRONTEND_TOKEN --flag-key KEY [--targeting-key KEY]\n".utf8
    ))
    exit(1)
}

let targetingKey = argument("--targeting-key") ?? "user-123"

let config = UnleashProviderConfig(
    unleashUrl: url,
    clientKey: apiKey,
    // Metrics interval is in seconds — keep it short so a metrics request
    // (which carries the flavor header) fires quickly while testing.
    metricsInterval: 1,
    appName: "openfeature-swift-example"
)
let provider = try UnleashProvider(config: config)

await OpenFeatureAPI.shared.setProviderAndWait(
    provider: provider,
    initialContext: ImmutableContext(targetingKey: targetingKey)
)

let client = OpenFeatureAPI.shared.getClient()
let details = client.getBooleanDetails(key: flagKey, defaultValue: false)
print("\(flagKey)=\(details.value)")
print("reason=\(details.reason ?? "nil")")

// For testing the poller/metrics on Prometheus
try await Task.sleep(nanoseconds: 5_000_000_000)
provider.onClose()
