import Foundation
import FirebaseAuth
import Combine

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var email = ""
    @Published var password = ""
    @Published var isSignUp = false

    private var cancellables = Set<AnyCancellable>()
    private let authService = AuthService.shared

    init() {
        // Observe auth state changes
        authService.$firebaseUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                guard let self = self else { return }
                if user != nil {
                    // Wait for backend token exchange
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        self.isAuthenticated = self.authService.isAuthenticated
                        self.isLoading = false
                    }
                } else {
                    self.isAuthenticated = false
                    self.isLoading = false
                }
            }
            .store(in: &cancellables)

        // Initial check after a brief delay for Firebase to initialize
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !self.isAuthenticated {
                self.isLoading = false
            }
        }
    }

    var currentUser: AppUser? {
        authService.currentUser
    }

    func signInWithEmail() async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter email and password"
            return
        }

        errorMessage = nil
        isLoading = true

        do {
            if isSignUp {
                try await authService.signUpWithEmail(email: email, password: password)
            } else {
                try await authService.signInWithEmail(email: email, password: password)
            }
            isAuthenticated = authService.isAuthenticated
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func signOut() {
        do {
            try authService.signOut()
            isAuthenticated = false
            StorageService.shared.clearAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
