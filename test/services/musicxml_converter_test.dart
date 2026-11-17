import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catholicsa/services/midi_writer.dart';
import 'package:catholicsa/services/musicxml_converter.dart';

// MIDI numbers used below: C4 = 60, D4 = 62, E4 = 64, F#4 = 66, G4 = 67,
// A4 = 69, B4 = 71, G3 = 55, B3 = 59, D3 = 50, G2 = 43.
const q = SimpleMidiWriter.ticksPerQuarterNote;

String score(String measures, {int divisions = 2}) => '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>Voice</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>$divisions</divisions><staves>2</staves></attributes>
      $measures
    </measure>
  </part>
</score-partwise>''';

String note(String step, int octave,
        {int duration = 2, String type = 'quarter', int alter = 0, bool chord = false, int voice = 1, String extra = ''}) =>
    '<note>${chord ? '<chord/>' : ''}<pitch><step>$step</step>'
    '${alter != 0 ? '<alter>$alter</alter>' : ''}<octave>$octave</octave></pitch>'
    '<duration>$duration</duration>$extra<voice>$voice</voice><type>$type</type></note>';

String rest({int duration = 2, int voice = 1}) =>
    '<note><rest/><duration>$duration</duration><voice>$voice</voice><type>quarter</type></note>';

List<(int, int, int)> simplify(List<MidiNoteEvent> events) =>
    [for (final e in events) (e.midiNote, e.startTick, e.durationTicks)];

void main() {
  group('MusicXmlToMidiConverter.parseAllParts timing', () {
    test('notes follow each other, rests leave a gap of silence', () {
      final events = MusicXmlToMidiConverter.parseNotes(score(
        note('G', 4) + rest() + note('A', 4, duration: 4, type: 'half'),
      ));
      expect(simplify(events), [(67, 0, q), (69, 2 * q, 2 * q)]);
    });

    test('dotted notes use <duration>, not just <type>', () {
      final events = MusicXmlToMidiConverter.parseNotes(score(
        note('G', 4, duration: 3, type: 'quarter', extra: '<dot/>') + note('A', 4, duration: 1, type: 'eighth'),
      ));
      expect(simplify(events), [(67, 0, (1.5 * q).round()), (69, (1.5 * q).round(), q ~/ 2)]);
    });

    test('<chord/> notes sound together instead of one after another', () {
      final events = MusicXmlToMidiConverter.parseNotes(score(
        note('G', 4) + note('B', 4, chord: true) + note('A', 4),
      ));
      expect(simplify(events), [(67, 0, q), (71, 0, q), (69, q, q)]);
    });

    test('<backup> puts a second voice alongside the first (SATB on two staves)', () {
      // Soprano (voice 1) and alto (voice 2) on the treble staff, then
      // tenor (voice 5) and bass (voice 6) on the bass staff - the
      // layout Audiveris produces for a typical four-part hymn.
      final events = MusicXmlToMidiConverter.parseNotes(score(
        note('G', 4) + note('F', 4, alter: 1) +
            '<backup><duration>4</duration></backup>' +
            note('D', 4, voice: 2) + note('D', 4, voice: 2) +
            '<backup><duration>4</duration></backup>' +
            note('B', 3, voice: 5) + note('A', 3, voice: 5) +
            '<backup><duration>4</duration></backup>' +
            note('G', 2, voice: 6) + note('D', 3, voice: 6),
      ));
      final starts = {for (final e in events) e.midiNote: e.startTick};
      expect(events, hasLength(8));
      expect(starts[67], 0); // soprano G4
      expect(starts[43], 0); // bass G2 - starts with the soprano, not after it
      expect(starts[66], q);
      expect(starts[57], q);
      expect(starts[50], q);
      expect(events.where((e) => e.midiNote == 62).map((e) => e.startTick), [0, q]);
    });

    test('<forward> skips time in a voice', () {
      final events = MusicXmlToMidiConverter.parseNotes(score(
        '<forward><duration>2</duration></forward>${note('G', 4)}',
      ));
      expect(simplify(events), [(67, q, q)]);
    });

    test('tied notes are held, not re-struck', () {
      final events = MusicXmlToMidiConverter.parseNotes(score(
        note('G', 4, extra: '<tie type="start"/>') +
            note('G', 4, extra: '<tie type="stop"/><tie type="start"/>') +
            note('G', 4, extra: '<tie type="stop"/>') +
            note('G', 4),
      ));
      expect(simplify(events), [(67, 0, 3 * q), (67, 3 * q, q)]);
    });

    test('unison between two voices on one staff becomes one note', () {
      final events = MusicXmlToMidiConverter.parseNotes(score(
        '${note('D', 4, duration: 4, type: 'half')}<backup><duration>4</duration></backup>${note('D', 4, voice: 2)}',
      ));
      expect(simplify(events), [(62, 0, 2 * q)]);
    });

    test('grace notes are skipped and do not shift later notes', () {
      final events = MusicXmlToMidiConverter.parseNotes(score(
        '<note><grace/><pitch><step>A</step><octave>4</octave></pitch><voice>1</voice><type>eighth</type></note>'
        '${note('G', 4)}',
      ));
      expect(simplify(events), [(67, 0, q)]);
    });

    test('divisions are honoured, including a change mid-part', () {
      final xml = '''<score-partwise><part id="P1">
        <measure number="1"><attributes><divisions>1</divisions></attributes>${note('G', 4, duration: 1)}</measure>
        <measure number="2"><attributes><divisions>4</divisions></attributes>${note('A', 4, duration: 4)}</measure>
      </part></score-partwise>''';
      expect(simplify(MusicXmlToMidiConverter.parseNotes(xml)), [(67, 0, q), (69, q, q)]);
    });

    test('every part is returned as its own track', () {
      final xml = '''<score-partwise>
        <part id="P1"><measure number="1"><attributes><divisions>1</divisions></attributes>${note('G', 4, duration: 1)}</measure></part>
        <part id="P2"><measure number="1"><attributes><divisions>1</divisions></attributes>${note('G', 2, duration: 1)}</measure></part>
      </score-partwise>''';
      final parts = MusicXmlToMidiConverter.parseAllParts(xml);
      expect(parts.map(simplify), [
        [(67, 0, q)],
        [(43, 0, q)],
      ]);
    });
  });

  group('MusicXmlToMidiConverter repeat expansion', () {
    // One whole-note-per-measure melody: measure k (1-based) plays the
    // k-th pitch in [pitches], so the played order can be read straight
    // off the resulting MIDI notes. [marks] adds barlines/directions to
    // a measure, keyed by 1-based measure number.
    const pitches = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    const midi = {'C': 60, 'D': 62, 'E': 64, 'F': 65, 'G': 67, 'A': 69, 'B': 71};

    String piece(int count, Map<int, String> marks, {int parts = 1}) {
      String part(String id) {
        final measures = StringBuffer();
        for (var k = 1; k <= count; k++) {
          measures.write('<measure number="$k">');
          if (k == 1) measures.write('<attributes><divisions>1</divisions></attributes>');
          measures.write(marks[k] ?? '');
          measures.write(note(pitches[k - 1], 4, duration: 4, type: 'whole'));
          measures.write('</measure>');
        }
        return '<part id="$id">$measures</part>';
      }

      return '<score-partwise>${[for (var p = 1; p <= parts; p++) part('P$p')].join()}</score-partwise>';
    }

    String forward() => '<barline location="left"><repeat direction="forward"/></barline>';
    String backward({int? times}) =>
        '<barline location="right"><repeat direction="backward"${times != null ? ' times="$times"' : ''}/></barline>';
    String endingStart(String n) => '<barline location="left"><ending number="$n" type="start"/></barline>';
    String endingStop(String n) => '<barline location="right"><ending number="$n" type="stop"/></barline>';
    String words(String text) => '<direction><direction-type><words>$text</words></direction-type></direction>';

    /// Played measure numbers (1-based), checking notes are back to back.
    List<int> played(String xml, {bool expandRepeats = true}) {
      final events = MusicXmlToMidiConverter.parseAllParts(xml, expandRepeats: expandRepeats).first;
      for (var k = 0; k < events.length; k++) {
        expect(events[k].startTick, k * 4 * q, reason: 'note $k should follow the previous one directly');
      }
      return [for (final e in events) pitches.indexWhere((p) => midi[p] == e.midiNote) + 1];
    }

    test('no repeat marks: played once, top to bottom', () {
      expect(played(piece(3, {})), [1, 2, 3]);
    });

    test('simple repeat with no forward sign goes back to the start', () {
      expect(played(piece(3, {2: backward()})), [1, 2, 1, 2, 3]);
    });

    test('forward repeat sign is where the repeat goes back to', () {
      expect(played(piece(4, {2: forward(), 3: backward()})), [1, 2, 3, 2, 3, 4]);
    });

    test('times attribute sets the number of passes', () {
      expect(played(piece(2, {1: backward(times: 3)})), [1, 1, 1, 2]);
    });

    test('first and second endings', () {
      expect(
        played(piece(5, {
          1: forward(),
          3: '${endingStart('1')}${backward()}${endingStop('1')}',
          4: '${endingStart('2')}${endingStop('2')}',
        })),
        [1, 2, 3, 1, 2, 4, 5],
      );
    });

    test('multi-measure endings, and "1, 2" endings with a third', () {
      expect(
        played(piece(6, {
          2: endingStart('1, 2'),
          3: '${backward()}${endingStop('1, 2')}',
          4: endingStart('3'),
          5: endingStop('3'),
        })),
        [1, 2, 3, 1, 2, 3, 1, 4, 5, 6],
      );
    });

    test('a second repeat after a volta group goes back to where that group ended', () {
      expect(
        played(piece(6, {
          2: '${endingStart('1')}${backward()}${endingStop('1')}',
          3: '${endingStart('2')}${endingStop('2')}',
          5: backward(),
        })),
        [1, 2, 1, 3, 4, 5, 4, 5, 6],
      );
    });

    test('D.C. al Fine (from <words>)', () {
      expect(played(piece(4, {2: words('Fine'), 4: words('D.C. al Fine')})), [1, 2, 3, 4, 1, 2]);
    });

    test('D.S. al Coda (from <sound> and symbols), repeats not retaken after the jump', () {
      expect(
        played(piece(7, {
          2: '<direction><direction-type><segno/></direction-type><sound segno="s1"/></direction>',
          3: '${backward()}<direction><direction-type><words>To Coda</words></direction-type><sound tocoda="c1"/></direction>',
          5: '<sound dalsegno="s1"/>',
          6: '<direction><direction-type><coda/></direction-type><sound coda="c1"/></direction>',
        })),
        [1, 2, 3, 1, 2, 3, 4, 5, 2, 3, 6, 7],
      );
    });

    test('after D.C., only the last ending of a volta group plays', () {
      expect(
        played(piece(5, {
          2: '${endingStart('1')}${backward()}${endingStop('1')}',
          3: '${endingStart('2')}${endingStop('2')}',
          4: '<sound dacapo="yes"/>',
        })),
        [1, 2, 1, 3, 4, 1, 3, 4, 5],
      );
    });

    test('D.S. with no segno anywhere is ignored rather than guessed at', () {
      expect(played(piece(3, {2: words('D.S. al Fine')})), [1, 2, 3]);
    });

    test('every part follows the same road map, even if only one part has the marks', () {
      final full = piece(3, {2: backward()}, parts: 2);
      final p2 = full.indexOf('<part id="P2">');
      final xml = full.substring(0, p2) + full.substring(p2).replaceFirst(backward(), '');
      expect(xml.split(backward()), hasLength(2)); // only P1 keeps the repeat
      final parts = MusicXmlToMidiConverter.parseAllParts(xml);
      expect(parts, hasLength(2));
      expect(parts[1].map((e) => e.startTick), [0, 4 * q, 8 * q, 12 * q, 16 * q]);
    });

    test('expandRepeats: false plays every measure once, as written', () {
      expect(played(piece(3, {2: backward()}), expandRepeats: false), [1, 2, 3]);
    });

    test('a backward repeat with no way out still terminates', () {
      // Malformed: a repeat inside an ending that every pass plays.
      final order = played(piece(2, {1: '${endingStart('1, 2, 3, 4, 5, 6, 7, 8, 9')}${backward()}'}));
      expect(order.length, lessThan(200));
    });
  });

  group('MusicXmlToMidiConverter.extractMusicXmlFromMxlBytes', () {
    Uint8List zip(Map<String, String> files) {
      final archive = Archive();
      files.forEach((name, content) {
        final bytes = utf8.encode(content);
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      });
      return Uint8List.fromList(ZipEncoder().encode(archive));
    }

    test('uses the rootfile named in META-INF/container.xml, decoded as UTF-8', () {
      final mxl = zip({
        'META-INF/container.xml': '<container><rootfiles><rootfile full-path="score.xml"/></rootfiles></container>',
        'aaa-other.xml': '<other/>',
        'score.xml': '<score-partwise><work><work-title>Salve Regína</work-title></work></score-partwise>',
      });
      expect(MusicXmlToMidiConverter.extractMusicXmlFromMxlBytes(mxl), contains('Salve Regína'));
    });

    test('falls back to the first non-META-INF .xml entry without a container', () {
      final mxl = zip({'score.xml': '<score-partwise/>'});
      expect(MusicXmlToMidiConverter.extractMusicXmlFromMxlBytes(mxl), '<score-partwise/>');
    });
  });

  group('SimpleMidiWriter', () {
    test('rests become delta time before the next note-on', () {
      final bytes = SimpleMidiWriter.write([
        [
          const MidiNoteEvent(midiNote: 60, startTick: 0, durationTicks: q),
          const MidiNoteEvent(midiNote: 62, startTick: 2 * q, durationTicks: q),
        ],
      ]);
      // After the 22-byte header+track-header and 7-byte tempo event:
      final body = bytes.sublist(22 + 7);
      expect(body, [
        0x00, 0x90, 60, 100, // on C4 at 0
        0x83, 0x60, 0x80, 60, 0, // off C4 at 480
        0x83, 0x60, 0x90, 62, 100, // on D4 at 960 (480-tick rest)
        0x83, 0x60, 0x80, 62, 0, // off D4 at 1440
        0x00, 0xFF, 0x2F, 0x00, // end of track
      ]);
    });

    test('a repeated note is switched off before it is switched on again', () {
      final bytes = SimpleMidiWriter.write([
        [
          const MidiNoteEvent(midiNote: 60, startTick: 0, durationTicks: q),
          const MidiNoteEvent(midiNote: 60, startTick: q, durationTicks: q),
        ],
      ]);
      final body = bytes.sublist(22 + 7);
      expect(body.sublist(0, 13), [
        0x00, 0x90, 60, 100,
        0x83, 0x60, 0x80, 60, 0,
        0x00, 0x90, 60, 100,
      ]);
    });

    test('chord notes share one start time', () {
      final bytes = SimpleMidiWriter.write([
        [
          const MidiNoteEvent(midiNote: 67, startTick: 0, durationTicks: q),
          const MidiNoteEvent(midiNote: 60, startTick: 0, durationTicks: q),
        ],
      ]);
      final body = bytes.sublist(22 + 7);
      expect(body.sublist(0, 8), [0x00, 0x90, 60, 100, 0x00, 0x90, 67, 100]);
    });
  });
}
