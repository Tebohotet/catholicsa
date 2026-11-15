import 'dart:typed_data';

/// One musical note or rest to write into the MIDI file.
class MidiNoteEvent {
  final int? midiNote; // null means a rest
  final int durationTicks;
  const MidiNoteEvent({required this.midiNote, required this.durationTicks});
}

/// Writes a Standard MIDI File - the same approach already tested and
/// verified working in the Node.js version of this pipeline (confirmed
/// real MThd/MTrk header bytes and correct note-on data on a real test
/// file before this was ported). Ported directly rather than relying
/// on a third-party Dart package whose own correctness couldn't be
/// independently confirmed.
class SimpleMidiWriter {
  static const int ticksPerQuarterNote = 480;

  /// Writes one track per element of [tracks]. Every track starts at
  /// time zero and is played back simultaneously, so a hymn
  /// arrangement's separate voices (SATB, or melody + accompaniment)
  /// all sound together instead of one voice replacing the others.
  /// A single track still produces the same file as before: format 0
  /// (single-track) rather than format 1, with everything else
  /// unchanged - the common single-voice case is untouched.
  static Uint8List write(List<List<MidiNoteEvent>> tracks) {
    if (tracks.isEmpty) {
      throw ArgumentError('write() needs at least one track of events.');
    }

    final header = BytesBuilder();
    header.add('MThd'.codeUnits);
    header.add(_uint32(6)); // header chunk length
    header.add(_uint16(tracks.length == 1 ? 0 : 1)); // format 0 (single track) or 1 (several, simultaneous)
    header.add(_uint16(tracks.length));
    header.add(_uint16(ticksPerQuarterNote));

    final full = BytesBuilder();
    full.add(header.toBytes());
    for (final trackEvents in tracks) {
      full.add(_writeTrack(trackEvents));
    }
    return full.toBytes();
  }

  static Uint8List _writeTrack(List<MidiNoteEvent> events) {
    final trackBytes = BytesBuilder();

    // Tempo meta event: 120 BPM = 500000 microseconds per quarter note.
    // Written into every track (harmless if repeated) so each track is
    // correctly timed on its own, without relying on a separate
    // tempo-only track that other players might not expect.
    trackBytes.add([0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]);

    for (final event in events) {
      if (event.midiNote == null) {
        // A rest is just silence - advance time with no note event.
        continue;
      }
      final note = event.midiNote!;
      // Note on, channel 0, velocity 100 - delta time 0 (starts immediately
      // after the previous event's duration elapsed).
      trackBytes.add(_variableLengthQuantity(0));
      trackBytes.add([0x90, note, 100]);
      // Note off after the note's full duration.
      trackBytes.add(_variableLengthQuantity(event.durationTicks));
      trackBytes.add([0x80, note, 0]);
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