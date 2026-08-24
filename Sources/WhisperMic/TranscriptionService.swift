import Foundation

enum TranscriptionError: Error, LocalizedError {
    case noAPIKey
    case fileReadError
    case audioTooLarge(Int)
    case networkError(String)
    case apiError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key. Add via: security add-generic-password -a claude-mcp -s OPENAI_API_KEY -w KEY"
        case .fileReadError: return "Could not read audio file"
        case .audioTooLarge(let mb): return "Recording too large (\(mb)MB). Max is 25MB (~13 min)."
        case .networkError(let msg): return "Network: \(msg)"
        case .apiError(let msg): return "API: \(msg)"
        case .timeout: return "Request timed out. Check your internet connection."
        }
    }

    /// Whether keeping the audio around is worth anything. A file that can't be
    /// read or is over the size cap will fail identically on every retry.
    var isRetryable: Bool {
        switch self {
        case .fileReadError, .audioTooLarge: return false
        case .noAPIKey, .networkError, .apiError, .timeout: return true
        }
    }
}

enum TranscriptionModel: String, CaseIterable {
    /// OpenAI's recommended transcription model since July 2026. Cheaper than
    /// gpt-4o-transcribe and without its documented habit of cutting the
    /// transcript short after a pause in speech.
    case gptTranscribe = "gpt-transcribe"
    case gpt4oTranscribe = "gpt-4o-transcribe"
    /// Slower and weaker on proper nouns, but the most resilient against
    /// dropped sentences — the fallback when a transcript comes back short.
    case whisper1 = "whisper-1"

    static let `default` = TranscriptionModel.gptTranscribe

    var displayName: String {
        switch self {
        case .gptTranscribe: return "gpt-transcribe (recommended)"
        case .gpt4oTranscribe: return "gpt-4o-transcribe (legacy)"
        case .whisper1: return "whisper-1 (most complete)"
        }
    }

    /// gpt-transcribe replaced the singular `language` field with `languages[]`
    /// and rejects any request that sends both.
    var usesLanguagesArray: Bool { self == .gptTranscribe }

    /// whisper-1 treats `prompt` as preceding transcript text to continue from,
    /// not as an instruction, so an instruction there only biases the output.
    var acceptsInstructionPrompt: Bool { self != .whisper1 }
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
    /// Anti-truncation anchor. gpt-4o-class transcription models otherwise treat a
    /// pause between sentences as end-of-input, or condense several sentences into
    /// one. English is safe for every language: the model reports the spoken
    /// language from the audio, not from the prompt.
    private static let verbatimPrompt =
        "Dictation. Transcribe every spoken word verbatim, from the first word to the last. "
        + "Do not omit, summarize, shorten or clean up anything. Silence and pauses are not the end of the recording."

    static func transcribe(fileURL: URL, language: String, model: TranscriptionModel) async throws -> String {
        guard let apiKey = KeychainHelper.getOpenAIKey() else {
            throw TranscriptionError.noAPIKey
        }
        guard let audioData = try? Data(contentsOf: fileURL) else {
            throw TranscriptionError.fileReadError
        }

        // OpenAI API limit is 25MB
        let maxSize = 25 * 1024 * 1024
        if audioData.count > maxSize {
            throw TranscriptionError.audioTooLarge(audioData.count / 1_048_576)
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

        appendField("model", model.rawValue)
        if language != "auto" {
            appendField(model.usesLanguagesArray ? "languages[]" : "language", language)
        }
        if model.acceptsInstructionPrompt {
            appendField("prompt", verbatimPrompt)
        }
        appendField("temperature", "0")

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

        // The caller owns the audio file — it is only removed once this returned.
        return result.text
    }
}
