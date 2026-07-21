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
    
    // Memory Optimization: Pre-cached shared SCNGeometry & SCNMaterial components
    private lazy var backgroundGeometry: SCNPlane = {
        let plane = SCNPlane(width: 0.05, height: 0.05)
        plane.cornerRadius = 0.025 // Perfect circle!
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.15, green: 0.68, blue: 0.37, alpha: 1.0) // Vibrantly green
        material.isDoubleSided = true
        plane.materials = [material]
        return plane
    }()
    
    private lazy var checkmarkGeometry: SCNPlane = {
        let plane = SCNPlane(width: 0.03, height: 0.03)
        let config = UIImage.SymbolConfiguration(pointSize: 100, weight: .bold)
        let image = UIImage(systemName: "checkmark", withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.isDoubleSided = true
        material.transparent.contents = image // Keep transparent background clean
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
            
            // 1. Try hitting the exact physical feature points on the object (precise for organic shapes like a shoe/chappal)
            let hitTestResults = arView.hitTest(centerPoint, types: [.featurePoint])
            if let firstHit = hitTestResults.first {
                worldTransform = firstHit.worldTransform
            }
            
            // 2. Fall back to estimated plane if feature point test yields no hits
            if worldTransform == nil {
                let query = arView.raycastQuery(from: centerPoint, allowing: .estimatedPlane, alignment: .any)
                if let result = query.flatMap({ arView.session.raycast($0).first }) {
                    worldTransform = result.worldTransform
                }
            }
            
            guard var finalTransform = worldTransform else { continue }
            
            // Distance Check: Filter out objects too close to camera or too far away (avoids giant/micro ticks)
            let cameraPosition = currentFrame.camera.transform.columns.3
            let objectPosition = finalTransform.columns.3
            let distance = simd_distance(simd_make_float3(cameraPosition.x, cameraPosition.y, cameraPosition.z),
                                         simd_make_float3(objectPosition.x, objectPosition.y, objectPosition.z))
            
            guard distance > 0.3 && distance < 4.0 else { continue }
            
            // Reset rotation to align perfectly with the world coordinate axes.
            // This prevents weird anchor tilts and ensures billboard constraints rotate properly.
            finalTransform.columns.0 = simd_make_float4(1, 0, 0, 0)
            finalTransform.columns.1 = simd_make_float4(0, 1, 0, 0)
            finalTransform.columns.2 = simd_make_float4(0, 0, 1, 0)
            
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
        
        let rootNode = SCNNode()
        let containerNode = SCNNode()
        
        // Circular green background
        let bgNode = SCNNode(geometry: backgroundGeometry)
        
        // White checkmark foreground
        let tickNode = SCNNode(geometry: checkmarkGeometry)
        tickNode.position = SCNVector3(0, 0, 0.002) // Offset slightly forward to prevent z-fighting
        
        containerNode.addChildNode(bgNode)
        containerNode.addChildNode(tickNode)
        
        // Billboard constraint so the tick ALWAYS faces the camera
        containerNode.constraints = [sharedBillboardConstraint]
        
        // Float the tick 4cm above the contact point so it is clearly visible and does not clip
        containerNode.position = SCNVector3(0, 0.04, 0)
        
        rootNode.addChildNode(containerNode)
        
        return rootNode
    }
}
#endif
