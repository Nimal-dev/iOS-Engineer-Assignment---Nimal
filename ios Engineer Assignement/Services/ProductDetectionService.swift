#if os(iOS)
import Foundation
import ARKit
import Vision

enum DetectionType: Equatable {
    case rectangle
    case barcode(String)
    case text(String)
}

/// A model representing a detected product in 2D screen space before being mapped to 3D.
struct DetectedProduct {
    let id: UUID
    let boundingBox: CGRect
    let type: DetectionType
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
        request.minimumConfidence = 0.6
        request.minimumSize = 0.15
        return request
    }()
    
    private lazy var barcodeRequest: VNDetectBarcodesRequest = {
        let request = VNDetectBarcodesRequest()
        return request
    }()
    
    private lazy var textRequest: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0.03
        return request
    }()
    
    func processFrame(_ frame: ARFrame) {
        guard !isProcessingFrame else { return }
        isProcessingFrame = true
        
        let pixelBuffer = frame.capturedImage
        let orientation = CGImagePropertyOrientation.up
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        
        detectionQueue.async { [weak self] in
            guard let self = self else { return }
            defer { self.isProcessingFrame = false }
            
            do {
                try requestHandler.perform([self.rectangleRequest, self.barcodeRequest, self.textRequest])
                
                var localDetections: [DetectedProduct] = []
                
                if let rectResults = self.rectangleRequest.results {
                    for observation in rectResults {
                        localDetections.append(DetectedProduct(id: UUID(), boundingBox: observation.boundingBox, type: .rectangle))
                    }
                }
                
                if let barcodeResults = self.barcodeRequest.results {
                    for observation in barcodeResults {
                        let payload = observation.payloadStringValue ?? "Unknown Barcode"
                        localDetections.append(DetectedProduct(id: UUID(), boundingBox: observation.boundingBox, type: .barcode(payload)))
                    }
                }
                
                if let textResults = self.textRequest.results {
                    for observation in textResults {
                        guard let topCandidate = observation.topCandidates(1).first else { continue }
                        let text = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard text.count > 2 else { continue }
                        localDetections.append(DetectedProduct(id: UUID(), boundingBox: observation.boundingBox, type: .text(text)))
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
#endif
