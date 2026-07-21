#if os(iOS)
import Foundation
import UIKit
import SceneKit
import ARKit
import Vision
import Combine
import simd

class ScannerViewModel: NSObject, ObservableObject, ARSessionDelegate, ARSCNViewDelegate, ProductDetectorDelegate {
    
    @Published var detectedProductCount: Int = 0
    @Published var isScanning: Bool = true
    @Published var feedbackMessage: String = "Scanning shelf..."
    
    var arView: ARSCNView?
    private var detectionService: ProductDetectionService
    private var knownAnchors: [UUID: ARAnchor] = [:]
    
    // Distance threshold in meters (e.g. 15cm) to consider a product as "already scanned"
    private let duplicateDistanceThreshold: Float = 0.15
    
    override init() {
        self.detectionService = ProductDetectionService()
        super.init()
        self.detectionService.delegate = self
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isScanning else { return }
        // Pass the frame to our Vision service
        detectionService.processFrame(frame)
    }
    
    // MARK: - ProductDetectorDelegate
    
    func didDetectProducts(_ products: [DetectedProduct]) {
        guard let arView = arView, isScanning else { return }
        
        for product in products {
            // Convert 2D bounding box to a center point in screen coordinates
            let rect = product.boundingBox
            // Vision returns coordinates normalized to [0,1] with origin at bottom-left
            let screenWidth = arView.bounds.width
            let screenHeight = arView.bounds.height
            
            // Adjust coordinates from Vision to UIKit/SceneKit (top-left origin)
            let x = (1.0 - rect.origin.y - rect.height / 2.0) * screenWidth
            let y = (rect.origin.x + rect.width / 2.0) * screenHeight
            let centerPoint = CGPoint(x: x, y: y)
            
            // Perform raycast from center point to find 3D location on a physical surface
            guard let query = arView.raycastQuery(from: centerPoint, allowing: .estimatedPlane, alignment: .any),
                  let result = arView.session.raycast(query).first else {
                continue
            }
            
            let worldTransform = result.worldTransform
            let position = simd_make_float3(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)
            
            // Phase 3: Non-Duplication Logic
            if isDuplicate(position: position) {
                continue // Already scanned this area
            }
            
            // Add a new ARAnchor at this position
            let newAnchor = ARAnchor(transform: worldTransform)
            arView.session.add(anchor: newAnchor)
            
            // Track the anchor to prevent duplicates
            knownAnchors[newAnchor.identifier] = newAnchor
            
            DispatchQueue.main.async {
                self.detectedProductCount += 1
                self.triggerHapticFeedback()
            }
        }
    }
    
    private func isDuplicate(position: simd_float3) -> Bool {
        for (_, anchor) in knownAnchors {
            let anchorPos = simd_make_float3(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
            let distance = simd_distance(position, anchorPos)
            if distance < duplicateDistanceThreshold {
                return true
            }
        }
        return false
    }
    
    private func triggerHapticFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        // Only provide nodes for our custom added anchors (not plane anchors etc.)
        guard knownAnchors[anchor.identifier] != nil else { return nil }
        
        // Phase 4: On-Camera AR Visuals
        let node = SCNNode()
        
        // 1. Create a bounding box (e.g., a green thin frame)
        let boxGeometry = SCNBox(width: 0.1, height: 0.15, length: 0.02, chamferRadius: 0.0)
        boxGeometry.firstMaterial?.diffuse.contents = UIColor.clear
        
        let outlineMaterial = SCNMaterial()
        outlineMaterial.diffuse.contents = UIColor.green.withAlphaComponent(0.8)
        outlineMaterial.isDoubleSided = true
        
        let edgeNode = SCNNode(geometry: boxGeometry)
        edgeNode.geometry?.materials = [outlineMaterial, outlineMaterial, outlineMaterial, outlineMaterial, outlineMaterial, outlineMaterial]
        
        // Let's create a wireframe-like appearance by adding a border.
        // For simplicity in SceneKit, a translucent green box works well as a highlight.
        
        // 2. Create the Tick mark
        let plane = SCNPlane(width: 0.05, height: 0.05)
        
        // Using SF Symbols for the tick mark (requires generating an image from UIImage)
        let config = UIImage.SymbolConfiguration(pointSize: 100, weight: .bold)
        let image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)?.withTintColor(.green, renderingMode: .alwaysOriginal)
        
        plane.firstMaterial?.diffuse.contents = image
        plane.firstMaterial?.isDoubleSided = true
        
        let tickNode = SCNNode(geometry: plane)
        // Position tick slightly in front of the box
        tickNode.position = SCNVector3(0, 0, 0.02)
        
        // Billboard constraint so the tick always faces the camera
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = .all
        tickNode.constraints = [billboardConstraint]
        
        node.addChildNode(edgeNode)
        node.addChildNode(tickNode)
        
        return node
    }
}
#endif
