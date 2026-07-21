#if os(iOS)
import SwiftUI
import ARKit
import Vision

struct ARCameraView: UIViewRepresentable {
    
    @Binding var arView: ARSCNView?
    var sessionDelegate: ARSessionDelegate
    var sceneDelegate: ARSCNViewDelegate
    
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        
        // Configure AR View
        view.session.delegate = sessionDelegate
        view.delegate = sceneDelegate
        view.automaticallyUpdatesLighting = true
        view.showsStatistics = false
        
        // Pass the reference back to the parent
        DispatchQueue.main.async {
            self.arView = view
        }
        
        // Configure Session
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        
        // Memory Optimization: Disable environment texturing cube maps to save ~50MB RAM
        configuration.environmentTexturing = .none
        
        // Run session
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        return view
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Handle updates if needed
    }
}
#endif
