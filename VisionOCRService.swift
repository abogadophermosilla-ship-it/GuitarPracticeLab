import Foundation
import Vision
import ImageIO

enum VisionOCRServiceError: LocalizedError {
    case invalidImage
    case noText

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "No fue posible leer la imagen seleccionada."
        case .noText:
            "No se reconoció texto suficiente en el recorte. Prueba con una zona más nítida."
        }
    }
}

enum VisionOCRService {
    static func recognizeText(in imageData: Data) async throws -> String {
        try await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw VisionOCRServiceError.invalidImage
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["es-ES", "en-US"]
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            let lines = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let text = lines.joined(separator: "\n")
            guard text.count >= 8 else { throw VisionOCRServiceError.noText }
            return text
        }.value
    }
}
