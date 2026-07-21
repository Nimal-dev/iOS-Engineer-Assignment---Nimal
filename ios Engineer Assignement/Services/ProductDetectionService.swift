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
    private var frameDetections: [DetectedProduct] = []
    
    private lazy var rectangleRequest: VNDetectRectanglesRequest = {
        let request = VNDetectRectanglesRequest { [weak self] request, error in
            self?.processRectangles(request: request, error: error)
        }
        request.maximumObservations = 5
        request.minimumConfidence = 0.6
        request.minimumSize = 0.15
        return request
    }()
    
    private lazy var barcodeRequest: VNDetectBarcodesRequest = {
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            self?.processBarcodes(request: request, error: error)
        }
        return request
    }()
    
    private lazy var textRequest: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            self?.processText(request: request, error: error)
        }
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0.03
        return request
    }()
    
    func processFrame(_ frame: ARFrame) {
        guard !isProcessingFrame else { return }
        isProcessingFrame = true
        
        // Retain the pixel buffer for processing
        let pixelBuffer = frame.capturedImage
        let orientation = CGImagePropertyOrientation.up
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        
        detectionQueue.async { [weak self] in
            guard let self = self else { return }
            self.frameDetections.removeAll()
            
            do {
                try requestHandler.perform([self.rectangleRequest, self.barcodeRequest, self.textRequest])
                
                let detections = self.frameDetections
                DispatchQueue.main.async {
                    self.delegate?.didDetectProducts(detections)
                }
            } catch {
                print("Failed to perform Vision requests: \(error)")
            }
            self.isProcessingFrame = false
        }
    }
    
    private func processRectangles(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNRectangleObservation], error == nil else { return }
        for observation in results {
            frameDetections.append(DetectedProduct(id: UUID(), boundingBox: observation.boundingBox, type: .rectangle))
        }
    }
    
    private func processBarcodes(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNBarcodeObservation], error == nil else { return }
        for observation in results {
            let payload = observation.payloadStringValue ?? "Unknown Barcode"
            frameDetections.append(DetectedProduct(id: UUID(), boundingBox: observation.boundingBox, type: .barcode(payload)))
        }
    }
    
    private func processText(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNRecognizedTextObservation], error == nil else { return }
        for observation in results {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            let text = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count > 2 else { continue }
            frameDetections.append(DetectedProduct(id: UUID(), boundingBox: observation.boundingBox, type: .text(text)))
        }
    }
}
#endif
