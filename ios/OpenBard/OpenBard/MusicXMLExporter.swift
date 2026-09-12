import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum MusicXMLExportError: Error, Equatable {
    case noScore
}

struct DurationGlyph: Equatable {
    var durationBeats: Double
    var type: String
    var dots: Int
}

enum MusicXMLExporter {
    static let divisionsPerQuarter = 4 // gridBeats 0.25 → 1 division
    static let measureDivisions = Int(ScoreBuilder.beatsPerMeasure) * divisionsPerQuarter

    /// Standard (possibly dotted) values on the 16th-note grid, longest first.
    private static let durationAtoms: [DurationGlyph] = [
        DurationGlyph(durationBeats: 4.0, type: "whole", dots: 0),
        DurationGlyph(durationBeats: 3.0, type: "half", dots: 1),
        DurationGlyph(durationBeats: 2.0, type: "half", dots: 0),
        DurationGlyph(durationBeats: 1.5, type: "quarter", dots: 1),
        DurationGlyph(durationBeats: 1.0, type: "quarter", dots: 0),
        DurationGlyph(durationBeats: 0.75, type: "eighth", dots: 1),
        DurationGlyph(durationBeats: 0.5, type: "eighth", dots: 0),
        DurationGlyph(durationBeats: 0.25, type: "16th", dots: 0),
    ]

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

    /// Split a grid duration into tied standard values (with dots).
    static func durationGlyphs(for durationBeats: Double) -> [DurationGlyph] {
        var remaining = (durationBeats / ScoreBuilder.gridBeats).rounded() * ScoreBuilder.gridBeats
        var glyphs: [DurationGlyph] = []
        while remaining > 1e-9 {
            guard let atom = durationAtoms.first(where: { $0.durationBeats <= remaining + 1e-9 }) else {
                break
            }
            glyphs.append(atom)
            remaining = (remaining - atom.durationBeats)
            remaining = (remaining / ScoreBuilder.gridBeats).rounded() * ScoreBuilder.gridBeats
        }
        return glyphs
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

        for (voiceIndex, voice) in measure.voices.enumerated() {
            if voiceIndex > 0 {
                xml += "      <backup>\n"
                xml += "        <duration>\(measureDivisions)</duration>\n"
                xml += "      </backup>\n"
            }
            xml += emitVoice(voice, tieStops: tieStops)
        }

        xml += "    </measure>\n"
        return xml
    }

    private static func emitVoice(_ voice: ScoreVoice, tieStops: Set<String>) -> String {
        var xml = ""
        var index = 0
        while index < voice.items.count {
            switch voice.items[index] {
            case .rest(let rest):
                xml += emitRest(rest, voice: voice.number)
                index += 1
            case .note(let note):
                var group = [note]
                var nextIndex = index + 1
                while nextIndex < voice.items.count {
                    if case .note(let other) = voice.items[nextIndex],
                       abs(other.startBeat - note.startBeat) < 1e-9,
                       abs(other.durationBeats - note.durationBeats) < 1e-9 {
                        group.append(other)
                        nextIndex += 1
                    } else {
                        break
                    }
                }
                xml += emitChordGroup(group, voice: voice.number, tieStops: tieStops)
                index = nextIndex
            }
        }
        return xml
    }

    private static func emitChordGroup(
        _ notes: [ScoreNote],
        voice: Int,
        tieStops: Set<String>
    ) -> String {
        let glyphs = durationGlyphs(for: notes[0].durationBeats)
        var xml = ""
        for (glyphIndex, glyph) in glyphs.enumerated() {
            for (noteIndex, note) in notes.enumerated() {
                let stopKey = "\(note.pitchMidi)@\(formatBeat(note.startBeat))"
                let needsIncomingStop = glyphIndex == 0 && tieStops.contains(stopKey)
                let tieStop = glyphIndex > 0 || needsIncomingStop
                let tieStart = glyphIndex < glyphs.count - 1 || note.tiedToNext
                xml += emitNoteElement(
                    note,
                    voice: voice,
                    isChord: noteIndex > 0,
                    glyph: glyph,
                    tieStop: tieStop,
                    tieStart: tieStart
                )
            }
        }
        return xml
    }

    private static func emitNoteElement(
        _ note: ScoreNote,
        voice: Int,
        isChord: Bool,
        glyph: DurationGlyph,
        tieStop: Bool,
        tieStart: Bool
    ) -> String {
        let duration = max(1, Int((glyph.durationBeats * Double(divisionsPerQuarter)).rounded()))
        let pitch = midiToPitch(note.pitchMidi)

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
        if tieStop {
            xml += "        <tie type=\"stop\"/>\n"
        }
        if tieStart {
            xml += "        <tie type=\"start\"/>\n"
        }
        xml += "        <voice>\(voice)</voice>\n"
        xml += "        <type>\(glyph.type)</type>\n"
        for _ in 0..<glyph.dots {
            xml += "        <dot/>\n"
        }
        if tieStop || tieStart {
            xml += "        <notations>\n"
            if tieStop {
                xml += "          <tied type=\"stop\"/>\n"
            }
            if tieStart {
                xml += "          <tied type=\"start\"/>\n"
            }
            xml += "        </notations>\n"
        }
        xml += "      </note>\n"
        return xml
    }

    private static func emitRest(_ rest: ScoreRest, voice: Int) -> String {
        var xml = ""
        for glyph in durationGlyphs(for: rest.durationBeats) {
            let duration = max(1, Int((glyph.durationBeats * Double(divisionsPerQuarter)).rounded()))
            xml += "      <note>\n"
            xml += "        <rest/>\n"
            xml += "        <duration>\(duration)</duration>\n"
            xml += "        <voice>\(voice)</voice>\n"
            xml += "        <type>\(glyph.type)</type>\n"
            for _ in 0..<glyph.dots {
                xml += "        <dot/>\n"
            }
            xml += "      </note>\n"
        }
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
        durationGlyphs(for: durationBeats).first?.type ?? "16th"
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
