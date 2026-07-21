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
    
    // We'll use a standard Vision rectangle detector as a fallback since no custom CoreML model was provided.
    // In a real scenario, this would be a VNCoreMLRequest using a custom .mlmodel.
    private lazy var rectangleRequest: VNDetectRectanglesRequest = {
        let request = VNDetectRectanglesRequest(completionHandler: self.handleDetections)
        // Configure to find typical product boxes
        request.maximumObservations = 10
        request.minimumConfidence = 0.5
        request.minimumSize = 0.1
        return request
    }()
    
    private var isProcessingFrame = false
    private let detectionQueue = DispatchQueue(label: "com.assignment.productDetectionQueue", qos: .userInitiated)
    
    func processFrame(_ frame: ARFrame) {
        guard !isProcessingFrame else { return }
        isProcessingFrame = true
        
        // Retain the pixel buffer for processing
        let pixelBuffer = frame.capturedImage
        
        // Use the frame's camera orientation to ensure correct detection
        let orientation = CGImagePropertyOrientation.up // ARFrame pixel buffers are typically right-side up in landscape, but we can adjust based on interface orientation if needed.
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        
        detectionQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try requestHandler.perform([self.rectangleRequest])
            } catch {
                print("Failed to perform Vision request: \(error)")
                self.isProcessingFrame = false
            }
        }
    }
    
    private func handleDetections(request: VNRequest, error: Error?) {
        defer { isProcessingFrame = false }
        
        guard let results = request.results as? [VNRectangleObservation], error == nil else {
            return
        }
        
        let detectedProducts = results.map { observation -> DetectedProduct in
            // The observation bounding box is in normalized coordinates (0.0 to 1.0)
            // with the origin at the bottom-left. We will pass this to the view model
            // which can then convert it to screen/world coordinates.
            DetectedProduct(id: UUID(), boundingBox: observation.boundingBox)
        }
        
        DispatchQueue.main.async {
            self.delegate?.didDetectProducts(detectedProducts)
        }
    }
}
#endif
