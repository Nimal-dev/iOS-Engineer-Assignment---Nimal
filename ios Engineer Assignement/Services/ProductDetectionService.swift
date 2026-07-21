#if os(iOS)
import Foundation
import ARKit
import Vision
import QuartzCore

/// A model representing a detected product in 2D screen space before being mapped to 3D.
struct DetectedProduct {
    let id: UUID
    let boundingBox: CGRect
}

protocol ProductDetectorDelegate: AnyObject {
    func didDetectProducts(_ products: [DetectedProduct])
}

class ProductDetectionService {
    
    weak var delegate: ProductDetectorDelegate?
    
    private var isProcessingFrame = false
    private var lastProcessingTime: CFTimeInterval = 0
    private let minProcessingInterval: CFTimeInterval = 0.25
    private let detectionQueue = DispatchQueue(label: "com.assignment.productDetectionQueue", qos: .userInitiated)
    
    private lazy var rectangleRequest: VNDetectRectanglesRequest = {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 8
        request.minimumConfidence = 0.5
        request.minimumSize = 0.08
        request.minimumAspectRatio = 0.2
        request.maximumAspectRatio = 1.0
        return request
    }()
    
    private lazy var saliencyRequest: VNGenerateObjectnessBasedSaliencyImageRequest = {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        return request
    }()
    
    private lazy var contourRequest: VNDetectContoursRequest = {
        let request = VNDetectContoursRequest()
        request.maximumImageDimension = 512
        request.contrastAdjustment = 2.0
        return request
    }()
    
    func processBuffer(_ pixelBuffer: CVPixelBuffer) {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastProcessingTime >= minProcessingInterval else { return }
        guard !isProcessingFrame else { return }
        
        lastProcessingTime = currentTime
        isProcessingFrame = true
        
        detectionQueue.async { [weak self] in
            guard let self = self else { return }
            defer { self.isProcessingFrame = false }
            
            autoreleasepool {
                let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
                
                do {
                    // Run all three detectors for maximum coverage
                    try requestHandler.perform([self.rectangleRequest, self.saliencyRequest, self.contourRequest])
                    
                    var localDetections: [DetectedProduct] = []
                    
                    // 1. Process Saliency — catches ANY visually distinct object (shoes, bags, bottles, etc.)
                    if let saliencyResults = self.saliencyRequest.results {
                        for observation in saliencyResults {
                            guard let salientObjects = observation.salientObjects else { continue }
                            for object in salientObjects {
                                guard object.confidence > 0.25 else { continue }
                                guard object.boundingBox.width > 0.05 && object.boundingBox.height > 0.05 else { continue }
                                // Reject full-frame detections (often just the floor/background)
                                guard object.boundingBox.width < 0.85 && object.boundingBox.height < 0.85 else { continue }
                                localDetections.append(DetectedProduct(id: UUID(), boundingBox: object.boundingBox))
                            }
                        }
                    }
                    
                    // 2. Process Rectangles — catches defined packages, boxes, product labels
                    if let rectResults = self.rectangleRequest.results {
                        for observation in rectResults {
                            localDetections.append(DetectedProduct(id: UUID(), boundingBox: observation.boundingBox))
                        }
                    }
                    
                    // 3. Process Contours — catches objects with strong edge contrast (dark chappal on light floor)
                    if let contourResults = self.contourRequest.results {
                        for observation in contourResults {
                            let topContours = observation.topLevelContours
                            for contour in topContours {
                                let bbox = contour.normalizedPath.boundingBox
                                // Filter: must be a meaningful-sized object, not a tiny edge or the whole frame
                                guard bbox.width > 0.06 && bbox.height > 0.06 else { continue }
                                guard bbox.width < 0.80 && bbox.height < 0.80 else { continue }
                                // Only promote contours of substantial area (not thin lines)
                                let area = bbox.width * bbox.height
                                guard area > 0.01 else { continue }
                                localDetections.append(DetectedProduct(id: UUID(), boundingBox: bbox))
                            }
                        }
                    }
                    
                    // Deduplicate detections that overlap significantly in 2D before sending
                    let deduplicated = self.deduplicateDetections(localDetections)
                    
                    DispatchQueue.main.async {
                        self.delegate?.didDetectProducts(deduplicated)
                    }
                } catch {
                    print("Failed to perform Vision requests: \(error)")
                }
            }
        }
    }
    
    /// Remove 2D bounding box overlaps so the same region doesn't get sent as multiple detections
    private func deduplicateDetections(_ detections: [DetectedProduct]) -> [DetectedProduct] {
        var kept: [DetectedProduct] = []
        
        for detection in detections {
            let dominated = kept.contains { existing in
                let intersection = existing.boundingBox.intersection(detection.boundingBox)
                guard !intersection.isNull else { return false }
                let intersectionArea = intersection.width * intersection.height
                let detectionArea = detection.boundingBox.width * detection.boundingBox.height
                // If >50% of this detection overlaps an already-kept one, skip it
                return detectionArea > 0 && (intersectionArea / detectionArea) > 0.50
            }
            if !dominated {
                kept.append(detection)
            }
        }
        return kept
    }
}
#endif
