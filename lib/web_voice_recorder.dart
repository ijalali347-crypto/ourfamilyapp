import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class RecordedVoice {
  const RecordedVoice(this.bytes, this.mimeType, this.seconds);
  final Uint8List bytes;
  final String mimeType;
  final int seconds;
}

/// Uses a format supported by the actual browser, rather than assuming WebM.
class WebVoiceRecorder {
  html.MediaStream? _stream;
  html.MediaRecorder? _recorder;
  final List<html.Blob> _chunks = [];
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Completer<void>? _stopped;
  DateTime? _started;

  Future<void> start() async {
    if (_recorder != null) throw StateError('Recording is already active.');
    if (html.window.isSecureContext != true) {
      throw StateError(
        'Open Chat Plus using its HTTPS link to use the microphone.',
      );
    }
    try {
      _stream = await html.window.navigator.mediaDevices!.getUserMedia({
        'audio': true,
      });
      final type = [
        'audio/webm;codecs=opus',
        'audio/mp4',
        'audio/webm',
        'audio/ogg;codecs=opus',
      ].firstWhere(html.MediaRecorder.isTypeSupported, orElse: () => '');
      _chunks.clear();
      _stopped = Completer<void>();
      _recorder = html.MediaRecorder(_stream!, {
        if (type.isNotEmpty) 'mimeType': type,
        'audioBitsPerSecond': 64000,
      });
      _subscriptions.add(
        const html.EventStreamProvider<html.BlobEvent>('dataavailable')
            .forTarget(_recorder!)
            .listen((event) {
              if (event.data != null && event.data!.size > 0)
                _chunks.add(event.data!);
            }),
      );
      _subscriptions.add(
        const html.EventStreamProvider<html.Event>('stop')
            .forTarget(_recorder!)
            .listen((_) {
              if (!_stopped!.isCompleted) _stopped!.complete();
            }),
      );
      _subscriptions.add(
        _recorder!.onError.listen((event) {
          if (!_stopped!.isCompleted)
            _stopped!.completeError(StateError('Microphone recording failed.'));
        }),
      );
      _recorder!.start(1000);
      _started = DateTime.now();
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  Future<RecordedVoice> stop() async {
    final recorder = _recorder;
    if (recorder == null) throw StateError('No voice recording is active.');
    final seconds = DateTime.now().difference(_started!).inSeconds.clamp(1, 60);
    try {
      recorder.stop();
      await _stopped!.future.timeout(const Duration(seconds: 10));
      final mime =
          recorder.mimeType ?? (_chunks.isEmpty ? '' : _chunks.first.type);
      final blob = html.Blob(_chunks, mime);
      final reader = html.FileReader();
      final done = Completer<Uint8List>();
      reader.onLoad.first.then((_) {
        final data = reader.result;
        if (data is ByteBuffer) {
          done.complete(data.asUint8List());
        } else if (data is Uint8List) {
          done.complete(data);
        } else {
          done.completeError(StateError('Could not read the recorded audio.'));
        }
      });
      reader.onError.first.then((_) {
        if (!done.isCompleted)
          done.completeError(StateError('Could not read the recorded audio.'));
      });
      reader.readAsArrayBuffer(blob);
      final bytes = await done.future.timeout(const Duration(seconds: 10));
      if (bytes.isEmpty)
        throw StateError('The recording is empty. Please try again.');
      if (bytes.length > 600000)
        throw StateError(
          'This recording is too large. Please record a shorter message.',
        );
      return RecordedVoice(bytes, mime.split(';').first, seconds);
    } finally {
      await dispose();
    }
  }

  Future<void> dispose() async {
    final recorder = _recorder;
    _recorder = null;
    if (recorder?.state == 'recording') recorder!.stop();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    for (final track in _stream?.getTracks() ?? <html.MediaStreamTrack>[]) {
      track.stop();
    }
    _stream = null;
    _chunks.clear();
  }
}
