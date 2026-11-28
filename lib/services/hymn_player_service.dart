import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// One global, app-wide hymn player - not tied to any single screen or
/// dialog. Before this, _HymnAudioPlayerDialog (hymns_screen.dart) owned
/// its own private AudioPlayer, so the only way to pause/stop/see what was
/// playing was that dialog's own UI - the moment you pushed another screen
/// on top of it (like "View PDF"), the song kept playing in the
/// background with absolutely no way to control it until you navigated
/// back. The project owner's own ask: "Can I have that music player thing
/// at the bottom of the pages incase I want to stop a song... while I am
/// on other pages." This service is the shared state both the dialog and
/// the new persistent mini-player bar (see HomeScreen's
/// bottomNavigationBar) read from and control - a ChangeNotifier so either
/// one can rebuild the instant the other changes something.
class HymnPlayerService extends ChangeNotifier {
  HymnPlayerService._internal() {
    _player.onPlayerStateChanged.listen((s) { _state = s; notifyListeners(); });
    _player.onPositionChanged.listen((p) { _position = p; notifyListeners(); });
    _player.onDurationChanged.listen((d) { _duration = d; notifyListeners(); });
    _player.onPlayerComplete.listen((_) {
      _state = PlayerState.stopped;
      _position = Duration.zero;
      notifyListeners();
    });
  }
  static final HymnPlayerService instance = HymnPlayerService._internal();

  final AudioPlayer _player = AudioPlayer();

  String? _title;
  String? _pdfUrl;
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  String? get title => _title;
  // Admin-only - see the isAdmin check at hymns_screen.dart's call site -
  // lets the mini-player's "owner" (the dialog) offer its own "View PDF"
  // button without this service needing to know about admin status itself.
  String? get pdfUrl => _pdfUrl;
  PlayerState get state => _state;
  Duration get position => _position;
  Duration get duration => _duration;
  String? get error => _error;
  bool get hasTrack => _title != null;
  bool get isPlaying => _state == PlayerState.playing;

  /// Starts a new hymn, or - if this exact hymn is already loaded (the
  /// dialog was closed and reopened on the same one) - just resumes it
  /// from wherever it was, instead of restarting the audio from zero.
  Future<void> play({required String title, required String audioUrl, String? pdfUrl}) async {
    _error = null;
    if (_title == title) {
      await resume();
      return;
    }
    _title = title;
    _pdfUrl = pdfUrl;
    _position = Duration.zero;
    notifyListeners();
    try {
      await _player.stop();
      await _player.play(UrlSource(audioUrl));
    } catch (e) {
      _error = 'Could not play this hymn: $e';
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  Future<void> resume() async => _player.resume();

  Future<void> seek(Duration d) => _player.seek(d);

  /// Fully ends playback and clears the current track - this is what
  /// makes the mini-player bar disappear (see hasTrack above). Pausing
  /// (togglePlayPause) deliberately does NOT do this - a paused hymn stays
  /// loaded and visible in the mini-player so it can be resumed.
  Future<void> stop() async {
    await _player.stop();
    _title = null;
    _pdfUrl = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _state = PlayerState.stopped;
    _error = null;
    notifyListeners();
  }
}
