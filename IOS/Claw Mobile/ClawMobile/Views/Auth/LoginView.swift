import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showPassword = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.07, blue: 0.18),
                    Color(red: 0.08, green: 0.04, blue: 0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    Spacer().frame(height: 60)

                    // Logo
                    VStack(spacing: 12) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .orange.opacity(0.3), radius: 20)

                        Text("Claw Mobile")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)

                        Text("AI Assistant powered by on-device MLX")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    // Login form
                    VStack(spacing: 16) {
                        // Email field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email")
                                .font(.caption)
                                .foregroundColor(.gray)
                            TextField("", text: $authViewModel.email)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(10)
                                .foregroundColor(.white)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                        }

                        // Password field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.caption)
                                .foregroundColor(.gray)
                            HStack {
                                if showPassword {
                                    TextField("", text: $authViewModel.password)
                                        .textFieldStyle(.plain)
                                        .foregroundColor(.white)
                                } else {
                                    SecureField("", text: $authViewModel.password)
                                        .textFieldStyle(.plain)
                                        .foregroundColor(.white)
                                }
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                            .textContentType(.password)
                        }

                        // Error message
                        if let error = authViewModel.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }

                        // Sign in button
                        Button {
                            Task {
                                await authViewModel.signInWithEmail()
                            }
                        } label: {
                            HStack {
                                if authViewModel.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.8)
                                } else {
                                    Text(authViewModel.isSignUp ? "Create Account" : "Sign In")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(
                                LinearGradient(
                                    colors: [.orange, Color(red: 0.9, green: 0.4, blue: 0.1)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(authViewModel.isLoading)

                        // Toggle sign up / sign in
                        Button {
                            authViewModel.isSignUp.toggle()
                            authViewModel.errorMessage = nil
                        } label: {
                            Text(authViewModel.isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(16)
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
        }
    }
}
