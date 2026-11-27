import AppKit
import Vision

/// On-device text recognition for images, so screenshots are searchable.
enum OCR {
    static func recognize(_ image: NSImage, completion: @escaping (String?) -> Void) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(nil)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            var text: String?
            if (try? handler.perform([request])) != nil {
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                text = lines.isEmpty ? nil : lines.joined(separator: "\n")
            }
            DispatchQueue.main.async { completion(text) }
        }
    }
}
