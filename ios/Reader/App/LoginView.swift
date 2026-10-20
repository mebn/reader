import SwiftUI

struct LoginView: View {
    private enum Mode { case signIn, signUp }

    @State private var mode = Mode.signIn
    @State private var email = AppModel.shared.session?.email ?? ""
    @State private var password = ""
    @State private var error = ""
    @State private var busy = false
    @State private var appeared = false
    @FocusState private var field: Int?

    var body: some View {
        ZStack {
            // A warm wash for the glass to sit on.
            LinearGradient(colors: [Color(uiColor: UIColor(hex: 0xebdcc0)), Color(uiColor: UIColor(hex: 0xe1e8dc)), Color(uiColor: UIColor(hex: 0x6fb3f0)).opacity(0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Reader")
                    .font(.custom("Literata", size: 44, relativeTo: .largeTitle).weight(.medium))
                    .padding(.bottom, 18)

                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 12) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($field, equals: 0)
                            .submitLabel(.next)
                            .onSubmit { field = 1 }
                            .padding(.horizontal, 20)
                            .frame(height: 52)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        SecureField("Password", text: $password)
                            .textContentType(mode == .signIn ? .password : .newPassword)
                            .focused($field, equals: 1)
                            .submitLabel(.go)
                            .onSubmit(submit)
                            .padding(.horizontal, 20)
                            .frame(height: 52)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }

                if !error.isEmpty {
                    Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }

                Button(action: submit) {
                    Group {
                        if busy { ProgressView() } else { Text(mode == .signIn ? "Sign in" : "Create account") }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(busy || email.isEmpty || password.isEmpty)
                .padding(.top, 6)

                Button(mode == .signIn ? "Create account" : "I have an account") {
                    withAnimation(.smooth) { mode = mode == .signIn ? .signUp : .signIn }
                    error = ""
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            }
            .frame(maxWidth: 340)
            .padding(24)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
        }
        .onAppear { withAnimation(.smooth(duration: 0.5)) { appeared = true } }
    }

    private func submit() {
        guard !busy, !email.isEmpty, !password.isEmpty else { return }
        if mode == .signUp && password.count < 8 {
            error = "Password must be at least 8 characters"
            return
        }
        busy = true
        error = ""
        Task {
            defer { busy = false }
            do {
                let server = Session.defaultServer
                let auth = mode == .signIn ? API.login : API.register
                let (token, user) = try await auth(server, email, password, DeviceInfo.current)
                AppModel.shared.signIn(Session(serverUrl: server, token: token, email: user.email))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
