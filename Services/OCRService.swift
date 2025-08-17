import Foundation
import Vision
import CoreImage
import AppKit

protocol OCRServiceProtocol {
    func extractText(from image: NSImage) async throws -> String
    func extractBarcode(from image: NSImage) async throws -> String
}

final class OCRService: OCRServiceProtocol {
    
    enum OCRError: LocalizedError {
        case noTextFound
        case noBarcodeFound
        case imageProcessingFailed
        case visionRequestFailed
        
        var errorDescription: String? {
            switch self {
            case .noTextFound:
                return "No text found in image"
            case .noBarcodeFound:
                return "No barcode found in image"
            case .imageProcessingFailed:
                return "Failed to process image"
            case .visionRequestFailed:
                return "Vision request failed"
            }
        }
    }
    
    // MARK: - Text Extraction
    
    func extractText(from image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.imageProcessingFailed
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: OCRError.visionRequestFailed)
                    return
                }
                
                let recognizedText = observations.compactMap { observation in
                    return observation.topCandidates(1).first?.string
                }.joined(separator: "\n")
                
                if recognizedText.isEmpty {
                    continuation.resume(throwing: OCRError.noTextFound)
                } else {
                    continuation.resume(returning: recognizedText)
                }
            }
            
            // Configure text recognition for better accuracy
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Barcode Detection
    
    func extractBarcode(from image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.imageProcessingFailed
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNBarcodeObservation] else {
                    continuation.resume(throwing: OCRError.visionRequestFailed)
                    return
                }
                
                // Get all detected barcodes and join them
                let barcodeValues = observations.compactMap { observation in
                    return observation.payloadStringValue
                }.joined(separator: "\n")
                
                if barcodeValues.isEmpty {
                    continuation.resume(throwing: OCRError.noBarcodeFound)
                } else {
                    continuation.resume(returning: barcodeValues)
                }
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}