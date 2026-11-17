internal extension DecodingError {
    var detailedDescription: String {
        switch self {
        case .keyNotFound(let key, let context):
            return "❌ Key '\(key.stringValue)' not found at: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(let type, let context):
            return "❌ Type mismatch: expected \(type) at: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return "❌ Value of type \(type) not found at: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context):
            return "❌ Data corrupted: \(context.debugDescription)"
        @unknown default:
            return "❌ Unknown decoding error"
        }
    }
}
