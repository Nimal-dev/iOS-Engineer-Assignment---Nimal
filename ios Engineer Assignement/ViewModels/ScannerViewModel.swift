#if os(iOS)
import Foundation
import UIKit
import SceneKit
import ARKit
import Vision
import Combine
import simd

// MARK: - Models

struct TrackedItem {
    let anchorIdentifier: UUID
    let position: simd_float3
}

/// A candidate detection that must be confirmed across multiple frames before a tick is placed.
/// This prevents false positives from single noisy frames and ensures stable 3D placement.
struct DetectionCandidate {
    var positions: [simd_float3] = []
    let firstSeen: TimeInterval
    var lastSeen: TimeInterval
    
    /// Average of all accumulated 3D positions for a stable final anchor point
    var averagePosition: simd_float3 {
        guard !positions.isEmpty else { return simd_float3(0, 0, 0) }
        var sum = simd_float3(0, 0, 0)
        for p in positions { sum += p }
        return sum / Float(positions.count)
    }
    
    /// A candidate is confirmed when detected in 3+ frames spanning at least 1 second
    var isConfirmed: Bool {
        return positions.count >= 3 && (lastSeen - firstSeen) >= 1.0
    }
}

// MARK: - ScannerViewModel

class ScannerViewModel: NSObject, ObservableObject, ARSessionDelegate, ARSCNViewDelegate, ProductDetectorDelegate {
    
    @Published var detectedProductCount: Int = 0
    @Published var isScanning: Bool = true
    @Published var feedbackMessage: String = "Scanning shelf..."
    
    var arView: ARSCNView?
    private var detectionService: ProductDetectionService
    
    // Confirmed items that have been placed in the AR scene
    private var trackedItems: [UUID: TrackedItem] = [:]
    private let itemLock = NSRecursiveLock()
    
    // Candidate detections waiting for multi-frame confirmation
    private var candidates: [DetectionCandidate] = []
    
    // 3D distance threshold: two detections within 50cm are considered the same object
    private let duplicateDistanceThreshold: Float = 0.50
    
    // Candidate matching radius: a new detection within 30cm of an existing candidate is a re-observation
    private let candidateMatchRadius: Float = 0.30
    
    // Stale candidate timeout: discard candidates not seen for 3 seconds
    private let candidateTimeout: TimeInterval = 3.0
    
    // Camera motion tracking for shake filter
    private var lastCameraTransform: simd_float4x4?
    private var lastCameraTimestamp: TimeInterval = 0
    
    // Pre-cached SceneKit geometries
    private lazy var backgroundGeometry: SCNPlane = {
        let plane = SCNPlane(width: 0.04, height: 0.04)
        plane.cornerRadius = 0.02
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.18, green: 0.72, blue: 0.35, alpha: 1.0)
        material.isDoubleSided = true
        plane.materials = [material]
        return plane
    }()
    
    private lazy var checkmarkGeometry: SCNPlane = {
        let plane = SCNPlane(width: 0.025, height: 0.025)
        let config = UIImage.SymbolConfiguration(pointSize: 100, weight: .bold)
        let image = UIImage(systemName: "checkmark", withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.isDoubleSided = true
        material.transparent.contents = image
        plane.materials = [material]
        return plane
    }()
    
    private lazy var sharedBillboardConstraint: SCNBillboardConstraint = {
        let c = SCNBillboardConstraint()
        c.freeAxes = .all
        return c
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
        
        // --- Gate 1: Only process when ARKit tracking is normal ---
        if case .limited = currentFrame.camera.trackingState { return }
        if case .notAvailable = currentFrame.camera.trackingState { return }
        
        // --- Gate 2: Skip if camera is shaking ---
        let camTransform = currentFrame.camera.transform
        let now = ProcessInfo.processInfo.systemUptime
        if let lastTx = lastCameraTransform {
            let lastPos = simd_make_float3(lastTx.columns.3)
            let currPos = simd_make_float3(camTransform.columns.3)
            let dt = now - lastCameraTimestamp
            if dt > 0 {
                let speed = simd_distance(lastPos, currPos) / Float(dt)
                if speed > 0.5 {
                    lastCameraTransform = camTransform
                    lastCameraTimestamp = now
                    return
                }
            }
        }
        lastCameraTransform = camTransform
        lastCameraTimestamp = now
        
        // --- Prune stale candidates ---
        candidates.removeAll { now - $0.lastSeen > candidateTimeout }
        
        // --- Process each detection ---
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
            let normalizedCenter = CGPoint(x: rect.midX, y: 1.0 - rect.midY)
            
            let displayTx = currentFrame.displayTransform(for: orientation, viewportSize: arView.bounds.size)
            let viewportPt = normalizedCenter.applying(displayTx)
            let screenPt = CGPoint(x: viewportPt.x * screenWidth, y: viewportPt.y * screenHeight)
            
            // --- Raycast to 3D world position ---
            var worldTransform: simd_float4x4?
            
            // Priority 1: Existing detected plane geometry (most stable, sticks to real surfaces)
            if let query = arView.raycastQuery(from: screenPt, allowing: .existingPlaneGeometry, alignment: .any),
               let result = arView.session.raycast(query).first {
                worldTransform = result.worldTransform
            }
            
            // Priority 2: Estimated plane
            if worldTransform == nil,
               let query = arView.raycastQuery(from: screenPt, allowing: .estimatedPlane, alignment: .any),
               let result = arView.session.raycast(query).first {
                worldTransform = result.worldTransform
            }
            
            // Priority 3: Feature points (noisier but works on organic objects)
            if worldTransform == nil {
                let hits = arView.hitTest(screenPt, types: [.featurePoint])
                if let hit = hits.first {
                    worldTransform = hit.worldTransform
                }
            }
            
            guard let hitTransform = worldTransform else { continue }
            
            let position = simd_make_float3(hitTransform.columns.3)
            
            // --- Distance sanity check ---
            let camPos = simd_make_float3(camTransform.columns.3)
            let dist = simd_distance(camPos, position)
            guard dist > 0.3 && dist < 5.0 else { continue }
            
            // --- Skip if too close to an already-confirmed item ---
            if isConfirmedDuplicate(at: position) { continue }
            
            // --- Feed into candidate confirmation system ---
            feedCandidate(position: position, timestamp: now, arView: arView)
        }
        
        // --- Promote confirmed candidates ---
        promoteConfirmedCandidates(arView: arView)
    }
    
    // MARK: - Candidate Confirmation System
    
    /// Feed a new 3D detection position into the candidate pool.
    private func feedCandidate(position: simd_float3, timestamp: TimeInterval, arView: ARSCNView) {
        // Try to match with an existing candidate
        for i in 0..<candidates.count {
            if simd_distance(candidates[i].averagePosition, position) < candidateMatchRadius {
                candidates[i].positions.append(position)
                candidates[i].lastSeen = timestamp
                return
            }
        }
        
        // No match found — create a new candidate
        var newCandidate = DetectionCandidate(firstSeen: timestamp, lastSeen: timestamp)
        newCandidate.positions.append(position)
        candidates.append(newCandidate)
    }
    
    /// Check all candidates and promote those that have been confirmed (seen 3+ times over 1+ second).
    private func promoteConfirmedCandidates(arView: ARSCNView) {
        var promotedIndices: [Int] = []
        
        for i in 0..<candidates.count {
            guard candidates[i].isConfirmed else { continue }
            
            let avgPos = candidates[i].averagePosition
            
            // Double-check it's not a duplicate of an already-placed item
            if isConfirmedDuplicate(at: avgPos) {
                promotedIndices.append(i)
                continue
            }
            
            // Build a clean, rotation-reset transform at the averaged position
            var anchorTransform = matrix_identity_float4x4
            anchorTransform.columns.3 = simd_make_float4(avgPos.x, avgPos.y, avgPos.z, 1)
            
            let newAnchor = ARAnchor(transform: anchorTransform)
            arView.session.add(anchor: newAnchor)
            
            let tracked = TrackedItem(anchorIdentifier: newAnchor.identifier, position: avgPos)
            itemLock.lock()
            trackedItems[newAnchor.identifier] = tracked
            itemLock.unlock()
            
            promotedIndices.append(i)
            
            DispatchQueue.main.async {
                self.detectedProductCount += 1
                self.feedbackMessage = "Product Detected"
                self.triggerHapticFeedback()
            }
        }
        
        // Remove promoted/discarded candidates in reverse order to preserve indices
        for i in promotedIndices.sorted().reversed() {
            candidates.remove(at: i)
        }
    }
    
    // MARK: - Duplication Check
    
    private func isConfirmedDuplicate(at position: simd_float3) -> Bool {
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
    
    // MARK: - Haptics
    
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
        tickNode.position = SCNVector3(0, 0, 0.002)
        
        containerNode.addChildNode(bgNode)
        containerNode.addChildNode(tickNode)
        
        // Billboard: tick always faces the camera
        containerNode.constraints = [sharedBillboardConstraint]
        
        // Lift tick 3cm above the anchor surface so it hovers just above the product
        containerNode.position = SCNVector3(0, 0.03, 0)
        
        rootNode.addChildNode(containerNode)
        
        return rootNode
    }
}
#endif
