# Unleash OpenFeature Swift Provider

An [OpenFeature](https://openfeature.dev) provider for the
[Unleash iOS/Swift SDK](https://github.com/Unleash/unleash-ios-sdk), letting you
evaluate Unleash feature flags through the vendor-neutral OpenFeature API.

The Unleash Swift SDK is a frontend SDK, so this is a **static-context
provider**: the evaluation context is set once (and updated) on the OpenFeature
API rather than passed per evaluation. Context changes trigger a refetch of the
flag configuration from Unleash.

## Installation

Add the package with Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/Unleash/unleash-openfeature-swift-provider", from: "0.1.0"),
]
```

Then import `UnleashOpenFeatureSwiftProvider`.

## Quick start

```swift
import OpenFeature
import UnleashOpenFeatureSwiftProvider

let provider = try UnleashProvider(config: UnleashProviderConfig(
    unleashUrl: "https://<your-unleash-instance>/api/frontend",
    clientKey: "<client-side-api-token>",
    appName: "my-ios-app"
))

// Registers the provider and starts the Unleash client (initial fetch + polling).
await OpenFeatureAPI.shared.setProviderAndWait(
    provider: provider,
    initialContext: ImmutableContext(targetingKey: "user-123")
)

let client = OpenFeatureAPI.shared.getClient()

let enabled = client.getBooleanValue(key: "my-flag", defaultValue: false)
let title = client.getStringValue(key: "title-variant", defaultValue: "Welcome")
```

### Updating the evaluation context

Context changes go through the OpenFeature API, which reconciles the provider
(the Unleash client refetches flags for the new context):

```swift
await OpenFeatureAPI.shared.setEvaluationContextAndWait(
    evaluationContext: ImmutableContext(
        targetingKey: "user-456",
        structure: ImmutableStructure(attributes: ["plan": .string("pro")])
    )
)
```

### Shutdown

The OpenFeature Swift SDK has no provider shutdown hook, so stop the Unleash
client explicitly when the provider is no longer needed:

```swift
provider.onClose()
OpenFeatureAPI.shared.clearProvider()
```

`onClose()` stops flag polling and metrics reporting and is idempotent.

## Context mapping

OpenFeature context fields are mapped onto the Unleash context:

| OpenFeature                  | Unleash                       |
| ---------------------------- | ----------------------------- |
| `targetingKey`               | `userId` (wins over a `userId` attribute if both are set) |
| `userId` attribute           | `userId` (when no targeting key is set) |
| `sessionId`, `remoteAddress` | Same-named context fields     |
| Other scalar attributes      | Custom context properties     |

Scalar attribute values (string, bool, int, double, date) are stringified;
lists and structures have no Unleash representation and are dropped. `appName`
and `environment` are fixed at provider construction via the config.

## Flag types

| OpenFeature call      | Unleash source | Requirement                       |
| --------------------- | -------------- | --------------------------------- |
| `getBooleanValue`     | `isEnabled`    | —                                 |
| `getStringValue`      | variant payload| payload type `string`             |
| `getIntegerValue`     | variant payload| payload type `number`, integral   |
| `getDoubleValue`      | variant payload| payload type `number`             |
| `getObjectValue`      | variant payload| payload type `json`               |

Payload handling is strict: a payload of the wrong type yields a
`TYPE_MISMATCH` error, and an unparseable value (bad number, invalid JSON)
yields `PARSE_ERROR`. In both cases the OpenFeature client returns the default
value with the error captured in the evaluation details.

A missing flag, a disabled variant, or a variant without a payload resolves to
the provided default value. Unleash frontend SDKs cannot distinguish these
cases, and booleans follow `isEnabled` semantics: a missing flag evaluates to
`false` regardless of the supplied default.

### Resolution reason

Unleash frontend SDKs do not report why a flag evaluated the way it did, so the
`reason` field in evaluation details is always `"UNKNOWN"` for successful
evaluations.

## Scope

Intentionally not implemented in this iteration: hooks, tracking, OFREP, and
provider-defined events. Provider lifecycle events (`ready`, `error`,
`reconciling`, `contextChanged`) are emitted by the OpenFeature SDK itself
around initialization and context changes.

## Development

```bash
swift build
swift test
```

Tests run fully offline: flag state is seeded through the Unleash SDK's
bootstrap mechanism and HTTP is stubbed via the config's `pollerSession`.
