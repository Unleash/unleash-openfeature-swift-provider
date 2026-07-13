import Foundation
import OpenFeature
@testable import UnleashOpenFeatureSwiftProvider
import UnleashProxyClientSwift
import XCTest

/// Exercises the provider through the real OpenFeature SDK plumbing
/// (`OpenFeatureAPI` + `Client`) rather than direct provider calls.
/// `OpenFeatureAPI.shared` is a process-wide singleton, so each test
/// clears the provider when done.
final class EndToEndTests: XCTestCase {
    override func tearDown() {
        (OpenFeatureAPI.shared.getProvider() as? UnleashProvider)?.onClose()
        OpenFeatureAPI.shared.clearProvider()
        super.tearDown()
    }

    func testEvaluatesAllTypesThroughOpenFeatureClient() async throws {
        let session = StubPollerSession()
        let provider = try makeProvider(toggles: fixtureToggles, session: session)

        await OpenFeatureAPI.shared.setProviderAndWait(
            provider: provider,
            initialContext: ImmutableContext(targetingKey: "user-1")
        )
        XCTAssertEqual(OpenFeatureAPI.shared.getProviderStatus(), .ready)

        let client = OpenFeatureAPI.shared.getClient()
        XCTAssertTrue(client.getBooleanValue(key: "bool-flag", defaultValue: false))
        XCTAssertEqual(client.getStringValue(key: "string-flag", defaultValue: "fallback"), "hello")
        XCTAssertEqual(client.getIntegerValue(key: "int-flag", defaultValue: 0), 42)
        XCTAssertEqual(client.getDoubleValue(key: "double-flag", defaultValue: 0), 3.25)

        let object = client.getObjectValue(key: "json-flag", defaultValue: .null)
        XCTAssertEqual(object.asStructure()?["title"], .string("welcome"))

        let details = client.getStringDetails(key: "string-flag", defaultValue: "fallback")
        XCTAssertEqual(details.reason, "UNKNOWN")
        XCTAssertEqual(details.variant, "string-flag-variant")

        // Provider errors surface as error details with the default value.
        let mismatch = client.getStringDetails(key: "int-flag", defaultValue: "fallback")
        XCTAssertEqual(mismatch.value, "fallback")
        XCTAssertEqual(mismatch.errorCode, .typeMismatch)
    }

    func testContextChangeReconcilesProvider() async throws {
        let session = StubPollerSession()
        let provider = try makeProvider(toggles: fixtureToggles, session: session)

        await OpenFeatureAPI.shared.setProviderAndWait(
            provider: provider,
            initialContext: ImmutableContext(targetingKey: "user-1")
        )

        await OpenFeatureAPI.shared.setEvaluationContextAndWait(
            evaluationContext: ImmutableContext(
                targetingKey: "user-2",
                structure: ImmutableStructure(attributes: ["plan": .string("pro")])
            )
        )

        XCTAssertEqual(OpenFeatureAPI.shared.getProviderStatus(), .ready)
        let query = try XCTUnwrap(session.lastRequestUrl?.query)
        XCTAssertTrue(query.contains("userId=user-2"))
        XCTAssertTrue(query.contains("properties%5Bplan%5D=pro"))

        // Flags are still served after reconciliation (304 keeps the bootstrap).
        let client = OpenFeatureAPI.shared.getClient()
        XCTAssertTrue(client.getBooleanValue(key: "bool-flag", defaultValue: false))
    }
}
