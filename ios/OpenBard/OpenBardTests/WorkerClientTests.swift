import Foundation
import Testing
@testable import OpenBard

struct WorkerClientTests {
    @Test func defaultWorkerURLTargetsLocalUvicorn() throws {
        #expect(WorkerSettings.defaultBaseURLString == "http://127.0.0.1:8000")
        let url = try WorkerSettings.baseURL(from: "")
        #expect(url.scheme == "http")
        #expect(url.host == "127.0.0.1")
        #expect(url.port == 8000)
        #expect(WorkerClient.transcriptionURL(from: url).absoluteString == "http://127.0.0.1:8000/v1/transcriptions")
        let slashed = try WorkerSettings.baseURL(from: "http://127.0.0.1:8000/")
        #expect(WorkerClient.transcriptionURL(from: slashed).absoluteString == "http://127.0.0.1:8000/v1/transcriptions")
    }

    @Test func blankStoredURLFallsBackToDefault() throws {
        let url = try WorkerSettings.baseURL(from: "   ")
        #expect(url.absoluteString == WorkerSettings.defaultBaseURLString)
    }

    @Test func rejectsInvalidWorkerURL() {
        #expect(throws: WorkerError.invalidBaseURL("not a url")) {
            try WorkerSettings.baseURL(from: "not a url")
        }
        #expect(throws: WorkerError.invalidBaseURL("ftp://127.0.0.1:8000")) {
            try WorkerSettings.baseURL(from: "ftp://127.0.0.1:8000")
        }
    }

    @Test func writeMultipartFileStreamsSourceBytes() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("openbard-multipart-source-\(UUID().uuidString).wav")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("openbard-multipart-body-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }
        let payload = Data("wav-bytes".utf8)
        try payload.write(to: source)

        try WorkerClient.writeMultipartFile(
            source: source,
            filename: "c-major-chord.wav",
            boundary: "Boundary-test",
            to: destination
        )

        let body = String(decoding: try Data(contentsOf: destination), as: UTF8.self)
        #expect(body.contains("name=\"audio\""))
        #expect(body.contains("filename=\"c-major-chord.wav\""))
        #expect(body.contains("audio/wav"))
        #expect(body.contains("wav-bytes"))
        #expect(body.contains("--Boundary-test--"))
    }

    @Test func makeRequestPostsMultipartAudioField() {
        let base = URL(string: WorkerSettings.defaultBaseURLString)!
        let request = WorkerClient.makeRequest(
            fileData: Data("wav-bytes".utf8),
            filename: "c-major-chord.wav",
            baseURL: base
        )
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/transcriptions")
        #expect(request.url?.host == "127.0.0.1")
        #expect(request.url?.port == 8000)
        #expect(request.timeoutInterval == WorkerClient.requestTimeout)
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("name=\"audio\""))
        #expect(body.contains("filename=\"c-major-chord.wav\""))
        #expect(body.contains("wav-bytes"))
        #expect(body.contains("audio/wav"))
    }

    @Test func mapsWorkerTranscriptionResponse() throws {
        let json = """
        {
          "engine": "basic_pitch",
          "engine_version": "0.3.0",
          "tempo_bpm": null,
          "key_guess": null,
          "note_events": [
            {
              "pitch_midi": 60,
              "onset_seconds": 0.0,
              "duration_seconds": 2.0,
              "velocity": 0.5,
              "confidence": 0.5,
              "staff_hint": "treble"
            },
            {
              "pitch_midi": 64,
              "onset_seconds": 0.0,
              "duration_seconds": 2.0,
              "velocity": 0.4,
              "confidence": 0.4,
              "staff_hint": "treble"
            },
            {
              "pitch_midi": 67,
              "onset_seconds": 0.0,
              "duration_seconds": 2.0,
              "velocity": 0.6,
              "confidence": 0.6,
              "staff_hint": "treble"
            }
          ]
        }
        """
        let transcription = try TranscriptionLoader.decodeTranscription(from: Data(json.utf8))

        #expect(transcription.engine == "basic_pitch")
        #expect(transcription.engineVersion == "0.3.0")
        #expect(transcription.keyGuess == nil)
        #expect(transcription.noteEvents.map(\.pitchMidi) == [60, 64, 67])
        #expect(transcription.noteEvents.map(\.velocity) == [0.5, 0.4, 0.6])
        #expect(transcription.noteEvents.map(\.confidence) == [0.5, 0.4, 0.6])
        #expect(transcription.noteEvents.allSatisfy { $0.onsetSeconds == 0 })
        #expect(transcription.noteEvents.allSatisfy { $0.durationSeconds == 2 })
        #expect(transcription.noteEvents.allSatisfy { $0.staffHint == .treble })
        #expect(transcription.tempoBpm == 120)
    }

    @Test func mapsBundledBasicPitchFixtureThroughTheSameDecoder() throws {
        let bundle = Bundle(for: TestBundleMarker.self)
        let url = try #require(
            bundle.url(forResource: "isolated-piano-basicpitch", withExtension: "json")
        )
        let transcription = try TranscriptionLoader.decodeTranscription(from: try Data(contentsOf: url))
        #expect(transcription.engine == "basic_pitch")
        #expect(transcription.keyGuess == nil)
        #expect(transcription.noteEvents.count == 21)
        #expect(transcription.tempoBpm == 60)
    }

    @Test func rejectInvalidWorkerJSON() {
        do {
            _ = try TranscriptionLoader.decodeTranscription(from: Data("{}".utf8))
            #expect(Bool(false), "expected decode to fail")
        } catch {
            #expect(error is DecodingError)
        }
    }

    @Test func validateResponseReturnsSuccessBody() throws {
        let url = URL(string: "http://127.0.0.1:8000/v1/transcriptions")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let payload = Data("{\"engine\":\"basic_pitch\"}".utf8)
        let body = try WorkerClient.validateResponse(data: payload, response: response)
        #expect(body == payload)
    }

    @Test func validateResponseSurfacesFastAPIDetail() {
        let url = URL(string: "http://127.0.0.1:8000/v1/transcriptions")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 400,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = Data("{\"detail\":\"Unsupported audio type\"}".utf8)
        #expect(throws: WorkerError.httpStatus(400, detail: "Unsupported audio type")) {
            try WorkerClient.validateResponse(data: data, response: response)
        }
        #expect(
            WorkerError.httpStatus(400, detail: "Unsupported audio type").errorDescription
                == "Worker error (400): Unsupported audio type"
        )
    }

    @Test func validateResponseSurfacesServerError() {
        let url = URL(string: "http://127.0.0.1:8000/v1/transcriptions")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 500,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = Data("{\"detail\":\"Basic Pitch failed to load\"}".utf8)
        #expect(throws: WorkerError.httpStatus(500, detail: "Basic Pitch failed to load")) {
            try WorkerClient.validateResponse(data: data, response: response)
        }
    }

    @Test func validateResponseSurfacesUnreachableMessage() {
        let url = URL(string: WorkerSettings.defaultBaseURLString)!
        #expect(WorkerError.unreachable(url).errorDescription == "Could not reach worker at http://127.0.0.1:8000")
        #expect(WorkerError.invalidTranscription.errorDescription == "Worker returned invalid transcription")
    }
}
