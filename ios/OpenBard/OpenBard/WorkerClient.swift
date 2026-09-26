import Foundation

enum WorkerSettings {
    static let defaultBaseURLString = "http://127.0.0.1:8000"
    static let storageKey = "workerBaseURL"

    static func resolvedBaseURLString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultBaseURLString : trimmed
    }

    static func baseURL(from raw: String) throws -> URL {
        let string = resolvedBaseURLString(raw)
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty
        else {
            throw WorkerError.invalidBaseURL(string)
        }
        return url
    }
}

enum WorkerError: Error, Equatable, LocalizedError {
    case invalidBaseURL(String)
    case unreachable(URL)
    case httpStatus(Int, detail: String?)
    case invalidTranscription

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let value):
            return "Invalid worker URL: \(value)"
        case .unreachable(let url):
            return "Could not reach worker at \(url.absoluteString)"
        case .httpStatus(let code, let detail):
            if let detail, !detail.isEmpty {
                return "Worker error (\(code)): \(detail)"
            }
            return "Worker error (\(code))"
        case .invalidTranscription:
            return "Worker returned invalid transcription"
        }
    }
}

enum WorkerClient {
    // Live Basic Pitch can exceed the default 60s URLRequest timeout on first inference.
    static let requestTimeout: TimeInterval = 120

    static func transcriptionURL(from baseURL: URL) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL.appending(path: "v1/transcriptions")
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = basePath.isEmpty ? "/v1/transcriptions" : "/\(basePath)/v1/transcriptions"
        return components.url ?? baseURL.appending(path: "v1/transcriptions")
    }

    static func transcribe(
        fileURL: URL,
        baseURL: URL,
        session: URLSession = .shared
    ) async throws -> Data {
        let filename = fileURL.lastPathComponent
        let boundary = "Boundary-\(UUID().uuidString)"
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openbard-upload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        try writeMultipartFile(source: fileURL, filename: filename, boundary: boundary, to: bodyURL)

        var request = URLRequest(url: transcriptionURL(from: baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, fromFile: bodyURL)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw WorkerError.unreachable(baseURL)
        }
        return try validateResponse(data: data, response: response)
    }

    static func writeMultipartFile(source: URL, filename: String, boundary: String, to destination: URL) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let safeName = filename.replacingOccurrences(of: "\"", with: "")
        try writeUTF8("--\(boundary)\r\n", to: output)
        try writeUTF8(
            "Content-Disposition: form-data; name=\"audio\"; filename=\"\(safeName)\"\r\n",
            to: output
        )
        try writeUTF8("Content-Type: \(mimeType(forFilename: safeName))\r\n\r\n", to: output)

        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try writeUTF8("\r\n--\(boundary)--\r\n", to: output)
    }

    private static func writeUTF8(_ string: String, to handle: FileHandle) throws {
        try handle.write(contentsOf: Data(string.utf8))
    }

    static func makeRequest(fileData: Data, filename: String, baseURL: URL) -> URLRequest {
        var request = URLRequest(url: transcriptionURL(from: baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(fileData: fileData, filename: filename, boundary: boundary)
        return request
    }

    static func validateResponse(data: Data, response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else {
            throw WorkerError.invalidTranscription
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WorkerError.httpStatus(http.statusCode, detail: errorDetail(from: data))
        }
        return data
    }

    static func multipartBody(fileData: Data, filename: String, boundary: String) -> Data {
        let safeName = filename.replacingOccurrences(of: "\"", with: "")
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(safeName)\"\r\n")
        append("Content-Type: \(mimeType(forFilename: safeName))\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    static func mimeType(forFilename filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "wav":
            return "audio/wav"
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        case "caf":
            return "audio/x-caf"
        case "aac":
            return "audio/aac"
        default:
            return "application/octet-stream"
        }
    }

    private static func errorDetail(from data: Data) -> String? {
        struct Body: Decodable {
            let detail: Detail

            enum Detail: Decodable {
                case message(String)
                case unsupported

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let message = try? container.decode(String.self) {
                        self = .message(message)
                        return
                    }
                    self = .unsupported
                }
            }
        }

        if let body = try? JSONDecoder().decode(Body.self, from: data) {
            switch body.detail {
            case .message(let message):
                return message
            case .unsupported:
                break
            }
        }

        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty {
            return raw
        }
        return nil
    }
}
