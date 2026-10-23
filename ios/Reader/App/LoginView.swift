import SwiftUI

/// Signing in: the name, then email (or Google, when it's offered).
struct LoginView: View {
    /// Google sign-in is hidden for now; with only email there's nothing to choose.
    static let offersGoogle = false

    private enum Step { case choose, email }

    @State private var step = offersGoogle ? Step.choose : .email
    /// How much of the screen the keyboard covers, 0 when it's down. Only grows while it's up,
    /// so the form doesn't bob when the keyboard changes a little between fields.
    @State private var keyboard: CGFloat = 0
    @State private var formHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            // At a set height, not centred: centred, it moved with every keyboard. The keyboard
            // is kept out of the layout and only lifts the form as far as it has to, so the
            // buttons under the fields stay in sight, with a little room above the keyboard.
            let top = max(40, min(geo.size.height * 0.22, geo.size.height - 560))
            let keyboardTop = geo.size.height + geo.safeAreaInsets.bottom - keyboard
            let lift = keyboard > 0 ? max(0, top + formHeight + 16 - keyboardTop) : 0
            VStack(spacing: 0) {
                Text("Reader")
                    .font(.custom(AppFont.family, size: 48, relativeTo: .largeTitle).weight(.medium))
                    .accessibilityAddTraits(.isHeader)
                Text("Every book, everywhere.")
                    .font(.custom(AppFont.family, size: 17, relativeTo: .body))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                // Both steps share one slot, so it keeps the taller one's height and nothing above it moves.
                ZStack {
                    if Self.offersGoogle {
                        Panel(active: step == .choose) {
                            ChooseStep { step = .email }
                        }
                    }
                    Panel(active: step == .email) {
                        EmailStep(active: step == .email, onBack: Self.offersGoogle ? { step = .choose } : nil)
                    }
                }
                .padding(.top, 40)
            }
            .frame(maxWidth: 384)
            .padding(.horizontal, 24)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { formHeight = $0 }
            .padding(.top, top)
            .offset(y: -lift)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(.rect)
            // A tap off the fields puts the keyboard away.
            .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
        .ignoresSafeArea(.keyboard)
        .background(Color(uiColor: .systemBackground))
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect, frame.height > keyboard else { return }
            withAnimation(.settle(0.35)) { keyboard = frame.height }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.settle(0.35)) { keyboard = 0 }
        }
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

extension Animation {
    /// Quick to start, long to settle.
    static func settle(_ duration: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: duration) }
}

/// One of the steps that trade places in the slot under the title.
private struct Panel<Content: View>: View {
    var active: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .opacity(active ? 1 : 0)
            .offset(y: active ? 0 : -10)
            .scaleEffect(active ? 1 : 0.98)
            .animation(.settle(0.35), value: active)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
    }
}

private struct ChooseStep: View {
    var onEmail: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var waiting = false
    @State private var error = ""
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 12) {
            Button(action: google) {
                HStack(spacing: 12) {
                    if waiting { ProgressView() } else { GoogleMark().frame(width: 20, height: 20) }
                    Text(waiting ? "Waiting for Google…" : "Continue with Google")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x1f1f1f))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white, in: .capsule)
                .overlay(Capsule().strokeBorder(.black.opacity(scheme == .dark ? 0 : 0.15)))
                .contentShape(.capsule)
            }
            .buttonStyle(PressStyle())
            .disabled(waiting)

            Button(action: onEmail) {
                HStack(spacing: 12) {
                    Image(systemName: "envelope")
                    Text("Continue with email")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                // Beside Google's white button in the dark, a second white one would look the same.
                .background(scheme == .dark ? Color.white.opacity(0.14) : .black, in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(PressStyle())

            if !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .animation(.settle(0.35), value: error)
        .onDisappear { task?.cancel() }
    }

    private func google() {
        error = ""
        waiting = true
        task = Task {
            defer { waiting = false }
            do {
                if let session = try await GoogleSignIn().run() {
                    AppModel.shared.signIn(session)
                }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct EmailStep: View {
    private enum Mode { case signIn, signUp }

    var active: Bool
    var onBack: (() -> Void)?

    @Environment(\.colorScheme) private var scheme
    @State private var mode = Mode.signIn
    @State private var email = AppModel.shared.session?.email ?? ""
    @State private var password = ""
    @State private var error = ""
    @State private var busy = false
    @FocusState private var field: Int?

    var body: some View {
        VStack(spacing: 12) {
            // `.username`, not `.emailAddress`: it pairs with the password for autofill and gets
            // the same bar over the keyboard, so the keyboard keeps its height between the two.
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($field, equals: 0)
                .submitLabel(.next)
                .onSubmit { field = 1 }
                .modifier(FieldStyle { field = 0 })
            SecureField("Password", text: $password)
                .textContentType(mode == .signIn ? .password : .newPassword)
                .focused($field, equals: 1)
                .submitLabel(.go)
                .onSubmit(submit)
                .modifier(FieldStyle { field = 1 })

            Button(action: submit) {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(scheme == .dark ? .black : .white) }
                    Text(mode == .signIn ? "Sign in" : "Create account")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(scheme == .dark ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(scheme == .dark ? Color.white.opacity(0.92) : .black, in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(PressStyle())
            .disabled(busy)

            HStack {
                if onBack != nil {
                    Button(action: back) {
                        Label("Back", systemImage: "arrow.left")
                    }
                }
                Spacer()
                Button(mode == .signIn ? "Create account" : "I have an account") {
                    mode = mode == .signIn ? .signUp : .signIn
                    error = ""
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            .padding(.horizontal, 4)

            // Under everything, with room kept for two lines, so it coming and going doesn't
            // move the button or change how far the keyboard lifts the form.
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .frame(minHeight: 36, alignment: .top)
                .opacity(error.isEmpty ? 0 : 1)
                .animation(.settle(0.35), value: error)
        }
        .onChange(of: active) {
            // Focus the first field once this step has taken its turn.
            if active {
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    if active { field = 0 }
                }
            } else {
                field = nil
            }
        }
    }

    private func back() {
        field = nil
        error = ""
        onBack?()
    }

    private func submit() {
        guard !busy else { return }
        guard !email.isEmpty, !password.isEmpty else {
            field = email.isEmpty ? 0 : 1
            return
        }
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

private struct FieldStyle: ViewModifier {
    /// Focuses the field; the text field itself is only a line tall, so a tap on the rest of
    /// the capsule would otherwise miss it.
    var focus: () -> Void

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(Color(uiColor: .secondarySystemBackground), in: .capsule)
            .overlay(Capsule().strokeBorder(.primary.opacity(0.1)))
            .contentShape(.capsule)
            .onTapGesture(perform: focus)
    }
}

/// Sinks a little while held.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.settle(0.25), value: configuration.isPressed)
    }
}

/// Google's "G": four arcs of a ring and the bar into its middle.
private struct GoogleMark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 48
            ctx.scaleBy(x: s, y: s)
            let center = CGPoint(x: 24, y: 24)
            func arc(_ from: Double, _ to: Double, _ hex: UInt32) {
                let path = Path { p in p.addRelativeArc(center: center, radius: 19, startAngle: .degrees(from), delta: .degrees(to - from)) }
                ctx.stroke(path, with: .color(Color(hex: hex)), lineWidth: 10)
            }
            arc(-140, -42, 0xea4335)
            arc(150, 220, 0xfbbc05)
            arc(42, 150, 0x34a853)
            arc(0, 42, 0x4285f4)
            ctx.fill(Path(CGRect(x: 24, y: 19.5, width: 22, height: 9)), with: .color(Color(hex: 0x4285f4)))
        }
        .accessibilityHidden(true)
    }
}
