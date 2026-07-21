#if os(iOS)
import Foundation
import ARKit
import Vision

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
    private let detectionQueue = DispatchQueue(label: "com.assignment.productDetectionQueue", qos: .userInitiated)
    
    private lazy var rectangleRequest: VNDetectRectanglesRequest = {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 5
        request.minimumConfidence = 0.7
        request.minimumSize = 0.12
        return request
    }()
    
    func processBuffer(_ pixelBuffer: CVPixelBuffer) {
        guard !isProcessingFrame else { return }
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
