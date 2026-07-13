import Foundation
import OpenFeature

/// Converts JSON strings (Unleash variant payloads of type "json") into
/// OpenFeature `Value` trees.
enum ValueConverter {
    static func value(fromJson json: String) throws -> Value {
        guard let data = json.data(using: .utf8) else {
            throw OpenFeatureError.parseError(message: "Variant payload is not valid UTF-8")
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw OpenFeatureError.parseError(message: "Variant payload is not valid JSON: \(error.localizedDescription)")
        }
        return convert(object)
    }

    private static func convert(_ object: Any) -> Value {
        switch object {
        case let dictionary as [String: Any]:
            return .structure(dictionary.mapValues(convert))
        case let array as [Any]:
            return .list(array.map(convert))
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if number.isBool {
                return .boolean(number.boolValue)
            }
            // Integral numbers become .integer, everything else .double.
            if number.doubleValue == number.doubleValue.rounded(),
               let int = Int64(exactly: number) {
                return .integer(int)
            }
            return .double(number.doubleValue)
        default:
            // JSONSerialization represents null as NSNull.
            return .null
        }
    }
}

private extension NSNumber {
    var isBool: Bool {
        CFGetTypeID(self) == CFBooleanGetTypeID()
    }
}
