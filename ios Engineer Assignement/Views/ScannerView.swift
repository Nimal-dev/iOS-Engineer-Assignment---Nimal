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
            
            // UI Overlay
            VStack {
                // Top Bar
                HStack {
                    VStack(alignment: .leading) {
                        Text("Retail Scanner")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                        
                        Text(viewModel.feedbackMessage)
                            .font(.subheadline)
                            .foregroundColor(.green)
                            .shadow(radius: 1)
                    }
                    Spacer()
                    
                    // Counter Badge
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("\(viewModel.detectedProductCount)")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(20)
                }
                .padding()
                .padding(.top, 40)
                
                Spacer()
                
                // Scanning Reticle
                Image(systemName: "viewfinder")
                    .font(.system(size: 60, weight: .ultraLight))
                    .foregroundColor(viewModel.isScanning ? .green : .white)
                    .opacity(0.6)
                
                Spacer()
                
                // Bottom Controls
                HStack {
                    Spacer()
                    Button(action: {
                        viewModel.isScanning.toggle()
                        if viewModel.isScanning {
                            viewModel.feedbackMessage = "Scanning shelf..."
                        } else {
                            viewModel.feedbackMessage = "Paused"
                        }
                    }) {
                        Image(systemName: viewModel.isScanning ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    Spacer()
                }
                .padding(.bottom, 40)
            }
        }
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
    }
}
#endif
