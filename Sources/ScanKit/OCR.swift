import CoreGraphics
import Foundation
import Vision

/// Native OCR via the Vision framework.
public enum OCR {
    public struct Word: Sendable {
        public let text: String
        /// Normalised bounding box, bottom-left origin (Vision/PDF convention).
        public let box: CGRect
    }

    /// Recognise text on a 1-bit page (works on the packed page directly),
    /// one entry per word so the invisible layer lines up with the ink.
    public static func recognize(_ page: Pipeline.ProcessedPage) throws -> [Word] {
        guard let img = page.cgImage else {
            throw ScanError.scanFailed("Cannot build image for OCR")
        }

        let request = VNRecognizeTextRequest()
        // Pinned, as WWDC22 "What's new in Vision" advises: the default is
        // whatever the linked SDK's latest is.
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Vision otherwise biases toward English
        // (/documentation/vision/recognizing-text-in-images).
        let languages = recognitionLanguages(
            preferred: Locale.preferredLanguages,
            supported: (try? request.supportedRecognitionLanguages()) ?? []
        )
        if !languages.isEmpty {
            request.recognitionLanguages = languages
        }
        try VNImageRequestHandler(cgImage: img).perform([request])
        return (request.results ?? []).flatMap { obs -> [Word] in
            guard let candidate = obs.topCandidates(1).first else { return [] }
            return words(of: candidate, lineBox: obs.boundingBox)
        }
    }

    /// The user's languages Vision can read, in the user's order: an exact
    /// match, else the same language in another region ("en-GB" → "en-US").
    static func recognitionLanguages(preferred: [String], supported: [String]) -> [String] {
        func language(_ id: String) -> String? {
            Locale(identifier: id).language.languageCode?.identifier
        }
        var picked: [String] = []
        for want in preferred {
            let match =
                supported.first { $0 == want }
                ?? supported.first { language($0) == language(want) }
            if let match, !picked.contains(match) {
                picked.append(match)
            }
        }
        return picked
    }

    /// Each whitespace-separated word with its own box
    /// (`boundingBox(for:)`, /documentation/vision/vnrecognizedtext), since
    /// a whole line stretched over its box drifts from the ink. Words keep
    /// the space after them: without it a reader runs neighbours together
    /// (PDFKit found 177 words on a page instead of 224). If Vision can't
    /// place every word, the line goes in as one.
    private static func words(of candidate: VNRecognizedText, lineBox: CGRect) -> [Word] {
        let text = candidate.string
        let ranges = text.ranges(of: #/\S+/#)
        let words = ranges.map { range in
            (try? candidate.boundingBox(for: range)?.boundingBox).map {
                Word(text: text[range] + (range == ranges.last ? "" : " "), box: $0)
            }
        }
        guard !words.isEmpty, !words.contains(where: { $0 == nil }) else {
            return [Word(text: text, box: lineBox)]
        }
        return words.compactMap { $0 }
    }
}
