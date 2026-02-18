import Foundation
import FirebaseAuth
import FirebaseCore
import AuthenticationServices

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var firebaseUser: FirebaseAuth.User?
    @Published var backendToken: String?
    @Published var backendUser: AuthUserInfo?

    private var authStateHandle: AuthStateDidChangeListenerHandle?

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

    // MARK: - Sign Out

    func signOut() throws {
        try Auth.auth().signOut()
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
        guard let user = firebaseUser else { return }
        await exchangeToken(user: user)
    }
}
