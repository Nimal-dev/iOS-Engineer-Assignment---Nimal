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
    private let minProcessingInterval: CFTimeInterval = 0.25 // Limit to ~4 FPS to save memory/CPU
    private let detectionQueue = DispatchQueue(label: "com.assignment.productDetectionQueue", qos: .userInitiated)
    
    private lazy var rectangleRequest: VNDetectRectanglesRequest = {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 5
        request.minimumConfidence = 0.6
        request.minimumSize = 0.1
        return request
    }()
    
    private lazy var saliencyRequest: VNGenerateObjectnessBasedSaliencyImageRequest = {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
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
                    // Run both requests: rectangle detection for boxes, and objectness saliency for generic objects
                    try requestHandler.perform([self.rectangleRequest, self.saliencyRequest])
                    
                    var localDetections: [DetectedProduct] = []
                    
                    // 1. Process Saliency (for generic organic objects like a chappal)
                    if let saliencyResults = self.saliencyRequest.results {
                        for observation in saliencyResults {
                            guard let salientObjects = observation.salientObjects else { continue }
                            for object in salientObjects {
                                guard object.confidence > 0.4 else { continue }
                                guard object.boundingBox.width > 0.08 && object.boundingBox.height > 0.08 else { continue }
                                localDetections.append(DetectedProduct(id: UUID(), boundingBox: object.boundingBox))
                            }
                        }
                    }
                    
                    // 2. Process Rectangles (for defined shelf product packages)
                    if let rectResults = self.rectangleRequest.results {
                        for observation in rectResults {
                            localDetections.append(DetectedProduct(id: UUID(), boundingBox: observation.boundingBox))
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.delegate?.didDetectProducts(localDetections)
                    }
                } catch {
                    print("Failed to perform Vision requests: \(error)")
                }
            }
        }
    }
}
#endif
