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
    let type: DetectionType
    let position: simd_float3
}

class ScannerViewModel: NSObject, ObservableObject, ARSessionDelegate, ARSCNViewDelegate, ProductDetectorDelegate {
    
    @Published var detectedProductCount: Int = 0
    @Published var isScanning: Bool = true
    @Published var feedbackMessage: String = "Scanning shelf..."
    
    var arView: ARSCNView?
    private var detectionService: ProductDetectionService
    private var trackedItems: [UUID: TrackedItem] = [:]
    
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
        detectionService.processFrame(frame)
    }
    
    // MARK: - ProductDetectorDelegate
    
    func didDetectProducts(_ products: [DetectedProduct]) {
        guard let arView = arView, isScanning,
              let currentFrame = arView.session.currentFrame else { return }
        
        let screenWidth = arView.bounds.width
        let screenHeight = arView.bounds.height
        
        let orientation: UIInterfaceOrientation
        if #available(iOS 26.0, *) {
            orientation = arView.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        } else {
            orientation = arView.window?.windowScene?.interfaceOrientation ?? .portrait
        }
        
        for product in products {
            let rect = product.boundingBox
            
            // Mathematically correct conversion from Vision [0, 1] (origin bottom-left)
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
            
            // Advanced Non-Duplication Logic by type
            if isDuplicate(product.type, at: position) {
                continue
            }
            
            // Add a new ARAnchor at this position
            let newAnchor = ARAnchor(transform: worldTransform)
            arView.session.add(anchor: newAnchor)
            
            // Track the item
            let tracked = TrackedItem(anchorIdentifier: newAnchor.identifier, type: product.type, position: position)
            trackedItems[newAnchor.identifier] = tracked
            
            DispatchQueue.main.async {
                self.detectedProductCount += 1
                
                // Customize feedback message based on scan type
                switch product.type {
                case .rectangle:
                    self.feedbackMessage = "Product Box Detected"
                case .barcode(let payload):
                    self.feedbackMessage = "Barcode: \(payload)"
                case .text(let content):
                    self.feedbackMessage = "Label: \(content)"
                }
                
                self.triggerHapticFeedback()
            }
        }
    }
    
    private func isDuplicate(_ type: DetectionType, at position: simd_float3) -> Bool {
        for item in trackedItems.values {
            switch (type, item.type) {
            case (.barcode(let codeA), .barcode(let codeB)):
                // Barcode matches: absolute duplicate
                if codeA == codeB { return true }
            case (.text(let textA), .text(let textB)):
                // Same text string within 1 meter is duplicate
                if textA == textB && simd_distance(position, item.position) < 1.0 {
                    return true
                }
            case (.rectangle, .rectangle):
                // Spatial check for plain boxes
                if simd_distance(position, item.position) < duplicateDistanceThreshold {
                    return true
                }
            default:
                // Cross-type spatial check (e.g. don't place box directly on top of barcode)
                if simd_distance(position, item.position) < duplicateDistanceThreshold {
                    return true
                }
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
        guard let trackedItem = trackedItems[anchor.identifier] else { return nil }
        
        let node = SCNNode()
        
        let boxColor: UIColor
        let width: CGFloat
        let height: CGFloat
        let symbol: String
        
        switch trackedItem.type {
        case .rectangle:
            boxColor = .green
            width = 0.10
            height = 0.15
            symbol = "checkmark.circle.fill"
        case .barcode(let payload):
            boxColor = .systemCyan
            width = 0.08
            height = 0.04
            symbol = "qrcode"
            addTextLabelNode(to: node, text: "BARCODE: \(payload)")
        case .text(let content):
            boxColor = .orange
            width = 0.12
            height = 0.05
            symbol = "text.alignleft"
            addTextLabelNode(to: node, text: content)
        }
        
        // 1. Create a bounding box shape matching the type's size
        let boxGeometry = SCNBox(width: width, height: height, length: 0.02, chamferRadius: 0.0)
        boxGeometry.firstMaterial?.diffuse.contents = UIColor.clear
        
        let outlineMaterial = SCNMaterial()
        outlineMaterial.diffuse.contents = boxColor.withAlphaComponent(0.8)
        outlineMaterial.isDoubleSided = true
        boxGeometry.materials = Array(repeating: outlineMaterial, count: 6)
        
        let edgeNode = SCNNode(geometry: boxGeometry)
        node.addChildNode(edgeNode)
        
        // 2. Create the Tick/Symbol mark
        let plane = SCNPlane(width: 0.04, height: 0.04)
        let config = UIImage.SymbolConfiguration(pointSize: 100, weight: .bold)
        let image = UIImage(systemName: symbol, withConfiguration: config)?
            .withTintColor(boxColor, renderingMode: .alwaysOriginal)
        
        plane.firstMaterial?.diffuse.contents = image
        plane.firstMaterial?.isDoubleSided = true
        
        let symbolNode = SCNNode(geometry: plane)
        symbolNode.position = SCNVector3(0, 0, 0.02) // Slightly in front of the box
        
        // Billboard constraint so the symbol always faces the camera
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = .all
        symbolNode.constraints = [billboardConstraint]
        
        node.addChildNode(symbolNode)
        
        return node
    }
    
    private func addTextLabelNode(to node: SCNNode, text: String) {
        let textGeometry = SCNText(string: text, extrusionDepth: 0.001)
        textGeometry.flatness = 0.2
        textGeometry.firstMaterial?.diffuse.contents = UIColor.white
        
        let textNode = SCNNode(geometry: textGeometry)
        textNode.scale = SCNVector3(0.001, 0.001, 0.001) // Extremely scaled down for AR scale
        
        let (minVec, maxVec) = textGeometry.boundingBox
        let width = maxVec.x - minVec.x
        // Center text horizontally and position 8cm above the anchor center
        textNode.position = SCNVector3(-width * 0.001 / 2, 0.06, 0.01)
        
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        textNode.constraints = [billboard]
        
        node.addChildNode(textNode)
    }
}
#endif
