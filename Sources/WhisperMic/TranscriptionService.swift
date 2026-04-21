import Foundation

enum TranscriptionError: Error, LocalizedError {
    case noAPIKey
    case fileReadError
    case networkError(String)
    case apiError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key. Add via: security add-generic-password -a claude-mcp -s OPENAI_API_KEY -w KEY"
        case .fileReadError: return "Could not read audio file"
        case .networkError(let msg): return "Network: \(msg)"
        case .apiError(let msg): return "API: \(msg)"
        case .timeout: return "Request timed out. Check your internet connection."
        }
    }
}

struct TranscriptionResponse: Decodable {
    let text: String
}

struct APIErrorResponse: Decodable {
    let error: APIErrorDetail
}

struct APIErrorDetail: Decodable {
    let message: String
}

enum TranscriptionService {
    static func transcribe(fileURL: URL, language: String) async throws -> String {
        guard let apiKey = KeychainHelper.getOpenAIKey() else {
            throw TranscriptionError.noAPIKey
        }
        guard let audioData = try? Data(contentsOf: fileURL) else {
            throw TranscriptionError.fileReadError
        }

        // OpenAI API limit is 25MB
        let maxSize = 25 * 1024 * 1024
        if audioData.count > maxSize {
            try? FileManager.default.removeItem(at: fileURL)
            throw TranscriptionError.apiError("Recording too large (\(audioData.count / 1_048_576)MB). Max is 25MB (~13 min).")
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90  // generous timeout for large audio files

        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("model", "gpt-4o-transcribe")
        if language != "auto" {
            appendField("language", language)
        }
        if let prompt = transcriptionPrompt(for: language) {
            appendField("prompt", prompt)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!
        )
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw TranscriptionError.timeout
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw TranscriptionError.networkError("No internet connection")
        } catch {
            throw TranscriptionError.networkError(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw TranscriptionError.apiError(errorResponse.error.message)
            }
            throw TranscriptionError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let result: TranscriptionResponse
        do {
            result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        } catch {
            throw TranscriptionError.apiError("Invalid response from API")
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: fileURL)

        return result.text
    }

    // Anchors gpt-4o-transcribe so it doesn't treat pauses between sentences
    // as end-of-input and stop generating. Must match the transcription
    // language; for "auto" we return nil to avoid biasing language detection.
    private static func transcriptionPrompt(for language: String) -> String? {
        switch language {
        case "nl": return "Dit is een dictaat. Transcribeer de volledige opname van begin tot einde, inclusief alle zinnen en pauzes."
        case "en": return "This is a dictation. Transcribe the complete audio from start to end, including every sentence and pause."
        case "de": return "Dies ist ein Diktat. Transkribiere die gesamte Aufnahme von Anfang bis Ende, einschließlich aller Sätze und Pausen."
        case "fr": return "Ceci est une dictée. Transcrivez l'enregistrement complet du début à la fin, y compris toutes les phrases et pauses."
        case "es": return "Esto es un dictado. Transcribe la grabación completa de principio a fin, incluyendo todas las frases y pausas."
        case "tr": return "Bu bir dikte. Tüm kaydı baştan sona, tüm cümleler ve duraklamalar dahil eksiksiz yazıya dök."
        default: return nil
        }
    }
}
