#if os(iOS)
import SwiftUI
import ARKit

struct ScannerView: View {
    @StateObject private var viewModel = ScannerViewModel()
    
    var body: some View {
        ZStack {
            // AR Camera Feed
            ARCameraView(arView: $viewModel.arView,
                         sessionDelegate: viewModel,
                         sceneDelegate: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            // Dark Overlay Gradient Vignette for UI readability
            VStack {
                LinearGradient(colors: [Color.black.opacity(0.9), Color.black.opacity(0.4), Color.clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
                Spacer()
                LinearGradient(colors: [Color.clear, Color.black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
            }
            .edgesIgnoringSafeArea(.all)
            .allowsHitTesting(false)
            
            // UI Overlay
            VStack {
                // Sleek Dark Top Bar Card Container
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Retail Shelf Scanner")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill(viewModel.isScanning ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(viewModel.feedbackMessage)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.white.opacity(0.85))
                        }
                    }
                    
                    Spacer(minLength: 8)
                    
                    // Counter Badge
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.green)
                        
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(viewModel.detectedProductCount)")
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Text("DETECTED")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .foregroundColor(Color.white.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.6), radius: 12, x: 0, y: 4)
                )
                .padding(.horizontal, 16)
                .padding(.top, 54)
                
                Spacer()
                
                // Bottom Controls
                HStack {
                    Spacer()
                    Button(action: {
                        viewModel.isScanning.toggle()
                        if viewModel.isScanning {
                            viewModel.feedbackMessage = "Scanning shelf..."
                        } else {
                            viewModel.feedbackMessage = "Scanning Paused"
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: viewModel.isScanning ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .bold))
                            Text(viewModel.isScanning ? "PAUSE SCAN" : "RESUME SCAN")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(viewModel.isScanning ? Color.black.opacity(0.75) : Color.green.opacity(0.85))
                                .overlay(
                                    Capsule()
                                        .stroke(viewModel.isScanning ? Color.white.opacity(0.2) : Color.green, lineWidth: 1)
                                )
                        )
                        .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 4)
                    }
                    Spacer()
                }
                .padding(.bottom, 36)
            }
        }
        .preferredColorScheme(.dark)
    }
}
#else
import SwiftUI

struct ScannerView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "ipad.and.iphone")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("AR Scanner is only supported on iOS / iPadOS")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
