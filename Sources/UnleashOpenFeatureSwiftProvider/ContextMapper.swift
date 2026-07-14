import Foundation
import OpenFeature

/// This deviates in pattern from the other Unleash OpenFeature provider implementations
/// in that it deals in raw String maps. This can only change when the SDK itself
/// gets a healthier public API for context values
enum ContextMapper {
    static func map(_ context: EvaluationContext) -> [String: String] {
        var result: [String: String] = [:]

        for (key, value) in context.asMap() {
            if let stringValue = stringify(value) {
                result[key] = stringValue
            }
        }

        let targetingKey = context.getTargetingKey()
        if !targetingKey.isEmpty {
            result["userId"] = targetingKey
        }

        return result
    }

    private static func stringify(_ value: Value) -> String? {
        switch value {
        case let .string(string):
            string
        case let .boolean(bool):
            String(bool)
        case let .integer(int):
            String(int)
        case let .double(double):
            String(double)
        case let .date(date):
            ISO8601DateFormatter().string(from: date)
        case .list, .structure, .null:
            nil
        }
    }
}
