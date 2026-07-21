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
        request.minimumConfidence = 0.7
        request.minimumSize = 0.12
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
                    try requestHandler.perform([self.rectangleRequest])
                    
                    var localDetections: [DetectedProduct] = []
                    
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
