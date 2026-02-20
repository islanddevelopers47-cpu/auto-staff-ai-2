import Foundation
import FirebaseAuth
import FirebaseCore
import AuthenticationServices
import GoogleSignIn
import CryptoKit

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var firebaseUser: FirebaseAuth.User?
    @Published var backendToken: String?
    @Published var backendUser: AuthUserInfo?

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    private init() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.firebaseUser = user
                if let user = user {
                    await self?.exchangeToken(user: user)
                } else {
                    self?.backendToken = nil
                    self?.backendUser = nil
                }
            }
        }
    }

    var isAuthenticated: Bool {
        firebaseUser != nil && backendToken != nil
    }

    var currentUser: AppUser? {
        guard let user = firebaseUser else { return nil }
        return AppUser(
            uid: user.uid,
            email: user.email,
            displayName: user.displayName ?? backendUser?.displayName,
            photoURL: user.photoURL
        )
    }

    // MARK: - Email/Password Sign In

    func signInWithEmail(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        firebaseUser = result.user
        await exchangeToken(user: result.user)
    }

    func signUpWithEmail(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        firebaseUser = result.user
        await exchangeToken(user: result.user)
    }

    // MARK: - Sign in with Google

    func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.missingClientID
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw AuthError.noRootViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingIDToken
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )

        let authResult = try await Auth.auth().signIn(with: credential)
        firebaseUser = authResult.user
        await exchangeToken(user: authResult.user)
    }

    // MARK: - Sign in with Apple

    func handleAppleSignIn(authorization: ASAuthorization) async throws {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.invalidCredential
        }

        guard let nonce = currentNonce else {
            throw AuthError.invalidState
        }

        guard let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw AuthError.missingIDToken
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )

        let authResult = try await Auth.auth().signIn(with: credential)
        firebaseUser = authResult.user
        await exchangeToken(user: authResult.user)
    }

    func prepareAppleSignInRequest() -> ASAuthorizationAppleIDRequest {
        let nonce = randomNonceString()
        currentNonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        return request
    }

    // MARK: - Sign Out

    func signOut() throws {
        try Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        firebaseUser = nil
        backendToken = nil
        backendUser = nil
    }

    // MARK: - Token Exchange

    func exchangeToken(user: FirebaseAuth.User) async {
        do {
            let idToken = try await user.getIDToken()
            let response = try await APIService.shared.exchangeFirebaseToken(idToken: idToken)
            backendToken = response.token
            backendUser = response.user
        } catch {
            print("[AuthService] Token exchange failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Refresh Token

    func refreshTokenIfNeeded() async {
        guard backendToken == nil, let user = firebaseUser else { return }
        await exchangeToken(user: user)
    }

    // MARK: - Helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case missingClientID
    case noRootViewController
    case missingIDToken
    case invalidCredential
    case invalidState

    var errorDescription: String? {
        switch self {
        case .missingClientID: return "Missing Firebase client ID"
        case .noRootViewController: return "No root view controller found"
        case .missingIDToken: return "Missing ID token"
        case .invalidCredential: return "Invalid credential"
        case .invalidState: return "Invalid state - nonce not found"
        }
    }
}
