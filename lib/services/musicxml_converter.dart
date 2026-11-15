import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'midi_writer.dart';

/// Platform-agnostic on purpose - takes raw bytes rather than a File,
/// so this parsing/conversion logic has no dart:io dependency and is
/// safe to compile into the shared web+Android+Windows codebase. Only
/// the orchestration that reads local files and shells out to external
/// tools (Audiveris, FluidSynth) is genuinely Windows-only.
class MusicXmlToMidiConverter {
  static const _stepOffset = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  static const _typeToTicks = {
    'whole': SimpleMidiWriter.ticksPerQuarterNote * 4,
    'half': SimpleMidiWriter.ticksPerQuarterNote * 2,
    'quarter': SimpleMidiWriter.ticksPerQuarterNote,
    'eighth': SimpleMidiWriter.ticksPerQuarterNote ~/ 2,
    '16th': SimpleMidiWriter.ticksPerQuarterNote ~/ 4,
    '32nd': SimpleMidiWriter.ticksPerQuarterNote ~/ 8,
  };

  /// .mxl is a real zip container (confirmed the same way in the
  /// earlier Node.js version) around the actual MusicXML document -
  /// the first non-META-INF .xml entry is taken, same approach already
  /// verified working.
  static String extractMusicXmlFromMxlBytes(Uint8List mxlBytes) {
    final archive = ZipDecoder().decodeBytes(mxlBytes);
    for (final file in archive) {
      if (file.name.endsWith('.xml') && !file.name.startsWith('META-INF') && file.isFile) {
        return String.fromCharCodes(file.content as List<int>);
      }
    }
    throw Exception('No MusicXML document found inside the .mxl container.');
  }

  /// Parses every note across every part and measure, in document
  /// order, into one MIDI note-event list per `<part>`. A hymn
  /// arrangement often has more than one voice/part (SATB on separate
  /// staves, or melody + accompaniment), and every voice should be
  /// heard, not just whichever one comes first in the file - so every
  /// part is parsed and returned, in document order, for the caller to
  /// write out as its own simultaneous MIDI track.
  static List<List<MidiNoteEvent>> parseAllParts(String xmlString) {
    final doc = XmlDocument.parse(xmlString);
    return [for (final part in doc.findAllElements('part')) _parsePartNotes(part)];
  }

  /// Convenience wrapper for callers that only want a single melody
  /// line: the first part's notes, or an empty list if the score has
  /// no parts at all. `convert()` below uses [parseAllParts] directly
  /// so no voice is dropped.
  static List<MidiNoteEvent> parseNotes(String xmlString) {
    final allParts = parseAllParts(xmlString);
    return allParts.isEmpty ? <MidiNoteEvent>[] : allParts.first;
  }

  static List<MidiNoteEvent> _parsePartNotes(XmlElement part) {
    final events = <MidiNoteEvent>[];
    for (final measure in part.findElements('measure')) {
      for (final noteEl in measure.findElements('note')) {
        final typeEl = noteEl.getElement('type');
        final durationType = typeEl?.innerText ?? 'quarter';
        final ticks = _typeToTicks[durationType] ?? SimpleMidiWriter.ticksPerQuarterNote;

        if (noteEl.getElement('rest') != null) {
          events.add(MidiNoteEvent(midiNote: null, durationTicks: ticks));
          continue;
        }

        final pitchEl = noteEl.getElement('pitch');
        if (pitchEl == null) continue; // not a real pitched note - skip rather than guess

        final step = pitchEl.getElement('step')?.innerText ?? 'C';
        final octave = int.tryParse(pitchEl.getElement('octave')?.innerText ?? '4') ?? 4;
        final alter = int.tryParse(pitchEl.getElement('alter')?.innerText ?? '0') ?? 0;
        final midiNote = (octave + 1) * 12 + (_stepOffset[step] ?? 0) + alter;

        events.add(MidiNoteEvent(midiNote: midiNote, durationTicks: ticks));
      }
    }
    return events;
  }

  static Uint8List convert(Uint8List mxlBytes) {
    final xmlString = extractMusicXmlFromMxlBytes(mxlBytes);
    // Every part becomes its own simultaneous MIDI track; a part that
    // Audiveris produced with no note/rest elements at all is dropped
    // rather than written out as a dead empty track.
    final parts = parseAllParts(xmlString).where((events) => events.isNotEmpty).toList();
    if (parts.isEmpty) {
      throw Exception('No notes were found in the converted score - Audiveris may not have recognized any notation on this page.');
    }
    return SimpleMidiWriter.write(parts);
  }
}