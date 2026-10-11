import 'dart:html' as html;

// Browser sound must first be enabled by a user gesture.
class CallRingtone {
  static final html.AudioElement _audio =
      html.AudioElement('assets/assets/ringtone.wav')..loop = true;
  static bool enabled = false;
  static Future<void> enable() async {
    await _audio.play();
    enabled = true;
    _audio.pause();
    _audio.currentTime = 0;
  }

  static Future<void> start() async {
    if (!enabled) return;
    try {
      await _audio.play();
    } catch (_) {
      enabled = false;
    }
  }

  static void stop() {
    _audio.pause();
    _audio.currentTime = 0;
  }
}
