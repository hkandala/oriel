import Foundation

public enum HerdrError: Error, Equatable, Sendable {
    /// No herdr binary on the machine.
    case notFound
    /// herdr is too old.
    case unsupported(String)
    /// herdr did not answer within the request's timeout.
    case timeout
    /// herdr answered with an error.
    case herdr(code: String, message: String)
    /// The command failed or printed something we cannot read.
    case failed(String)
    /// ssh needs an answer (a password, a code, a host key) to reach the machine; ssh's text. Only the user's
    /// Connect asks again.
    case disconnected(String)
    /// herdr changed nothing, for this reason (`same_tab`, `cross_tab`, `zoomed_tab`).
    case refused(String)
}

extension HerdrError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound: "herdr is not installed"
        case let .unsupported(message), let .failed(message), let .disconnected(message): message
        case .timeout: "herdr did not answer"
        case let .herdr(code, message): "\(message) (\(code))"
        case .refused("zoomed_tab"): "The tab is zoomed in herdr"
        case let .refused(reason): "herdr changed nothing (\(reason))"
        }
    }
}
