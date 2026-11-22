import 'dart:typed_data';

/// One sounding note to write into the MIDI file, placed at an absolute
/// position in the track rather than "right after the previous note".
///
/// Absolute placement is what lets a single track hold chords (several
/// notes sharing one [startTick]), rests (a gap between one note's end
/// and the next note's start) and several voices on one staff (notes
/// that overlap in time) - none of which a purely sequential list of
/// notes can express.
class MidiNoteEvent {
  final int midiNote;
  final int startTick;
  final int durationTicks;
  const MidiNoteEvent({
    required this.midiNote,
    required this.startTick,
    required this.durationTicks,
  });

  int get endTick => startTick + durationTicks;

  @override
  String toString() => 'MidiNoteEvent(note: $midiNote, start: $startTick, duration: $durationTicks)';
}

/// Writes a Standard MIDI File. Ported directly rather than relying on
/// a third-party Dart package whose own correctness couldn't be
/// independently confirmed.
class SimpleMidiWriter {
  static const int ticksPerQuarterNote = 480;

  /// Writes one track per element of [tracks]. Every track starts at
  /// time zero and is played back simultaneously, so a hymn
  /// arrangement's separate parts (SATB, or melody + accompaniment)
  /// all sound together instead of one replacing the others. A single
  /// track produces a format 0 (single-track) file, several produce
  /// format 1 (several, simultaneous).
  ///
  /// [bpm] sets the tempo (real, confirmed problem: a fixed 120 BPM -
  /// a brisk, almost march-like pace - was previously hardcoded with
  /// no way to change it; hymns are typically sung much slower, and
  /// Audiveris essentially never recognizes a printed tempo marking,
  /// so this has to be adjustable rather than guessed once in code).
  /// [instrumentPrograms] are General MIDI program numbers, 0-127
  /// (0-indexed - note this is one less than the 1-128 numbering
  /// MusicXML/most instrument lists use), one per track, by index:
  /// track `i` gets a program-change event to `instrumentPrograms[i]`
  /// before its first note so FluidSynth actually voices it with that
  /// instrument instead of silently falling back to the soundfont's
  /// default (normally Acoustic Grand Piano on MuseScore_General.sf2),
  /// regardless of what instrument Audiveris itself guessed when
  /// exporting the MusicXML. A track past the end of the list reuses
  /// the list's last entry, so a single-element list gives every track
  /// the same instrument. Null or empty: no program change at all.
  ///
  /// Every track plays on its own MIDI channel ([channelForTrack]) -
  /// a program change applies to a whole channel, not a track, so if
  /// two tracks shared one channel the later program change would
  /// silently re-voice both of them.
  static Uint8List write(
    List<List<MidiNoteEvent>> tracks, {
    int bpm = 84,
    List<int>? instrumentPrograms,
  }) {
    if (tracks.isEmpty) {
      throw ArgumentError('write() needs at least one track of events.');
    }

    final header = BytesBuilder();
    header.add('MThd'.codeUnits);
    header.add(_uint32(6)); // header chunk length
    header.add(_uint16(tracks.length == 1 ? 0 : 1));
    header.add(_uint16(tracks.length));
    header.add(_uint16(ticksPerQuarterNote));

    final full = BytesBuilder();
    full.add(header.toBytes());
    for (var i = 0; i < tracks.length; i++) {
      final program = (instrumentPrograms == null || instrumentPrograms.isEmpty)
          ? null
          : instrumentPrograms[i < instrumentPrograms.length ? i : instrumentPrograms.length - 1];
      full.add(_writeTrack(tracks[i], bpm: bpm, channel: channelForTrack(i), instrumentProgram: program));
    }
    return full.toBytes();
  }

  /// MIDI channel (0-15) for track [trackIndex]. Channel 9 (General
  /// MIDI channel 10) is reserved for percussion - any program change
  /// on it is ignored and notes play as drum sounds - so it's skipped.
  /// With more than 15 tracks (never seen in a hymn) channels are
  /// reused, and tracks sharing a channel share its instrument.
  static int channelForTrack(int trackIndex) {
    final c = trackIndex % 15;
    return c >= 9 ? c + 1 : c;
  }

  static Uint8List _writeTrack(
    List<MidiNoteEvent> events, {
    required int bpm,
    required int channel,
    required int? instrumentProgram,
  }) {
    final trackBytes = BytesBuilder();

    // Tempo meta event: microseconds per quarter note = 60,000,000 / bpm.
    // Written into every track (harmless if repeated) so each track is
    // correctly timed on its own, without relying on a separate
    // tempo-only track that other players might not expect.
    final microsPerQuarter = (60000000 / bpm.clamp(20, 300)).round();
    trackBytes.add([0x00, 0xFF, 0x51, 0x03, ..._uint24(microsPerQuarter)]);

    // Program (instrument) change before any notes, on the same channel
    // every note-on/off below uses, so this is the one instrument that
    // plays for the whole track.
    if (instrumentProgram != null) {
      trackBytes.add([0x00, 0xC0 | channel, instrumentProgram.clamp(0, 127).toInt()]);
    }

    // Flatten every note into an absolute-time note-on and note-off,
    // then emit them in time order with delta times between them.
    final raw = <_RawEvent>[];
    for (final e in events) {
      if (e.durationTicks <= 0) continue;
      raw.add(_RawEvent(e.startTick, false, e.midiNote));
      raw.add(_RawEvent(e.endTick, true, e.midiNote));
    }
    // At the same tick, note-offs go before note-ons: otherwise a
    // repeated note (same pitch ending and restarting on one tick)
    // would be switched on and then immediately switched off again.
    raw.sort((a, b) {
      final byTick = a.tick.compareTo(b.tick);
      if (byTick != 0) return byTick;
      if (a.isOff != b.isOff) return a.isOff ? -1 : 1;
      return a.note.compareTo(b.note);
    });

    var lastTick = 0;
    for (final r in raw) {
      trackBytes.add(_variableLengthQuantity(r.tick - lastTick));
      lastTick = r.tick;
      // Note-off sent as 0x80 with velocity 0.
      trackBytes.add(r.isOff ? [0x80 | channel, r.note, 0] : [0x90 | channel, r.note, 100]);
    }

    // End of track meta event.
    trackBytes.add([0x00, 0xFF, 0x2F, 0x00]);

    final trackData = trackBytes.toBytes();
    final track = BytesBuilder();
    track.add('MTrk'.codeUnits);
    track.add(_uint32(trackData.length));
    track.add(trackData);
    return track.toBytes();
  }

  static List<int> _uint16(int value) => [(value >> 8) & 0xFF, value & 0xFF];

  static List<int> _uint24(int value) => [
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ];

  static List<int> _uint32(int value) => [
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ];

  /// MIDI variable-length quantity encoding - same format used for
  /// both delta-times and meta-event lengths.
  static List<int> _variableLengthQuantity(int value) {
    if (value == 0) return [0x00];
    final bytes = <int>[];
    var v = value;
    bytes.add(v & 0x7F);
    v >>= 7;
    while (v > 0) {
      bytes.add((v & 0x7F) | 0x80);
      v >>= 7;
    }
    return bytes.reversed.toList();
  }
}

class _RawEvent {
  final int tick;
  final bool isOff;
  final int note;
  const _RawEvent(this.tick, this.isOff, this.note);
}
