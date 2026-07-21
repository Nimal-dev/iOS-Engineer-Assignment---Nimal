#if os(iOS)
import Foundation
import UIKit
import SceneKit
import ARKit
import Vision
import Combine
import simd

struct TrackedItem {
    let anchorIdentifier: UUID
    let position: simd_float3
}

class ScannerViewModel: NSObject, ObservableObject, ARSessionDelegate, ARSCNViewDelegate, ProductDetectorDelegate {
    
    @Published var detectedProductCount: Int = 0
    @Published var isScanning: Bool = true
    @Published var feedbackMessage: String = "Scanning shelf..."
    
    var arView: ARSCNView?
    private var detectionService: ProductDetectionService
    private var trackedItems: [UUID: TrackedItem] = [:]
    private let itemLock = NSRecursiveLock()
    
    // Distance threshold in meters (15cm) to consider a product as "already scanned"
    private let duplicateDistanceThreshold: Float = 0.15
    
    override init() {
        self.detectionService = ProductDetectionService()
        super.init()
        self.detectionService.delegate = self
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isScanning else { return }
        detectionService.processBuffer(frame.capturedImage)
    }
    
    // MARK: - ProductDetectorDelegate
    
    func didDetectProducts(_ products: [DetectedProduct]) {
        guard let arView = arView, isScanning,
              let currentFrame = arView.session.currentFrame else { return }
        
        let screenWidth = arView.bounds.width
        let screenHeight = arView.bounds.height
        
        let orientation: UIInterfaceOrientation
        if #available(iOS 17.0, *) {
            orientation = arView.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        } else {
            orientation = arView.window?.windowScene?.interfaceOrientation ?? .portrait
        }
        
        for product in products {
            let rect = product.boundingBox
            
            // Convert from Vision [0, 1] (origin bottom-left)
            // to normalized camera frame coordinate system (origin top-left)
            let normalizedCenter = CGPoint(x: rect.midX, y: 1.0 - rect.midY)
            
            // Get the display transform mapping camera frame to screen viewport
            let transform = currentFrame.displayTransform(for: orientation, viewportSize: arView.bounds.size)
            let viewportPoint = normalizedCenter.applying(transform)
            
            // Map normalized viewport coordinates to actual pixel coordinates
            let centerPoint = CGPoint(x: viewportPoint.x * screenWidth, y: viewportPoint.y * screenHeight)
            
            // Raycast query: 1. Try existingPlaneGeometry for high stability, 2. Fall back to estimatedPlane
            var query = arView.raycastQuery(from: centerPoint, allowing: .existingPlaneGeometry, alignment: .any)
            var result = query.flatMap { arView.session.raycast($0).first }
            
            if result == nil {
                query = arView.raycastQuery(from: centerPoint, allowing: .estimatedPlane, alignment: .any)
                result = query.flatMap { arView.session.raycast($0).first }
            }
            
            guard let finalResult = result else { continue }
            
            let worldTransform = finalResult.worldTransform
            let position = simd_make_float3(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)
            
            // Non-Duplication Check
            if isDuplicate(at: position) {
                continue
            }
            
            // Add a new ARAnchor at this position
            let newAnchor = ARAnchor(transform: worldTransform)
            arView.session.add(anchor: newAnchor)
            
            // Track the item thread-safely
            let tracked = TrackedItem(anchorIdentifier: newAnchor.identifier, position: position)
            itemLock.lock()
            trackedItems[newAnchor.identifier] = tracked
            itemLock.unlock()
            
            DispatchQueue.main.async {
                self.detectedProductCount += 1
                self.feedbackMessage = "Product Detected"
                self.triggerHapticFeedback()
            }
        }
    }
    
    private func isDuplicate(at position: simd_float3) -> Bool {
        itemLock.lock()
        let items = Array(trackedItems.values)
        itemLock.unlock()
        
        for item in items {
            if simd_distance(position, item.position) < duplicateDistanceThreshold {
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
        itemLock.lock()
        let trackedItem = trackedItems[anchor.identifier]
        itemLock.unlock()
        
        guard trackedItem != nil else { return nil }
        
        let node = SCNNode()
        
        // Render ONLY the green tick mark plane (no 3D green box!)
        let plane = SCNPlane(width: 0.06, height: 0.06)
        
        let config = UIImage.SymbolConfiguration(pointSize: 100, weight: .bold)
        let image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)?
            .withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
        
        plane.firstMaterial?.diffuse.contents = image
        plane.firstMaterial?.isDoubleSided = true
        
        let tickNode = SCNNode(geometry: plane)
        
        // Billboard constraint so the tick mark ALWAYS faces the user's camera
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = .all
        tickNode.constraints = [billboardConstraint]
        
        node.addChildNode(tickNode)
        
        return node
    }
}
#endif
