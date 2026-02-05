import Foundation
import AuthenticationServices
import AppKit

@MainActor
final class CloudAuthManager: NSObject {
    private var continuation: CheckedContinuation<Void, Error>?
    private var anchorProvider: (() -> ASPresentationAnchor?)?
    private(set) var lastUserIdentifier: String?
    private(set) var lastIdentityToken: String?

    enum CloudAuthError: Error, LocalizedError {
        case alreadyInProgress
        case missingCredential

        var errorDescription: String? {
            switch self {
            case .alreadyInProgress:
                return "Sign-in is already in progress."
            case .missingCredential:
                return "Sign-in did not return a valid credential."
            }
        }
    }

    init(anchorProvider: (() -> ASPresentationAnchor?)? = nil) {
        self.anchorProvider = anchorProvider
    }

    func authenticate() async throws {
        guard continuation == nil else { throw CloudAuthError.alreadyInProgress }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = []
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension CloudAuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { continuation = nil }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: CloudAuthError.missingCredential)
            return
        }
        lastUserIdentifier = credential.user
        if let tokenData = credential.identityToken {
            lastIdentityToken = String(data: tokenData, encoding: .utf8)
        } else {
            lastIdentityToken = nil
        }
        continuation?.resume()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        defer { continuation = nil }
        continuation?.resume(throwing: error)
    }
}

extension CloudAuthManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let anchor = anchorProvider?() {
            return anchor
        }
        return NSApplication.shared.mainWindow
            ?? NSApplication.shared.keyWindow
            ?? ASPresentationAnchor()
    }
}
