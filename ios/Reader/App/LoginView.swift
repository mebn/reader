import SwiftUI

/// Signing in, made to look like the desktop app's: a book that reads itself over a desk
/// of bookish things, then Google or email.
struct LoginView: View {
    private enum Step { case choose, email }

    @State private var step = Step.choose

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    HeroBook(width: min(max(72, geo.size.height * 0.14), 128))
                    Headline().padding(.top, 28)
                    // Both steps share one slot, so it keeps the taller one's height and nothing above it moves.
                    ZStack {
                        Panel(active: step == .choose) {
                            ChooseStep { step = .email }
                        }
                        Panel(active: step == .email) {
                            EmailStep(active: step == .email) { step = .choose }
                        }
                    }
                    .padding(.top, 32)
                }
                .frame(maxWidth: 384)
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background {
            ZStack {
                Backdrop()
                FloatingObjects()
            }
            .ignoresSafeArea()
        }
    }
}

/// Soft colour that slowly wanders behind everything, over faintly ruled paper.
private struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var calm
    @State private var drift = false

    var body: some View {
        let dark = scheme == .dark
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Color(hex: dark ? 0x171411 : 0xfbf7ee)
                EllipticalGradient(colors: [Color(hex: dark ? 0x2c241d : 0xfff7e6), .clear], center: .top, endRadiusFraction: 0.6)
                blob(dark ? Color(hex: 0xc9532c).opacity(0.2) : Color(hex: 0xf0b98a).opacity(0.45), size: 360,
                     at: CGPoint(x: -96, y: size.height * 0.08), by: CGSize(width: 60, height: 40), duration: 16)
                blob(dark ? Color(hex: 0x46607f).opacity(0.25) : Color(hex: 0x9ec4b0).opacity(0.45), size: 380,
                     at: CGPoint(x: size.width + 80 - 380, y: size.height * 0.3), by: CGSize(width: -50, height: -30), duration: 19)
                blob(dark ? Color(hex: 0xe0a93c).opacity(0.12) : Color(hex: 0xf3d58a).opacity(0.45), size: 420,
                     at: CGPoint(x: size.width * 0.3, y: size.height + 160 - 420), by: CGSize(width: 40, height: -40), duration: 22)
                Canvas { ctx, size in
                    for y in stride(from: 31.0, to: size.height, by: 32) {
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color(red: 120 / 255, green: 100 / 255, blue: 80 / 255).opacity(0.08)))
                    }
                }
                .opacity(dark ? 0.6 : 0.35)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if !calm { drift = true } }
    }

    /// Wanders out by `by` and back over `duration` seconds, swelling on the way.
    private func blob(_ color: Color, size: CGFloat, at origin: CGPoint, by: CGSize, duration: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 64)
            .scaleEffect(drift ? 1.15 : 1)
            .offset(x: origin.x + (drift ? by.width : 0), y: origin.y + (drift ? by.height : 0))
            .animation(.easeInOut(duration: duration / 2).repeatForever(autoreverses: true), value: drift)
    }
}

private struct Headline: View {
    private static let title = "Reader"

    @State private var shown = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Array(Self.title.enumerated()), id: \.offset) { i, letter in
                    Text(String(letter))
                        .offset(y: shown ? 0 : 64)
                        .opacity(shown ? 1 : 0)
                        .animation(.settle(0.7).delay(0.45 + Double(i) * 0.06), value: shown)
                        .clipped()
                }
            }
            .font(.custom("Literata", size: 48, relativeTo: .largeTitle).weight(.medium))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.title)
            .accessibilityAddTraits(.isHeader)

            Text("Every book, everywhere.")
                .foregroundStyle(.secondary)
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 8)
                .animation(.settle(0.7).delay(0.95), value: shown)
        }
        .onAppear { shown = true }
    }
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

/// Rises into place after the title; each step of a column staggers after the last.
private struct Rise: ViewModifier {
    var index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .onAppear { withAnimation(.settle(0.6).delay(0.9 + Double(index) * 0.1)) { shown = true } }
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
                .overlay(Capsule().strokeBorder(.black.opacity(0.05)))
                .shadow(color: Color(red: 60 / 255, green: 40 / 255, blue: 20 / 255).opacity(0.35), radius: 12, y: 8)
                .contentShape(.capsule)
            }
            .buttonStyle(PressStyle())
            .disabled(waiting)
            .modifier(Rise(index: 0))

            Button(action: onEmail) {
                HStack(spacing: 12) {
                    Image(systemName: "envelope")
                    Text("Continue with email")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(scheme == .dark ? Color.white.opacity(0.1) : Color(hex: 0x2b2622), in: .capsule)
                .shadow(color: Color(red: 30 / 255, green: 20 / 255, blue: 10 / 255).opacity(scheme == .dark ? 0 : 0.6), radius: 12, y: 8)
                .contentShape(.capsule)
            }
            .buttonStyle(PressStyle())
            .modifier(Rise(index: 1))

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
    var onBack: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var mode = Mode.signIn
    @State private var email = AppModel.shared.session?.email ?? ""
    @State private var password = ""
    @State private var error = ""
    @State private var busy = false
    @FocusState private var field: Int?

    var body: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($field, equals: 0)
                .submitLabel(.next)
                .onSubmit { field = 1 }
                .modifier(FieldStyle())
            SecureField("Password", text: $password)
                .textContentType(mode == .signIn ? .password : .newPassword)
                .focused($field, equals: 1)
                .submitLabel(.go)
                .onSubmit(submit)
                .modifier(FieldStyle())

            if !error.isEmpty {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(scheme == .dark ? .black : .white) }
                    Text(mode == .signIn ? "Sign in" : "Create account")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(scheme == .dark ? Color(hex: 0x171411) : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(scheme == .dark ? Color(hex: 0xf1ece4) : Color(hex: 0x2b2622), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(PressStyle())
            .disabled(busy)

            HStack {
                Button(action: back) {
                    Label("Back", systemImage: "arrow.left")
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
        onBack()
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
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(.ultraThinMaterial, in: .capsule)
            .background(scheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.8), in: .capsule)
            .overlay(Capsule().strokeBorder(.primary.opacity(0.1)))
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
