import Foundation

enum TranscriptionLoader {
    static func loadDemo(from bundle: Bundle = .main) throws -> TranscriptionResult {
        guard let url = bundle.url(
            forResource: "transcription.example",
            withExtension: "json"
        ) else {
            throw LoaderError.missingDemoJSON
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return try decoder.decode(TranscriptionResult.self, from: data)
    }

    static func loadFixture(_ fixture: AudioFixture, from bundle: Bundle = .main) throws -> TranscriptionResult? {
        guard let resourceName = fixture.groundTruthResource else {
            return nil
        }
        
        guard let url = bundle.url(
            forResource: resourceName,
            withExtension: "json"
        ) else {
            throw LoaderError.missingFixtureJSON
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return try decoder.decode(TranscriptionResult.self, from: data)
    }

    static func demoAudioURL(from bundle: Bundle = .main) throws -> URL {
        guard let url = bundle.url(
            forResource: "c-major-chord",
            withExtension: "wav"
        ) else {
            throw LoaderError.missingDemoAudio
        }
        return url
    }
    
    static func fixtureAudioURL(_ fixture: AudioFixture, from bundle: Bundle = .main) throws -> URL {
        guard let url = bundle.url(
            forResource: fixture.resourceName,
            withExtension: "wav"
        ) else {
            throw LoaderError.missingFixtureAudio
        }
        return url
    }

    enum LoaderError: Error {
        case missingDemoJSON
        case missingDemoAudio
        case missingFixtureJSON
        case missingFixtureAudio
    }
}

enum AudioFixture: String, CaseIterable, Identifiable {
    case cMajorChord = "C Major Chord"
    case isolatedPiano = "Isolated Piano"
    case mixedArrangement = "Mixed Arrangement"
    
    var id: String { rawValue }
    
    var resourceName: String {
        switch self {
        case .cMajorChord:
            return "c-major-chord"
        case .isolatedPiano:
            return "isolated-piano"
        case .mixedArrangement:
            return "mixed-arrangement"
        }
    }
    
    var groundTruthResource: String? {
        switch self {
        case .cMajorChord:
            return nil
        case .isolatedPiano:
            return "isolated-piano-ground-truth"
        case .mixedArrangement:
            return "mixed-arrangement-ground-truth"
        }
    }
}
