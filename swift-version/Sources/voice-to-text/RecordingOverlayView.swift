import SwiftUI

struct RecordingOverlayView: View {
    @ObservedObject var stateManager: AppStateManager
    
    // Animation states
    @State private var isPulsing = false
    @State private var initializingRotation: Double = 0
    @State private var processingRotation: Double = 0
    
    var body: some View {
        Group {
            if stateManager.currentState == .recording || stateManager.currentState == .processing || stateManager.currentState == .initializing {
                HStack(spacing: 12) {
                    if stateManager.currentState == .initializing {
                        Image(systemName: "gearshape.2.fill")
                            .foregroundStyle(Theme.accent)
                            .rotationEffect(.degrees(initializingRotation))
                            .onAppear {
                                initializingRotation = 0
                                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                                    initializingRotation = 360
                                }
                            }
                        
                        Text("Initializing Model")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.navy)
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
                .frame(minWidth: (stateManager.currentState == .recording || stateManager.currentState == .processing) ? 230 : 200, minHeight: 48)
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
