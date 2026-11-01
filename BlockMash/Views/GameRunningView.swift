import SwiftUI

struct GameRunningView: View {
    let game: GameEntry
    let launcher: GameLauncher
    let onExit: () -> Void

    @State private var animationPhase: Double = 0
    @State private var fpsTick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var showingOverlay = true
    @State private var elapsedSeconds: Int = 0

    var body: some View {
        ZStack {
            animatedBackground
                .ignoresSafeArea()

            if showingOverlay {
                overlay
            }
        }
        .statusBarHidden()
        .onTapGesture {
            withAnimation { showingOverlay.toggle() }
        }
        .onReceive(fpsTick) { _ in
            launcher.simulateFrameTick()
            elapsedSeconds += 1
        }
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                animationPhase = 1
            }
        }
    }

    private var animatedBackground: some View {
        let base = colorForGame(game)
        return ZStack {
            LinearGradient(
                colors: [base.opacity(0.9), base.opacity(0.4), .black],
                startPoint: UnitPoint(x: animationPhase, y: 0),
                endPoint: UnitPoint(x: 1 - animationPhase, y: 1)
            )

            ForEach(0..<30, id: \.self) { i in
                Circle()
                    .fill(base.opacity(0.15))
                    .frame(width: CGFloat(20 + i * 3))
                    .offset(
                        x: CGFloat(sin(animationPhase * .pi * 2 + Double(i)) * 150),
                        y: CGFloat(cos(animationPhase * .pi * 2 + Double(i) * 0.7) * 300)
                    )
                    .blur(radius: 8)
            }
        }
    }

    private var overlay: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        badge("\(Int(launcher.fps)) FPS", icon: "speedometer")
                        badge(formattedElapsed, icon: "clock.fill")
                    }
                }
                Spacer()
                Button {
                    onExit()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white, .black.opacity(0.4))
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding()

            Spacer()

            VStack(spacing: 6) {
                Text("Tap screen to toggle overlay")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Text("Rendering • Metal 3 • \(game.titleId.isEmpty ? "no title id" : game.titleId)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.bottom, 32)
        }
        .transition(.opacity)
    }

    private func badge(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption.monospaced())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.3))
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }

    private var formattedElapsed: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func colorForGame(_ game: GameEntry) -> Color {
        let colors: [Color] = [.purple, .blue, .indigo, .pink, .orange, .teal, .mint, .cyan]
        let hash = abs(game.title.hashValue)
        return colors[hash % colors.count]
    }
}
