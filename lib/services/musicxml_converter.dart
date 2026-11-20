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
  ///
  /// Repeat signs, first/second endings (voltas), D.C./D.S., Fine and
  /// To Coda are expanded into the order the music is actually played
  /// (see [playbackOrder]), unless [expandRepeats] is false, in which
  /// case measures are played once each, top to bottom, as written.
  static List<List<MidiNoteEvent>> parseAllParts(String xmlString, {bool expandRepeats = true}) {
    final doc = XmlDocument.parse(xmlString);
    final parts = doc.findAllElements('part').toList();
    final measuresPerPart = [for (final part in parts) part.findElements('measure').toList()];
    final order = expandRepeats ? playbackOrder(measuresPerPart) : null;
    return [for (final measures in measuresPerPart) _parsePartNotes(measures, order)];
  }

  /// The order in which measures are actually played, as indexes into
  /// each part's measure list, once repeat signs, endings and jumps are
  /// taken into account. Measures are matched across parts by position
  /// (a partwise score has the same number of measures in every part),
  /// and a marking found in any part at a given position counts for all
  /// of them - Audiveris doesn't always put a barline/direction in every
  /// part, but every part has to follow the same road map or they'd
  /// drift apart.
  ///
  /// Conventions used (standard engraving practice, not configurable):
  /// - `<repeat direction="backward">` jumps back to the most recent
  ///   forward repeat (or the start of the piece / the end of the last
  ///   completed repeat if there is none), `times` passes in total,
  ///   default 2.
  /// - `<ending number="1, 2">` measures only play on those passes.
  /// - D.C. / D.S. are taken once, at the end of the measure that
  ///   carries them; after the jump, repeats are not taken again and
  ///   only the last ending of each volta group plays, Fine ends the
  ///   piece, and To Coda jumps to the next coda sign.
  /// - Read from `<sound dacapo/dalsegno/segno/fine/tocoda/coda>`,
  ///   `<segno/>`/`<coda/>` symbols, and `<words>` text like "D.C. al
  ///   Fine", "D.S. al Coda", "Fine", "To Coda" (Audiveris often only
  ///   exports the words).
  static List<int> playbackOrder(List<List<XmlElement>> measuresPerPart) {
    final n = measuresPerPart.fold<int>(0, (m, part) => part.length > m ? part.length : m);
    final info = List.generate(n, (_) => _MeasureMarks());
    for (final part in measuresPerPart) {
      for (var i = 0; i < part.length; i++) {
        info[i].mergeFrom(part[i]);
      }
    }

    // Each ending's numbers apply from its type="start" through its
    // stop/discontinue, which may span several measures.
    final endingOf = List<Set<int>?>.filled(n, null);
    Set<int>? open;
    for (var i = 0; i < n; i++) {
      final m = info[i];
      if (m.endingStart != null) open = m.endingStart;
      endingOf[i] = open;
      if (m.endingStop) open = null;
    }
    // Highest ending number in each run of consecutive volta measures,
    // so after a D.C./D.S. only the final ending is played.
    final groupMax = List<int>.filled(n, 0);
    for (var i = 0; i < n;) {
      if (endingOf[i] == null) {
        i++;
        continue;
      }
      var j = i;
      var max = 0;
      while (j < n && endingOf[j] != null) {
        for (final e in endingOf[j]!) {
          if (e > max) max = e;
        }
        j++;
      }
      for (var k = i; k < j; k++) {
        groupMax[k] = max;
      }
      i = j;
    }

    final order = <int>[];
    var i = 0;
    var repeatStart = 0;
    var pass = 1;
    var arrivedByRepeatJump = false;
    var repeatCompleted = false;
    var lastWasEnding = false;
    var afterJump = false; // a D.C./D.S. has been taken
    // Hard cap so a malformed/misrecognized score can never loop forever.
    final maxLength = n * 32 + 64;

    while (i < n && order.length < maxLength) {
      final m = info[i];
      final ending = endingOf[i];

      if (m.forwardRepeat && !arrivedByRepeatJump) {
        repeatStart = i;
        pass = 1;
        repeatCompleted = false;
      }
      arrivedByRepeatJump = false;
      // Past the end of a repeated section (its backward repeat done,
      // or its volta group over): the next repeat starts fresh from here.
      if (ending == null && (repeatCompleted || lastWasEnding)) {
        if (lastWasEnding && !m.forwardRepeat) repeatStart = i;
        pass = 1;
        repeatCompleted = false;
      }
      lastWasEnding = ending != null;

      if (ending != null) {
        final plays = afterJump ? ending.contains(groupMax[i]) : ending.contains(pass);
        if (!plays) {
          i++;
          continue;
        }
      }

      order.add(i);

      if (afterJump && m.fine) break;

      if (m.backwardRepeat && !afterJump) {
        // A backward repeat inside a volta always goes back (that
        // ending only plays on passes that repeat), unless an explicit
        // `times` says how many passes there are in total.
        final times = m.repeatTimes;
        final goBack = ending != null ? (times == null || pass < times) : pass < (times ?? 2);
        if (goBack) {
          pass++;
          i = repeatStart;
          arrivedByRepeatJump = true;
          lastWasEnding = false;
          continue;
        }
        repeatCompleted = true;
        repeatStart = i + 1;
      }

      if (afterJump && (m.toCoda || m.coda)) {
        final target = _indexWhere(info, (x) => x.coda, i + 1);
        if (target != null) {
          i = target;
          continue;
        }
      }

      if (!afterJump && (m.daCapo || m.dalSegno)) {
        final target = m.daCapo ? 0 : _indexWhere(info, (x) => x.segno, 0);
        if (target != null) {
          afterJump = true;
          lastWasEnding = false;
          i = target;
          continue;
        }
      }

      i++;
    }
    return order;
  }

  static int? _indexWhere(List<_MeasureMarks> info, bool Function(_MeasureMarks) test, int from) {
    for (var k = from; k < info.length; k++) {
      if (test(info[k])) return k;
    }
    return null;
  }

  /// Convenience wrapper for callers that only want a single line: the
  /// first part's notes, or an empty list if the score has no parts.
  static List<MidiNoteEvent> parseNotes(String xmlString) {
    final allParts = parseAllParts(xmlString);
    return allParts.isEmpty ? <MidiNoteEvent>[] : allParts.first;
  }

  static List<MidiNoteEvent> _parsePartNotes(List<XmlElement> measures, List<int>? order) {
    final events = <MidiNoteEvent>[];

    // Divisions in effect at the start of each measure, as written
    // (top to bottom), so jumping back for a repeat picks up the right
    // value even if it changed later in the piece.
    final divisionsAtStart = List<int?>.filled(measures.length, null);
    int? running;
    for (var k = 0; k < measures.length; k++) {
      divisionsAtStart[k] = running;
      for (final a in measures[k].findElements('attributes')) {
        final d = int.tryParse(a.getElement('divisions')?.innerText.trim() ?? '');
        if (d != null && d > 0) running = d;
      }
    }

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

    for (final index in order ?? List<int>.generate(measures.length, (k) => k)) {
      // A part can be shorter than the longest part; it just falls
      // silent for measures it doesn't have.
      if (index >= measures.length) continue;
      final measure = measures[index];
      divisions = divisionsAtStart[index] ?? divisions;
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

  static Uint8List convert(Uint8List mxlBytes, {int bpm = 84, int? instrumentProgram}) {
    final xmlString = extractMusicXmlFromMxlBytes(mxlBytes);
    // Every part becomes its own simultaneous MIDI track; a part with
    // no sounding notes at all is dropped rather than written out as a
    // dead empty track.
    final parts = parseAllParts(xmlString).where((events) => events.isNotEmpty).toList();
    if (parts.isEmpty) {
      throw Exception('No notes were found in the converted score - Audiveris may not have recognized any notation on this page.');
    }
    return SimpleMidiWriter.write(parts, bpm: bpm, instrumentProgram: instrumentProgram);
  }

  /// Converts several .mxl files end to end, each one picked up right
  /// where the previous one finished - real, confirmed need: Audiveris
  /// sometimes can't merge every page/system of a hymn into one book
  /// and exports several separate .mxl files (e.g. input.mvt1.mxl,
  /// input.mvt2.mxl) instead. Converting only the first of those (the
  /// old behaviour) played just that one movement and stopped, which is
  /// exactly why a hymn could come out a few seconds long instead of
  /// playing start to finish. This merges all of them into one MIDI
  /// file: each movement's notes are shifted later in time by the
  /// previous movements' combined length, per track index, so the
  /// piece continues instead of overlapping or restarting from zero.
  static Uint8List convertAll(List<Uint8List> mxlBytesList, {int bpm = 84, int? instrumentProgram}) {
    if (mxlBytesList.isEmpty) {
      throw Exception('No MusicXML files to convert.');
    }
    if (mxlBytesList.length == 1) {
      return convert(mxlBytesList.first, bpm: bpm, instrumentProgram: instrumentProgram);
    }

    final tracks = <List<MidiNoteEvent>>[];
    var offset = 0;

    for (final mxlBytes in mxlBytesList) {
      final xmlString = extractMusicXmlFromMxlBytes(mxlBytes);
      final parts = parseAllParts(xmlString);
      if (parts.every((events) => events.isEmpty)) continue;

      while (tracks.length < parts.length) {
        tracks.add(<MidiNoteEvent>[]);
      }

      var movementEnd = offset;
      for (var i = 0; i < parts.length; i++) {
        for (final e in parts[i]) {
          final shifted = MidiNoteEvent(
            midiNote: e.midiNote,
            startTick: e.startTick + offset,
            durationTicks: e.durationTicks,
          );
          tracks[i].add(shifted);
          if (shifted.endTick > movementEnd) movementEnd = shifted.endTick;
        }
      }
      offset = movementEnd;
    }

    final nonEmptyTracks = tracks.where((t) => t.isNotEmpty).toList();
    if (nonEmptyTracks.isEmpty) {
      throw Exception('No notes were found in the converted score - Audiveris may not have recognized any notation on this page.');
    }
    return SimpleMidiWriter.write(nonEmptyTracks, bpm: bpm, instrumentProgram: instrumentProgram);
  }

  /// Same movement-merging idea as [convertAll], but keeps only the
  /// first part's notes (see [parseNotes]) and writes them as a single
  /// monophonic track, with no instrument program - this is the melody
  /// line handed to a singing-voice synthesizer (OddVoices), not
  /// something FluidSynth plays. A singer sings one note at a time, so
  /// the full multi-part instrumental arrangement isn't what's wanted
  /// here; just the tune.
  static Uint8List convertAllMelodyOnly(List<Uint8List> mxlBytesList, {int bpm = 84}) {
    if (mxlBytesList.isEmpty) {
      throw Exception('No MusicXML files to convert.');
    }

    final track = <MidiNoteEvent>[];
    var offset = 0;
    for (final mxlBytes in mxlBytesList) {
      final xmlString = extractMusicXmlFromMxlBytes(mxlBytes);
      final melody = parseNotes(xmlString);
      if (melody.isEmpty) continue;

      var movementEnd = offset;
      for (final e in melody) {
        final shifted = MidiNoteEvent(
          midiNote: e.midiNote,
          startTick: e.startTick + offset,
          durationTicks: e.durationTicks,
        );
        track.add(shifted);
        if (shifted.endTick > movementEnd) movementEnd = shifted.endTick;
      }
      offset = movementEnd;
    }

    if (track.isEmpty) {
      throw Exception('No melody notes were found to sing - the converted score may not have any notes in its first part.');
    }
    return SimpleMidiWriter.write([track], bpm: bpm);
  }
}

/// Repeat/jump markings found on one measure (merged across parts).
class _MeasureMarks {
  bool forwardRepeat = false;
  bool backwardRepeat = false;
  int? repeatTimes;
  Set<int>? endingStart;
  bool endingStop = false;
  bool segno = false;
  bool coda = false;
  bool toCoda = false;
  bool fine = false;
  bool daCapo = false;
  bool dalSegno = false;

  static final _dc = RegExp(r'\bd\.\s*c\.|da\s+capo', caseSensitive: false);
  static final _ds = RegExp(r'\bd\.\s*s\.|dal\s+segno', caseSensitive: false);
  static final _toCoda = RegExp(r'\bto\s+coda\b', caseSensitive: false);
  static final _fine = RegExp(r'^\s*fine\.?\s*$', caseSensitive: false);

  void mergeFrom(XmlElement measure) {
    for (final barline in measure.findElements('barline')) {
      final repeat = barline.getElement('repeat');
      if (repeat != null) {
        final dir = repeat.getAttribute('direction');
        if (dir == 'forward') forwardRepeat = true;
        if (dir == 'backward') {
          backwardRepeat = true;
          final t = int.tryParse(repeat.getAttribute('times') ?? '');
          if (t != null && t > 0) repeatTimes = t;
        }
      }
      final ending = barline.getElement('ending');
      if (ending != null) {
        final type = ending.getAttribute('type');
        if (type == 'start') {
          final numbers = RegExp(r'\d+')
              .allMatches(ending.getAttribute('number') ?? '')
              .map((mm) => int.parse(mm.group(0)!))
              .toSet();
          if (numbers.isNotEmpty) endingStart = {...?endingStart, ...numbers};
        } else if (type == 'stop' || type == 'discontinue') {
          endingStop = true;
        }
      }
    }

    for (final sound in measure.findAllElements('sound')) {
      if (sound.getAttribute('dacapo') == 'yes') daCapo = true;
      if (sound.getAttribute('dalsegno') != null) dalSegno = true;
      if (sound.getAttribute('segno') != null) segno = true;
      if (sound.getAttribute('coda') != null) coda = true;
      if (sound.getAttribute('tocoda') != null) toCoda = true;
      if (sound.getAttribute('fine') != null) fine = true;
    }

    for (final dt in measure.findAllElements('direction-type')) {
      if (dt.getElement('segno') != null) segno = true;
      if (dt.getElement('coda') != null) coda = true;
      for (final w in dt.findElements('words')) {
        final text = w.innerText;
        if (_dc.hasMatch(text)) daCapo = true;
        if (_ds.hasMatch(text)) dalSegno = true;
        if (_toCoda.hasMatch(text)) toCoda = true;
        if (_fine.hasMatch(text)) fine = true;
      }
    }
  }
}
