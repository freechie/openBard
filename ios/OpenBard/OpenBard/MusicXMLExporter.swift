import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum MusicXMLExportError: Error, Equatable {
    case noScore
}

enum MusicXMLExporter {
    static let divisionsPerQuarter = 4 // gridBeats 0.25 → 1 division

    /// Build partwise MusicXML 3.1 from a ScoreBuilder score.
    static func makeData(from score: Score) throws -> Data {
        guard !score.measures.isEmpty else { throw MusicXMLExportError.noScore }

        let tieStops = tieStopKeys(in: score)
        var xml = ""
        xml += #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
        xml += #"<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 3.1 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">"# + "\n"
        xml += #"<score-partwise version="3.1">"# + "\n"
        xml += "  <work>\n"
        xml += "    <work-title>openBard</work-title>\n"
        xml += "  </work>\n"
        xml += "  <part-list>\n"
        xml += #"    <score-part id="P1">"# + "\n"
        xml += "      <part-name>Music</part-name>\n"
        xml += "    </score-part>\n"
        xml += "  </part-list>\n"
        xml += #"  <part id="P1">"# + "\n"

        for measure in score.measures {
            xml += emitMeasure(measure, score: score, tieStops: tieStops, isFirst: measure.index == 0)
        }

        xml += "  </part>\n"
        xml += "</score-partwise>\n"

        guard let data = xml.data(using: .utf8) else { throw MusicXMLExportError.noScore }
        return data
    }

    static func makeData(from notes: [NoteEvent], tempoBpm: Double? = nil) throws -> Data {
        guard let score = ScoreBuilder.build(from: notes, tempoBpm: tempoBpm) else {
            throw MusicXMLExportError.noScore
        }
        return try makeData(from: score)
    }

    // MARK: - Measure emission

    private static func emitMeasure(
        _ measure: ScoreMeasure,
        score: Score,
        tieStops: Set<String>,
        isFirst: Bool
    ) -> String {
        var xml = "    <measure number=\"\(measure.index + 1)\">\n"

        if isFirst {
            xml += "      <attributes>\n"
            xml += "        <divisions>\(divisionsPerQuarter)</divisions>\n"
            xml += "        <key>\n"
            xml += "          <fifths>0</fifths>\n"
            xml += "        </key>\n"
            xml += "        <time>\n"
            xml += "          <beats>4</beats>\n"
            xml += "          <beat-type>4</beat-type>\n"
            xml += "        </time>\n"
            xml += "        <clef>\n"
            switch score.clef {
            case .bass:
                xml += "          <sign>F</sign>\n"
                xml += "          <line>4</line>\n"
            case .treble, .unknown:
                xml += "          <sign>G</sign>\n"
                xml += "          <line>2</line>\n"
            }
            xml += "        </clef>\n"
            xml += "      </attributes>\n"
            xml += "      <direction placement=\"above\">\n"
            xml += "        <direction-type>\n"
            xml += "          <metronome>\n"
            xml += "            <beat-unit>quarter</beat-unit>\n"
            xml += "            <per-minute>\(Int(score.tempoBpm.rounded()))</per-minute>\n"
            xml += "          </metronome>\n"
            xml += "        </direction-type>\n"
            xml += "        <sound tempo=\"\(formatNumber(score.tempoBpm))\"/>\n"
            xml += "      </direction>\n"
        }

        var lastNoteStart: Double?
        for item in measure.items {
            switch item {
            case .note(let note):
                let isChord = lastNoteStart.map { abs($0 - note.startBeat) < 1e-9 } ?? false
                xml += emitNote(note, isChord: isChord, tieStops: tieStops)
                lastNoteStart = note.startBeat
            case .rest(let rest):
                xml += emitRest(rest)
                lastNoteStart = nil
            }
        }

        xml += "    </measure>\n"
        return xml
    }

    private static func emitNote(_ note: ScoreNote, isChord: Bool, tieStops: Set<String>) -> String {
        let duration = max(1, Int((note.durationBeats * Double(divisionsPerQuarter)).rounded()))
        let pitch = midiToPitch(note.pitchMidi)
        let type = noteType(for: note.durationBeats)
        let stopKey = "\(note.pitchMidi)@\(formatBeat(note.startBeat))"
        let needsStop = tieStops.contains(stopKey)

        var xml = "      <note>\n"
        if isChord {
            xml += "        <chord/>\n"
        }
        xml += "        <pitch>\n"
        xml += "          <step>\(pitch.step)</step>\n"
        if let alter = pitch.alter {
            xml += "          <alter>\(alter)</alter>\n"
        }
        xml += "          <octave>\(pitch.octave)</octave>\n"
        xml += "        </pitch>\n"
        xml += "        <duration>\(duration)</duration>\n"
        if needsStop {
            xml += "        <tie type=\"stop\"/>\n"
        }
        if note.tiedToNext {
            xml += "        <tie type=\"start\"/>\n"
        }
        xml += "        <voice>1</voice>\n"
        xml += "        <type>\(type)</type>\n"
        if needsStop || note.tiedToNext {
            xml += "        <notations>\n"
            if needsStop {
                xml += "          <tied type=\"stop\"/>\n"
            }
            if note.tiedToNext {
                xml += "          <tied type=\"start\"/>\n"
            }
            xml += "        </notations>\n"
        }
        xml += "      </note>\n"
        return xml
    }

    private static func emitRest(_ rest: ScoreRest) -> String {
        let duration = max(1, Int((rest.durationBeats * Double(divisionsPerQuarter)).rounded()))
        let type = noteType(for: rest.durationBeats)
        var xml = "      <note>\n"
        xml += "        <rest/>\n"
        xml += "        <duration>\(duration)</duration>\n"
        xml += "        <voice>1</voice>\n"
        xml += "        <type>\(type)</type>\n"
        xml += "      </note>\n"
        return xml
    }

    // MARK: - Helpers

    private static func tieStopKeys(in score: Score) -> Set<String> {
        var keys = Set<String>()
        for measure in score.measures {
            for item in measure.items {
                if case .note(let note) = item, note.tiedToNext {
                    let end = note.startBeat + note.durationBeats
                    keys.insert("\(note.pitchMidi)@\(formatBeat(end))")
                }
            }
        }
        return keys
    }

    static func midiToPitch(_ midi: Int) -> (step: String, alter: Int?, octave: Int) {
        let names = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"]
        let alters: [Int?] = [nil, 1, nil, 1, nil, nil, 1, nil, 1, nil, 1, nil]
        let pc = ((midi % 12) + 12) % 12
        let octave = midi / 12 - 1
        return (names[pc], alters[pc], octave)
    }

    static func noteType(for durationBeats: Double) -> String {
        let rounded = (durationBeats / ScoreBuilder.gridBeats).rounded() * ScoreBuilder.gridBeats
        switch rounded {
        case 4.0: return "whole"
        case 3.0: return "half" // dotted half approximated without dots for MVP
        case 2.0: return "half"
        case 1.5: return "quarter"
        case 1.0: return "quarter"
        case 0.75: return "eighth"
        case 0.5: return "eighth"
        default: return "16th"
        }
    }

    private static func formatNumber(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func formatBeat(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}

struct MusicXMLFileDocument: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .musicXML) { document in
            document.data
        }
    }
}

extension UTType {
    static var musicXML: UTType {
        UTType(filenameExtension: "musicxml")
            ?? UTType(filenameExtension: "xml")
            ?? .xml
    }
}
