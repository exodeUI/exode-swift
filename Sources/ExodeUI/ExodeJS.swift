import Foundation

/// JavaScript literal helpers.
///
/// Every argument that reaches `evaluateJavaScript` goes through these helpers
/// so artboards containing quotes, newlines or backslashes cannot break (or
/// inject into) the script.
public enum ExodeJS {
    /// Encodes `value` as a quoted JavaScript string literal.
    public static func string(_ value: String) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
            let encoded = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        return encoded
    }

    /// Encodes any JSON-compatible value as JavaScript source.
    public static func json(_ value: Any) -> String {
        if value is NSNull { return "null" }
        guard
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
            let encoded = String(data: data, encoding: .utf8)
        else {
            return "null"
        }
        return encoded
    }

    /// Renders a number literal, clamping `NaN` and infinities to `0`.
    public static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    /// Renders a boolean literal.
    public static func bool(_ value: Bool) -> String {
        value ? "true" : "false"
    }
}

/// A message emitted by the JavaScript bridge.
public struct ExodeEvent: Equatable {
    /// Event name (`hostReady`, `ready`, `trigger`, `navigation`, ...).
    public let type: String
    /// Decoded payload, including the `type` key.
    public let payload: [String: Any]

    public init(type: String, payload: [String: Any]) {
        self.type = type
        self.payload = payload
    }

    /// Parses a raw script-message body, returning `nil` for unrelated messages.
    public static func parse(_ raw: String) -> ExodeEvent? {
        guard
            let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let payload = object as? [String: Any],
            let type = payload["type"] as? String,
            !type.isEmpty
        else {
            return nil
        }
        return ExodeEvent(type: type, payload: payload)
    }

    /// A string payload value, coercing numbers and booleans.
    public func string(_ key: String) -> String? {
        guard let value = payload[key], !(value is NSNull) else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    /// A boolean payload value.
    public func bool(_ key: String) -> Bool? {
        guard let number = payload[key] as? NSNumber else { return nil }
        // `JSONSerialization` maps true/false to CFBoolean, which is an NSNumber.
        guard CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// A numeric payload value.
    public func double(_ key: String) -> Double? {
        if let number = payload[key] as? NSNumber { return number.doubleValue }
        if let string = payload[key] as? String { return Double(string) }
        return nil
    }

    /// An integer payload value.
    public func int(_ key: String) -> Int? {
        if let number = payload[key] as? NSNumber { return number.intValue }
        if let string = payload[key] as? String { return Int(string) }
        return nil
    }

    /// A dictionary payload value.
    public func map(_ key: String) -> [String: Any]? {
        payload[key] as? [String: Any]
    }

    /// An array payload value.
    public func list(_ key: String) -> [Any]? {
        payload[key] as? [Any]
    }

    public static func == (lhs: ExodeEvent, rhs: ExodeEvent) -> Bool {
        lhs.type == rhs.type
            && NSDictionary(dictionary: lhs.payload).isEqual(to: rhs.payload)
    }
}
