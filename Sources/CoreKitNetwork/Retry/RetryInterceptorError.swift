import Foundation

enum RetryInterceptorError: LocalizedError {
    case maxAttemptsExceeded

    var errorDescription: String? {
        switch self {
        case .maxAttemptsExceeded:
            return "Maximum number of attempts exceeded"
        }
    }
}
