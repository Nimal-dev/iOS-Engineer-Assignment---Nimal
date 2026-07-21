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
    
    // Memory Optimization: Pre-cached shared SCNGeometry & SCNMaterial to avoid runtime allocations
    private lazy var tickGeometry: SCNPlane = {
        let plane = SCNPlane(width: 0.05, height: 0.05) // Slightly smaller, tighter tick
        
        // Multi-color palette: white checkmark, green background circle
        let config = UIImage.SymbolConfiguration(paletteColors: [.white, .systemGreen])
        // Fallback to regular green tint if palette fails
        let image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config) ?? 
                    UIImage(systemName: "checkmark.circle.fill")?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
        
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.isDoubleSided = true
        material.transparent.contents = image // Ensure background remains transparent
        plane.materials = [material]
        
        return plane
    }()
    
    private lazy var sharedBillboardConstraint: SCNBillboardConstraint = {
        let constraint = SCNBillboardConstraint()
        constraint.freeAxes = .all
        return constraint
    }()
    
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
            
            var worldTransform: simd_float4x4?
            
            // Raycast query: 1. Try estimated plane
            let query = arView.raycastQuery(from: centerPoint, allowing: .estimatedPlane, alignment: .any)
            if let result = query.flatMap({ arView.session.raycast($0).first }) {
                worldTransform = result.worldTransform
            } else {
                // 2. Fall back to feature points to hit organic objects (like a shoe/chappal) exactly on their surface
                let hitTestResults = arView.hitTest(centerPoint, types: [.featurePoint])
                if let firstHit = hitTestResults.first {
                    worldTransform = firstHit.worldTransform
                }
            }
            
            guard let finalTransform = worldTransform else { continue }
            
            let position = simd_make_float3(finalTransform.columns.3.x, finalTransform.columns.3.y, finalTransform.columns.3.z)
            
            // Non-Duplication Check
            if isDuplicate(at: position) {
                continue
            }
            
            // Add a new ARAnchor at this position
            let newAnchor = ARAnchor(transform: finalTransform)
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
        let tickNode = SCNNode(geometry: tickGeometry)
        tickNode.constraints = [sharedBillboardConstraint]
        node.addChildNode(tickNode)
        
        return node
    }
}
#endif
