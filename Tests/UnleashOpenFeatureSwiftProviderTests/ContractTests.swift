import Foundation
import OpenFeature
@testable import UnleashOpenFeatureSwiftProvider
import UnleashProxyClientSwift
import XCTest

final class ContractTests: XCTestCase {
    override func tearDown() {
        (OpenFeatureAPI.shared.getProvider() as? UnleashProvider)?.onClose()
        OpenFeatureAPI.shared.clearProvider()
        super.tearDown()
    }

    func testVerifierContract() async throws {
        let specRoot = URL(fileURLWithPath: "verifier/spec", relativeTo: projectRoot)
        let contract = try JSONObject(contentsOf: specRoot.appendingPathComponent("contract.json"))
        let toggles = try frontendToggles(
            from: specRoot.appendingPathComponent("fixtures/frontend-toggles.json")
        )
        let provider = try makeProvider(toggles: toggles)

        await OpenFeatureAPI.shared.setProviderAndWait(provider: provider)

        for scenario in contract.array("scenarios").objects {
            guard scenario.appliesToFrontendProvider else {
                continue
            }

            let details = evaluate(scenario: scenario)
            let expected = scenario.object("expect")

            assertJsonEqual(
                scenarioId: scenario.string("id"),
                expected: expected.any("value"),
                actual: details.value
            )

            if expected.has("variant") {
                XCTAssertEqual(details.variant, expected.string("variant"), scenario.string("id"))
            }
        }
    }

    private func evaluate(scenario: JSONObject) -> AnyFlagEvaluationDetails {
        let client = OpenFeatureAPI.shared.getClient()
        let flagKey = scenario.string("flagKey")

        switch scenario.string("type") {
        case "boolean":
            let details = client.getBooleanDetails(
                key: flagKey,
                defaultValue: scenario.bool("default")
            )
            return AnyFlagEvaluationDetails(value: details.value, variant: details.variant)
        case "string":
            let details = client.getStringDetails(
                key: flagKey,
                defaultValue: scenario.string("default")
            )
            return AnyFlagEvaluationDetails(value: details.value, variant: details.variant)
        case "number":
            let details = client.getDoubleDetails(
                key: flagKey,
                defaultValue: scenario.double("default")
            )
            return AnyFlagEvaluationDetails(value: details.value, variant: details.variant)
        case "object":
            let details = client.getObjectDetails(
                key: flagKey,
                defaultValue: openFeatureValue(from: scenario.any("default"))
            )
            return AnyFlagEvaluationDetails(value: details.value.jsonCompatible, variant: details.variant)
        default:
            XCTFail("Unsupported contract scenario type: \(scenario.string("type"))")
            return AnyFlagEvaluationDetails(value: NSNull(), variant: nil)
        }
    }
}

private struct AnyFlagEvaluationDetails {
    let value: Any
    let variant: String?
}

private var projectRoot: URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}

private func frontendToggles(from file: URL) throws -> [Toggle] {
    try JSONObject(contentsOf: file)
        .array("toggles")
        .objects
        .map { toggle in
            Toggle(
                name: toggle.string("name"),
                enabled: toggle.bool("enabled"),
                variant: toggle.object("variant").variant
            )
        }
}

private extension JSONObject {
    var appliesToFrontendProvider: Bool {
        let unsupportedCapabilities = Set(["localEval", "perCallContext"])
        return Set(optionalArray("requires")?.strings ?? []).isDisjoint(with: unsupportedCapabilities)
    }
}

private extension JSONObject {
    var variant: Variant {
        Variant(
            name: string("name"),
            enabled: bool("enabled"),
            featureEnabled: bool("feature_enabled"),
            payload: optionalObject("payload")?.payload
        )
    }

    var payload: Payload {
        Payload(type: string("type"), value: string("value"))
    }
}

private func assertJsonEqual(
    scenarioId: String,
    expected: Any,
    actual: Any,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch (expected, actual) {
    case let (expected as [String: Any], actual as [String: Any]):
        XCTAssertEqual(Set(expected.keys), Set(actual.keys), "\(scenarioId) object keys", file: file, line: line)
        for key in expected.keys {
            assertJsonEqual(
                scenarioId: scenarioId,
                expected: expected[key] ?? NSNull(),
                actual: actual[key] ?? NSNull(),
                file: file,
                line: line
            )
        }
    case let (expected as [Any], actual as [Any]):
        XCTAssertEqual(expected.count, actual.count, "\(scenarioId) array length", file: file, line: line)
        for (expectedValue, actualValue) in zip(expected, actual) {
            assertJsonEqual(
                scenarioId: scenarioId,
                expected: expectedValue,
                actual: actualValue,
                file: file,
                line: line
            )
        }
    case let (expected as NSNumber, actual as NSNumber):
        if expected.isBool || actual.isBool {
            XCTAssertEqual(expected.boolValue, actual.boolValue, scenarioId, file: file, line: line)
        } else {
            XCTAssertEqual(
                expected.doubleValue,
                actual.doubleValue,
                accuracy: 0.000001,
                scenarioId,
                file: file,
                line: line
            )
        }
    case (_ as NSNull, _ as NSNull):
        break
    default:
        XCTAssertEqual(
            String(describing: normalizeJsonValue(expected)),
            String(describing: normalizeJsonValue(actual)),
            scenarioId,
            file: file,
            line: line
        )
    }
}

private func normalizeJsonValue(_ value: Any) -> Any {
    if value is NSNull {
        return "null"
    }
    return value
}

private extension Value {
    var jsonCompatible: Any {
        switch self {
        case let .boolean(value):
            value
        case let .string(value):
            value
        case let .integer(value):
            NSNumber(value: value)
        case let .double(value):
            NSNumber(value: value)
        case let .date(value):
            ISO8601DateFormatter().string(from: value)
        case let .list(values):
            values.map(\.jsonCompatible)
        case let .structure(values):
            values.mapValues(\.jsonCompatible)
        case .null:
            NSNull()
        }
    }
}

private func openFeatureValue(from value: Any) -> Value {
    switch value {
    case let value as Bool:
        .boolean(value)
    case let value as String:
        .string(value)
    case let value as Int:
        .integer(Int64(value))
    case let value as Int64:
        .integer(value)
    case let value as NSNumber:
        if value.isBool {
            .boolean(value.boolValue)
        } else {
            .double(value.doubleValue)
        }
    case let value as [Any]:
        .list(value.map(openFeatureValue))
    case let value as [String: Any]:
        .structure(value.mapValues(openFeatureValue))
    default:
        .null
    }
}

private struct JSONObject {
    private let dictionary: [String: Any]

    init(contentsOf file: URL) throws {
        let data = try Data(contentsOf: file)
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = json as? [String: Any] else {
            throw ContractError.invalidJson(file.path)
        }
        self.dictionary = dictionary
    }

    init(_ dictionary: [String: Any]) {
        self.dictionary = dictionary
    }

    var keys: [String] {
        Array(dictionary.keys)
    }

    func has(_ key: String) -> Bool {
        dictionary[key] != nil
    }

    func any(_ key: String) -> Any {
        dictionary[key] ?? NSNull()
    }

    func string(_ key: String) -> String {
        any(key) as? String ?? fail("Expected \(key) to be a string")
    }

    func bool(_ key: String) -> Bool {
        any(key) as? Bool ?? fail("Expected \(key) to be a boolean")
    }

    func double(_ key: String) -> Double {
        (any(key) as? NSNumber)?.doubleValue ?? fail("Expected \(key) to be a number")
    }

    func object(_ key: String) -> JSONObject {
        optionalObject(key) ?? fail("Expected \(key) to be an object")
    }

    func optionalObject(_ key: String) -> JSONObject? {
        (dictionary[key] as? [String: Any]).map(JSONObject.init)
    }

    func array(_ key: String) -> JSONArray {
        optionalArray(key) ?? fail("Expected \(key) to be an array")
    }

    func optionalArray(_ key: String) -> JSONArray? {
        (dictionary[key] as? [Any]).map(JSONArray.init)
    }

    private func fail<T>(_ message: String) -> T {
        fatalError(message)
    }
}

private struct JSONArray {
    let values: [Any]

    init(_ values: [Any]) {
        self.values = values
    }

    var objects: [JSONObject] {
        values.map { value in
            guard let dictionary = value as? [String: Any] else {
                fatalError("Expected array value to be an object")
            }
            return JSONObject(dictionary)
        }
    }

    var strings: [String] {
        values.map { value in
            guard let string = value as? String else {
                fatalError("Expected array value to be a string")
            }
            return string
        }
    }
}

private enum ContractError: Error {
    case invalidJson(String)
}

private extension NSNumber {
    var isBool: Bool {
        CFGetTypeID(self) == CFBooleanGetTypeID()
    }
}
