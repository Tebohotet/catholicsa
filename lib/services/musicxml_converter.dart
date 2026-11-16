import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'midi_writer.dart';

/// Platform-agnostic on purpose - takes raw bytes rather than a File,
/// so this parsing/conversion logic has no dart:io dependency and is
/// safe to compile into the shared web+Android+Windows codebase. Only
/// the orchestration that reads local files and shells out to external
/// tools (Audiveris, FluidSynth) is genuinely Windows-only.
///
/// Timing follows the MusicXML model rather than assuming one note
/// simply follows another: each part keeps a time cursor that every
/// note/rest advances by its `<duration>`, `<chord/>` notes share the
/// previous note's start time, and `<backup>`/`<forward>` move the
/// cursor so a second voice on the same staff (very common in hymns -
/// soprano+alto on the treble staff, tenor+bass on the bass staff)
/// plays alongside the first voice instead of after it.
class MusicXmlToMidiConverter {
  static const _tpq = SimpleMidiWriter.ticksPerQuarterNote;
  static const _stepOffset = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

  /// Note-type lengths in quarter notes, used only as a fallback for
  /// the (non-standard) case of a note with no `<duration>` element.
  static const _typeToQuarters = {
    'breve': 8.0,
    'whole': 4.0,
    'half': 2.0,
    'quarter': 1.0,
    'eighth': 0.5,
    '16th': 0.25,
    '32nd': 0.125,
    '64th': 0.0625,
  };

  /// .mxl is a zip container around the actual MusicXML document. The
  /// container's `META-INF/container.xml` names the real score file
  /// (the "rootfile"); that's used when present, falling back to the
  /// first non-META-INF .xml/.musicxml entry otherwise. Decoded as
  /// UTF-8 (MusicXML's normal encoding) so non-ASCII lyric/title text
  /// doesn't come out garbled.
  static String extractMusicXmlFromMxlBytes(Uint8List mxlBytes) {
    final archive = ZipDecoder().decodeBytes(mxlBytes);
    String decode(ArchiveFile f) => utf8.decode(f.content as List<int>, allowMalformed: true);

    final container = archive.findFile('META-INF/container.xml');
    if (container != null) {
      try {
        final rootPath = XmlDocument.parse(decode(container))
            .findAllElements('rootfile')
            .map((e) => e.getAttribute('full-path'))
            .whereType<String>()
            .firstWhere((path) => !path.startsWith('META-INF'), orElse: () => '');
        if (rootPath.isNotEmpty) {
          final root = archive.findFile(rootPath);
          if (root != null && root.isFile) return decode(root);
        }
      } on XmlException {
        // Malformed container.xml - fall through to the plain scan below.
      }
    }

    for (final file in archive) {
      final name = file.name;
      if ((name.endsWith('.xml') || name.endsWith('.musicxml')) && !name.startsWith('META-INF') && file.isFile) {
        return decode(file);
      }
    }
    throw Exception('No MusicXML document found inside the .mxl container.');
  }

  /// Parses every `<part>` into its own list of absolutely-timed MIDI
  /// notes, in document order. A hymn arrangement often has more than
  /// one part (SATB on separate staves, or melody + accompaniment), and
  /// every part should be heard, so each one is returned for the caller
  /// to write out as its own simultaneous MIDI track.
  static List<List<MidiNoteEvent>> parseAllParts(String xmlString) {
    final doc = XmlDocument.parse(xmlString);
    return [for (final part in doc.findAllElements('part')) _parsePartNotes(part)];
  }

  /// Convenience wrapper for callers that only want a single line: the
  /// first part's notes, or an empty list if the score has no parts.
  static List<MidiNoteEvent> parseNotes(String xmlString) {
    final allParts = parseAllParts(xmlString);
    return allParts.isEmpty ? <MidiNoteEvent>[] : allParts.first;
  }

  static List<MidiNoteEvent> _parsePartNotes(XmlElement part) {
    final events = <MidiNoteEvent>[];
    int? divisions; // divisions per quarter note; can change mid-part
    var cursor = 0; // current position in the part, in MIDI ticks
    var lastNoteStart = 0; // start of the most recent non-chord note, for <chord/>

    // Index into [events] of a note that has an open <tie type="start">,
    // keyed by MIDI pitch, so the matching tied-to note extends it
    // instead of re-striking it.
    final openTies = <int, int>{};
    // Index into [events] by (start, pitch), so two voices sharing a
    // note (e.g. soprano and alto in unison on one staff) produce one
    // MIDI note rather than two overlapping identical ones.
    final byStartAndPitch = <int, int>{};

    int toTicks(XmlElement el) {
      final raw = double.tryParse(el.getElement('duration')?.innerText.trim() ?? '');
      if (raw != null && divisions != null && divisions > 0) {
        return (raw * _tpq / divisions).round();
      }
      return _fallbackTicks(el);
    }

    for (final measure in part.findElements('measure')) {
      for (final el in measure.childElements) {
        switch (el.name.local) {
          case 'attributes':
            final d = int.tryParse(el.getElement('divisions')?.innerText.trim() ?? '');
            if (d != null && d > 0) divisions = d;
          case 'backup':
            cursor -= toTicks(el);
            if (cursor < 0) cursor = 0;
          case 'forward':
            cursor += toTicks(el);
          case 'note':
            // Grace notes have no duration of their own; playing them
            // would mean stealing time from a neighbour - skip them.
            if (el.getElement('grace') != null) continue;

            final isChord = el.getElement('chord') != null;
            final ticks = toTicks(el);
            final start = isChord ? lastNoteStart : cursor;
            if (!isChord) {
              lastNoteStart = cursor;
              cursor += ticks;
            }

            final pitchEl = el.getElement('pitch');
            // Rests, cue notes and unpitched (percussion) notes take up
            // time but produce no sound.
            if (el.getElement('rest') != null || el.getElement('cue') != null || pitchEl == null) continue;

            final midiNote = _midiNumber(pitchEl);
            if (midiNote == null) continue;

            final tieTypes = el.findElements('tie').map((t) => t.getAttribute('type')).toSet();

            if (tieTypes.contains('stop')) {
              final idx = openTies[midiNote];
              if (idx != null && events[idx].endTick == start) {
                final prev = events[idx];
                events[idx] = MidiNoteEvent(
                  midiNote: prev.midiNote,
                  startTick: prev.startTick,
                  durationTicks: prev.durationTicks + ticks,
                );
                if (!tieTypes.contains('start')) openTies.remove(midiNote);
                continue;
              }
            }

            final key = start * 128 + midiNote;
            final existing = byStartAndPitch[key];
            int idx;
            if (existing != null) {
              idx = existing;
              if (events[idx].durationTicks < ticks) {
                events[idx] = MidiNoteEvent(midiNote: midiNote, startTick: start, durationTicks: ticks);
              }
            } else {
              idx = events.length;
              events.add(MidiNoteEvent(midiNote: midiNote, startTick: start, durationTicks: ticks));
              byStartAndPitch[key] = idx;
            }
            if (tieTypes.contains('start')) openTies[midiNote] = idx;
        }
      }
    }
    return events;
  }

  static int? _midiNumber(XmlElement pitchEl) {
    final step = pitchEl.getElement('step')?.innerText.trim();
    final offset = _stepOffset[step];
    if (offset == null) return null;
    final octave = int.tryParse(pitchEl.getElement('octave')?.innerText.trim() ?? '');
    if (octave == null) return null;
    // <alter> may be fractional (microtones); round to the nearest semitone.
    final alter = (double.tryParse(pitchEl.getElement('alter')?.innerText.trim() ?? '') ?? 0).round();
    final midi = (octave + 1) * 12 + offset + alter;
    return (midi < 0 || midi > 127) ? null : midi;
  }

  /// Duration from `<type>`, `<dot/>`s and `<time-modification>`
  /// (tuplets), for notes without a usable `<duration>`.
  static int _fallbackTicks(XmlElement el) {
    final type = el.getElement('type')?.innerText.trim();
    var quarters = _typeToQuarters[type] ?? 1.0;
    var dotValue = quarters / 2;
    for (var i = 0; i < el.findElements('dot').length; i++) {
      quarters += dotValue;
      dotValue /= 2;
    }
    final tm = el.getElement('time-modification');
    if (tm != null) {
      final actual = int.tryParse(tm.getElement('actual-notes')?.innerText.trim() ?? '');
      final normal = int.tryParse(tm.getElement('normal-notes')?.innerText.trim() ?? '');
      if (actual != null && normal != null && actual > 0) quarters = quarters * normal / actual;
    }
    return (quarters * _tpq).round();
  }

  static Uint8List convert(Uint8List mxlBytes) {
    final xmlString = extractMusicXmlFromMxlBytes(mxlBytes);
    // Every part becomes its own simultaneous MIDI track; a part with
    // no sounding notes at all is dropped rather than written out as a
    // dead empty track.
    final parts = parseAllParts(xmlString).where((events) => events.isNotEmpty).toList();
    if (parts.isEmpty) {
      throw Exception('No notes were found in the converted score - Audiveris may not have recognized any notation on this page.');
    }
    return SimpleMidiWriter.write(parts);
  }
}
