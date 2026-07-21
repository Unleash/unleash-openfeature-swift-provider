import Foundation
import OpenFeature
@testable import UnleashOpenFeatureSwiftProvider
import UnleashProxyClientSwift
import XCTest

final class EvaluationTests: XCTestCase {
    private func initializedProvider() async throws -> UnleashProvider {
        let provider = try makeProvider(toggles: fixtureToggles)
        try await provider.initialize(initialContext: nil)
        return provider
    }

    func testBooleanEvaluation() async throws {
        let provider = try await initializedProvider()

        let enabled = try provider.getBooleanEvaluation(key: "bool-flag", defaultValue: false, context: nil)
        XCTAssertTrue(enabled.value)
        XCTAssertEqual(enabled.reason, "UNKNOWN")
        XCTAssertNil(enabled.errorCode)

        let disabled = try provider.getBooleanEvaluation(key: "bool-flag-off", defaultValue: true, context: nil)
        XCTAssertFalse(disabled.value)
    }

    func testBooleanEvaluationOfMissingFlagFallsBackToDisabled() async throws {
        let provider = try await initializedProvider()

        // Unleash's isEnabled has no default parameter; a missing flag is
        // indistinguishable from a disabled one and resolves to false.
        let missing = try provider.getBooleanEvaluation(key: "no-such-flag", defaultValue: true, context: nil)
        XCTAssertFalse(missing.value)
    }

    func testStringEvaluation() async throws {
        let provider = try await initializedProvider()

        let result = try provider.getStringEvaluation(key: "string-flag", defaultValue: "fallback", context: nil)
        XCTAssertEqual(result.value, "hello")
        XCTAssertEqual(result.variant, "string-flag-variant")
        XCTAssertEqual(result.reason, "UNKNOWN")

        let csv = try provider.getStringEvaluation(key: "csv-flag", defaultValue: "fallback", context: nil)
        XCTAssertEqual(csv.value, "a,b,c")
        XCTAssertEqual(csv.variant, "csv-flag-variant")
    }

    func testIntegerEvaluation() async throws {
        let provider = try await initializedProvider()

        let result = try provider.getIntegerEvaluation(key: "int-flag", defaultValue: 0, context: nil)
        XCTAssertEqual(result.value, 42)
        XCTAssertEqual(result.variant, "int-flag-variant")
    }

    func testDoubleEvaluation() async throws {
        let provider = try await initializedProvider()

        let result = try provider.getDoubleEvaluation(key: "double-flag", defaultValue: 0, context: nil)
        XCTAssertEqual(result.value, 3.25)
    }

    func testObjectEvaluation() async throws {
        let provider = try await initializedProvider()

        let result = try provider.getObjectEvaluation(key: "json-flag", defaultValue: .null, context: nil)
        let structure = try XCTUnwrap(result.value.asStructure())
        XCTAssertEqual(structure["title"], .string("welcome"))
        XCTAssertEqual(structure["count"], .integer(2))
        XCTAssertEqual(structure["ratio"], .double(0.5))
        XCTAssertEqual(structure["on"], .boolean(true))
        XCTAssertEqual(structure["tags"], .list([.string("a"), .string("b")]))
        XCTAssertEqual(structure["missing"], .null)
    }

    func testMissingFlagReturnsDefaultForVariantTypes() async throws {
        let provider = try await initializedProvider()

        let string = try provider.getStringEvaluation(key: "no-such-flag", defaultValue: "fallback", context: nil)
        XCTAssertEqual(string.value, "fallback")
        XCTAssertNil(string.variant)
        XCTAssertNil(string.errorCode)

        let object = try provider.getObjectEvaluation(key: "no-such-flag", defaultValue: .string("d"), context: nil)
        XCTAssertEqual(object.value, .string("d"))
    }

    func testDisabledVariantReturnsDefault() async throws {
        let provider = try await initializedProvider()

        let result = try provider.getStringEvaluation(
            key: "disabled-variant-flag", defaultValue: "fallback", context: nil
        )
        XCTAssertEqual(result.value, "fallback")
        XCTAssertNil(result.variant)
    }

    func testVariantWithoutPayloadReturnsDefault() async throws {
        let provider = try await initializedProvider()

        let result = try provider.getIntegerEvaluation(key: "no-payload-flag", defaultValue: 7, context: nil)
        XCTAssertEqual(result.value, 7)
        XCTAssertNil(result.variant)
    }

    func testMismatchedPayloadTypeThrowsTypeMismatch() async throws {
        let provider = try await initializedProvider()

        XCTAssertThrowsError(
            try provider.getStringEvaluation(key: "int-flag", defaultValue: "fallback", context: nil)
        ) { error in
            XCTAssertEqual(error as? OpenFeatureError, .typeMismatchError)
        }
        XCTAssertThrowsError(
            try provider.getIntegerEvaluation(key: "string-flag", defaultValue: 0, context: nil)
        ) { error in
            XCTAssertEqual(error as? OpenFeatureError, .typeMismatchError)
        }
        XCTAssertThrowsError(
            try provider.getObjectEvaluation(key: "csv-flag", defaultValue: .null, context: nil)
        ) { error in
            XCTAssertEqual(error as? OpenFeatureError, .typeMismatchError)
        }
    }

    func testUnparseablePayloadThrowsParseError() async throws {
        let provider = try await initializedProvider()

        XCTAssertThrowsError(
            try provider.getIntegerEvaluation(key: "bad-int-flag", defaultValue: 0, context: nil)
        ) { error in
            XCTAssertEqual((error as? OpenFeatureError)?.errorCode(), .parseError)
        }
        XCTAssertThrowsError(
            try provider.getDoubleEvaluation(key: "bad-int-flag", defaultValue: 0, context: nil)
        ) { error in
            XCTAssertEqual((error as? OpenFeatureError)?.errorCode(), .parseError)
        }
        XCTAssertThrowsError(
            try provider.getObjectEvaluation(key: "bad-json-flag", defaultValue: .null, context: nil)
        ) { error in
            XCTAssertEqual((error as? OpenFeatureError)?.errorCode(), .parseError)
        }
    }
}

final class LifecycleTests: XCTestCase {
    func testInitializeWithBootstrapSucceedsOffline() async throws {
        let session = StubPollerSession()
        let provider = try makeProvider(toggles: fixtureToggles, session: session)

        try await provider.initialize(initialContext: nil)

        // Bootstrapped start never fetches; evaluation is served from bootstrap.
        XCTAssertTrue(session.requests.isEmpty)
        let result = try provider.getBooleanEvaluation(key: "bool-flag", defaultValue: false, context: nil)
        XCTAssertTrue(result.value)
    }

    func testInitializeWithoutBootstrapFetchesFlags() async throws {
        let session = StubPollerSession()
        let provider = try makeProvider(toggles: [], session: session)

        try await provider.initialize(initialContext: nil)

        XCTAssertEqual(session.requests.count, 1)
    }

    func testStampsSdkFlavorHeaderOnRequests() async throws {
        let session = StubPollerSession()
        let provider = try makeProvider(toggles: [], session: session)

        try await provider.initialize(initialContext: nil)

        XCTAssertEqual(
            session.requests.first?.value(forHTTPHeaderField: "sdkFlavor"),
            ProviderInfo.sdkFlavor
        )
        XCTAssertEqual(
            session.requests.first?.value(forHTTPHeaderField: "sdkFlavorVersion"),
            ProviderInfo.sdkFlavorVersion
        )
    }

    func testInitializeThrowsWhenFetchFails() async throws {
        let session = StubPollerSession(statusCode: 401)
        let provider = try makeProvider(toggles: [], session: session)

        do {
            try await provider.initialize(initialContext: nil)
            XCTFail("Expected initialize to throw")
        } catch let error as OpenFeatureError {
            XCTAssertEqual(error.errorCode(), .general)
        }
    }

    func testInitializeWithInitialContextSendsContextToUnleash() async throws {
        let session = StubPollerSession()
        let provider = try makeProvider(toggles: fixtureToggles, session: session)
        let context = ImmutableContext(
            targetingKey: "user-123",
            structure: ImmutableStructure(attributes: ["plan": .string("premium")])
        )

        try await provider.initialize(initialContext: context)

        let query = try XCTUnwrap(session.lastRequestUrl?.query)
        XCTAssertTrue(query.contains("userId=user-123"))
        XCTAssertTrue(query.contains("properties%5Bplan%5D=premium"))
    }

    func testOnContextSetUpdatesUnleashContext() async throws {
        let session = StubPollerSession()
        let provider = try makeProvider(toggles: fixtureToggles, session: session)
        try await provider.initialize(initialContext: nil)

        let context = ImmutableContext(
            targetingKey: "user-456",
            structure: ImmutableStructure(attributes: [
                "sessionId": .string("session-9"),
                "custom": .string("value"),
            ])
        )
        try await provider.onContextSet(oldContext: nil, newContext: context)

        let query = try XCTUnwrap(session.lastRequestUrl?.query)
        XCTAssertTrue(query.contains("userId=user-456"))
        XCTAssertTrue(query.contains("sessionId=session-9"))
        XCTAssertTrue(query.contains("properties%5Bcustom%5D=value"))
    }

    func testInvalidUrlThrowsInsteadOfCrashing() {
        XCTAssertThrowsError(
            try UnleashProvider(config: UnleashProviderConfig(unleashUrl: "not a url", clientKey: "key"))
        ) { error in
            XCTAssertEqual((error as? OpenFeatureError)?.errorCode(), .general)
        }
    }

    func testOnCloseIsIdempotent() async throws {
        let provider = try makeProvider(toggles: fixtureToggles)
        try await provider.initialize(initialContext: nil)

        provider.onClose()
        provider.onClose()
    }

    func testMetadataNamesTheProvider() throws {
        let provider = try makeProvider()
        XCTAssertEqual(provider.metadata.name, "Unleash")
        XCTAssertTrue(provider.hooks.isEmpty)
    }
}

final class ContextMapperTests: XCTestCase {
    func testTargetingKeyWinsOverUserId() {
        let context = ImmutableContext(
            targetingKey: "targeting-key",
            structure: ImmutableStructure(attributes: ["userId": .string("explicit-user-id")])
        )
        XCTAssertEqual(ContextMapper.map(context)["userId"], "targeting-key")
    }

    func testUserIdIsUsedWhenNoTargetingKeyIsSet() {
        let context = ImmutableContext(attributes: ["userId": .string("explicit-user-id")])
        XCTAssertEqual(ContextMapper.map(context)["userId"], "explicit-user-id")
    }

    func testScalarsAreStringified() {
        let date = Date(timeIntervalSince1970: 0)
        let context = ImmutableContext(attributes: [
            "string": .string("text"),
            "int": .integer(7),
            "double": .double(1.5),
            "bool": .boolean(true),
            "date": .date(date),
        ])
        let map = ContextMapper.map(context)
        XCTAssertEqual(map["string"], "text")
        XCTAssertEqual(map["int"], "7")
        XCTAssertEqual(map["double"], "1.5")
        XCTAssertEqual(map["bool"], "true")
        XCTAssertEqual(map["date"], "1970-01-01T00:00:00Z")
    }

    func testNonScalarsAreDropped() {
        let context = ImmutableContext(attributes: [
            "list": .list([.string("a")]),
            "structure": .structure(["k": .string("v")]),
            "null": .null,
        ])
        XCTAssertTrue(ContextMapper.map(context).isEmpty)
    }
}

final class ValueConverterTests: XCTestCase {
    func testConvertsNestedJson() throws {
        let value = try ValueConverter.value(
            fromJson: #"{"nested": {"list": [1, 2.5, "x", false, null]}}"#
        )
        let nested = try XCTUnwrap(value.asStructure()?["nested"]?.asStructure())
        XCTAssertEqual(nested["list"], .list([.integer(1), .double(2.5), .string("x"), .boolean(false), .null]))
    }

    func testConvertsTopLevelFragments() throws {
        XCTAssertEqual(try ValueConverter.value(fromJson: "3"), .integer(3))
        XCTAssertEqual(try ValueConverter.value(fromJson: "true"), .boolean(true))
        XCTAssertEqual(try ValueConverter.value(fromJson: #""text""#), .string("text"))
        XCTAssertEqual(try ValueConverter.value(fromJson: "[1, 2]"), .list([.integer(1), .integer(2)]))
    }

    func testInvalidJsonThrowsParseError() {
        XCTAssertThrowsError(try ValueConverter.value(fromJson: "{broken")) { error in
            XCTAssertEqual((error as? OpenFeatureError)?.errorCode(), .parseError)
        }
    }
}
