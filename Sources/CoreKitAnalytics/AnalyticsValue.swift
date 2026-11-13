/// One event parameter, typed. Each engine decides how a type travels: Firebase sends a `Bool` as
/// `"true"`/`"false"` because a GA4 custom dimension only reads the text slot, while Mixpanel keeps it
/// a boolean so a funnel can filter on it.
///
/// Typed on purpose: the apps used to build parameters as `[String: Any]`, where a `Bool` bridged
/// through `NSNumber` also casts to `Int`, so the order of a cast chain decided whether a flag read
/// `"true"` or `"1"` in the reports.
public enum AnalyticsValue: Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

extension AnalyticsValue: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public init(stringInterpolation: DefaultStringInterpolation) {
        self = .string(String(stringInterpolation: stringInterpolation))
    }
}

extension AnalyticsValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension AnalyticsValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension AnalyticsValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

// MARK: - Convertible

/// A Swift value that can be an event parameter. It lets an app's event factories keep writing
/// `["kind": kind, "has_logo": hasLogo]` with variables, not only literals, while anything else
/// (a `Date`, an optional, a model) fails to compile instead of reaching the reports as a
/// description string.
public protocol AnalyticsValueConvertible {
    var analyticsValue: AnalyticsValue { get }
}

extension AnalyticsValue: AnalyticsValueConvertible {
    public var analyticsValue: AnalyticsValue { self }
}

extension String: AnalyticsValueConvertible {
    public var analyticsValue: AnalyticsValue { .string(self) }
}

extension Int: AnalyticsValueConvertible {
    public var analyticsValue: AnalyticsValue { .int(self) }
}

extension Double: AnalyticsValueConvertible {
    public var analyticsValue: AnalyticsValue { .double(self) }
}

extension Bool: AnalyticsValueConvertible {
    public var analyticsValue: AnalyticsValue { .bool(self) }
}
