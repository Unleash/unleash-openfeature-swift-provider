import Foundation
import OpenFeature

/// Translates an OpenFeature `EvaluationContext` into the flat
/// `[String: String]` map the Unleash Swift SDK expects.
///
/// The Unleash SDK itself lifts the special keys (`userId`, `sessionId`,
/// `remoteAddress`) out of the map and treats everything else as custom
/// context properties, so a single flat map is all we need to produce.
enum ContextMapper {
    static func map(_ context: EvaluationContext) -> [String: String] {
        var result: [String: String] = [:]

        for (key, value) in context.asMap() {
            if let stringValue = stringify(value) {
                result[key] = stringValue
            }
        }

        // The OpenFeature targeting key identifies the subject of the
        // evaluation and maps to Unleash's userId. It wins over any
        // explicit "userId" field in the context.
        let targetingKey = context.getTargetingKey()
        if !targetingKey.isEmpty {
            result["userId"] = targetingKey
        }

        return result
    }

    /// Unleash context values are flat strings; lists and structures have
    /// no representation and are dropped.
    private static func stringify(_ value: Value) -> String? {
        switch value {
        case .string(let string):
            return string
        case .boolean(let bool):
            return String(bool)
        case .integer(let int):
            return String(int)
        case .double(let double):
            return String(double)
        case .date(let date):
            return ISO8601DateFormatter().string(from: date)
        case .list, .structure, .null:
            return nil
        }
    }
}
