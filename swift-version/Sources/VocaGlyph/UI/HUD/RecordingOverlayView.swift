import SwiftUI

struct RecordingOverlayView: View {
    @ObservedObject var stateManager: AppStateManager

    // Animation states
    @State private var isPulsing = false
    @State private var initializingRotation: Double = 0
    @State private var processingRotation: Double = 0

    var body: some View {
        Group {
            if stateManager.currentState == .recording || stateManager.currentState == .processing || stateManager.currentState == .initializing || stateManager.notReadyMessage != nil {
                ZStack {
                    // ── Main pill content ────────────────────────────────────
                    HStack(spacing: 12) {
                        if stateManager.currentState == .initializing {
                            // Spinning gear + progress row
                            VStack(spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: "gearshape.2.fill")
                                        .foregroundStyle(Theme.accent)
                                        .rotationEffect(.degrees(initializingRotation))
                                        .onAppear {
                                            initializingRotation = 0
                                            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                                                initializingRotation = 360
                                            }
                                        }

                                    Text("Loading Model")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.navy)
                                }

                                // Progress bar: .overlay on the gray track ensures the blue
                                // fill inherits its exact bounds. Using ZStack+GeometryReader
                                // was placing them in separate layout passes, making two
                                // visually distinct bars.
                                Capsule()
                                    .fill(Color.black.opacity(0.08))
                                    .frame(height: 3)
                                    .overlay(alignment: .leading) {
                                        GeometryReader { geo in
                                            Capsule()
                                                .fill(Theme.accent)
                                                .frame(
                                                    width: geo.size.width * stateManager.whisperLoadingProgress,
                                                    height: 3
                                                )
                                        }
                                        .frame(height: 3)
                                        .animation(
                                            stateManager.whisperLoadingProgress > 0
                                                ? .linear(duration: 0.5)
                                                : .none,
                                            value: stateManager.whisperLoadingProgress
                                        )
                                    }

                                // ETA label
                                if stateManager.whisperLoadingETA > 1 {
                                    Text("~\(stateManager.whisperLoadingETA)s remaining")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.textMuted)
                                }
                            }
                            .padding(.vertical, 4)

                        } else if stateManager.currentState == .recording {
                            WaveformView()
                        } else if stateManager.currentState == .processing {
                            WaveformView()

                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(processingRotation))
                                .onAppear {
                                    processingRotation = 0
                                    withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                                        processingRotation = 360
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .frame(width: 230, height: stateManager.currentState == .initializing ? 72 : 48)

                    // ── "Not ready" banner (overlaid at top of pill) ─────────
                    if let message = stateManager.notReadyMessage {
                        VStack {
                            Text(message)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.82))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            Spacer()
                        }
                        .frame(width: 230)
                        .offset(y: -52)
                        .animation(.easeInOut(duration: 0.2), value: stateManager.notReadyMessage != nil)
                    }
                }
                .background(
                    Group {
                        if stateManager.currentState == .recording || stateManager.currentState == .processing {
                            Capsule()
                                .fill(Color(red: 0.05, green: 0.08, blue: 0.12))
                                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                        } else {
                            Capsule()
                                .fill(Theme.background.opacity(0.8))
                                .background(.ultraThinMaterial, in: Capsule())
                                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                        }
                    }
                )
                .overlay(
                    Group {
                        if stateManager.currentState == .recording || stateManager.currentState == .processing {
                            Capsule()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        } else {
                            Capsule()
                                .stroke(Theme.textMuted.opacity(0.4), lineWidth: 1)
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }
}

struct WaveformView: View {
    let barCount = 28
    @State private var heights: [CGFloat] = Array(repeating: 10, count: 28)
    @State private var opacities: [Double] = Array(repeating: 0.8, count: 28)
    
    let timer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(opacities[index]))
                    .frame(width: 1.5, height: heights[index])
                    .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: heights[index])
            }
        }
        .frame(height: 16)
        .onReceive(timer) { _ in
            for i in 0..<barCount {
                heights[i] = CGFloat.random(in: 4...16)
                opacities[i] = Double.random(in: 0.5...1.0)
            }
        }
    }
}
