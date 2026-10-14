import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ChatVoiceCall extends StatefulWidget {
  static bool active = false;

  const ChatVoiceCall({
    super.key,
    required this.conversation,
    required this.user,
    required this.call,
    required this.incoming,
    this.video = false,
  });

  final DocumentReference<Map<String, dynamic>> conversation;
  final User user;
  final DocumentReference<Map<String, dynamic>> call;
  final bool incoming;
  final bool video;

  @override
  State<ChatVoiceCall> createState() => _ChatVoiceCallState();
}

class _ChatVoiceCallState extends State<ChatVoiceCall> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localVideo = RTCVideoRenderer();

  late final Future<void> _rendererReady;

  Future<void>? _cleanupFuture;

  RTCPeerConnection? _peer;
  MediaStream? _local;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _callSubscription;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _candidateSubscription;

  final List<RTCIceCandidate> _pendingCandidates = [];

  bool _remoteReady = false;
  bool _muted = false;
  bool _cameraOff = false;
  bool _ended = false;
  bool _busy = false;

  html.AudioElement? _ringAudio;
  Timer? _ringTimer;

  String _status = 'Preparing call…';

  @override
  void initState() {
    super.initState();

    ChatVoiceCall.active = true;

    _rendererReady = Future.wait([
      _remoteRenderer.initialize(),
      _localVideo.initialize(),
    ]);

    _watchCall();

    if (!widget.incoming) {
      _startOutgoing();
    } else {
      _status = widget.video
          ? 'Incoming video call'
          : 'Incoming voice call';
    }
  }

  // ------------------------------------------------------------
  // RINGBACK
  // ------------------------------------------------------------

  void _startRingback() {
    if (widget.incoming || _ringTimer != null || _ended) {
      return;
    }

    _playRingbackBurst();

    _ringTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _playRingbackBurst(),
    );
  }

  void _playRingbackBurst() {
    if (_ended || _remoteReady) {
      return;
    }

    try {
      _ringAudio ??= html.AudioElement(
        'data:audio/wav;base64,UklGRiQZAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAZAACAkqKutbeyqJmIdWRWTUlLVGFxg5WlsLa2saWWhHJhVExJTFVjdIaYp7G3tq+jk4FvX1JLSU5YZneKm6mzt7WtoJB+bFxRSkpPWml7jZ6rtLe0q56Ne2laT0pKUVxsfpCgrbW3s6mbindmWE5JS1Jfb4GTo6+2t7GnmIZ0Y1VMSUxUYXKElqWxtrawpZWDcWFUS0lNVmR1iJmosre1rqKSgG5eUktJTlhneIucqrO3tayfj31rW1BKSk9banyOn6y0t7SrnYx6aFlPSUpRXW1/kaGutbeyqJqJdmVXTUlLU2BwgpSkr7a2saaXhXNiVUxJTFVic4WXprG2tq+klIJwYFNLSU1XZXaJmqiyt7WuoZF/bV1RSklPWWh6jJ2rtLe0rJ+OfGpbT0pKUFtrfY+frLW3s6qci3hnWE5JS1JeboCSoq61t7KomYh1ZFZNSUtUYXGDlaWwtraxpZaEcmFUTElMVWN0hpinsbe2r6OTgW9fUktJTlhmd4qbqbO3ta2gkH5sXFFKSk9aaXuNnqu0t7Srno17aVpPSkpRXGx+kKCttbezqZuKd2ZYTklLUl9vgZOjr7a3saeYhnRjVUxJTFRhcoSWpbG2trCllYNxYVRLSU1WZHWImaiyt7WuopKAbl5SS0lOWGd4i5yqs7e1rJ+PfWtbUEpKT1tqfI6frLS3tKudjHpoWU9JSlFdbX+Roa61t7Komol2ZVdNSUtTYHCClKSvtraxppeFc2JVTElMVWJzhZemsba2r6SUgnBgU0tJTVdldomaqLK3ta6hkX9tXVFKSU9ZaHqMnau0t7Ssn458altPSkpQW2t9j5+stbezqpyLeGdYTklLUl5u',
      );

      _ringAudio!
        ..currentTime = 0
        ..volume = 0.45
        ..play();
    } catch (_) {}
  }

  void _stopRingback() {
    _ringTimer?.cancel();
    _ringTimer = null;

    try {
      _ringAudio?.pause();
      _ringAudio?.currentTime = 0;
    } catch (_) {}

    _ringAudio = null;
  }

  // ------------------------------------------------------------
  // FIRESTORE CALL WATCHER
  // ------------------------------------------------------------

  void _watchCall() {
    _callSubscription = widget.call.snapshots().listen(
      (snapshot) async {
        if (!mounted || _ended) {
          return;
        }

        final data = snapshot.data();

        if (data == null) {
          return;
        }

        final state =
            data['status'] as String? ?? 'ringing';

        if (state == 'ended' || state == 'declined') {
          _stopRingback();
          _finishLocally();
          return;
        }

        if (!widget.incoming &&
            state == 'accepted' &&
            !_remoteReady) {
          _stopRingback();

          final answer = data['answer'];

          if (answer is Map &&
              answer['sdp'] is String) {
            try {
              await _peer?.setRemoteDescription(
                RTCSessionDescription(
                  answer['sdp'] as String,
                  'answer',
                ),
              );

              _remoteReady = true;

              await _flushCandidates();

              if (mounted) {
                setState(
                  () => _status = 'Connecting…',
                );
              }
            } catch (error) {
              if (mounted) {
                setState(
                  () => _status =
                      'Connection error: $error',
                );
              }
            }
          }
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(
            () => _status =
                'Call signaling unavailable: $error',
          );
        }
      },
    );

    _candidateSubscription =
        widget.call
            .collection('candidates')
            .snapshots()
            .listen(
      (snapshot) async {
        for (final change in snapshot.docChanges) {
          if (change.type !=
              DocumentChangeType.added) {
            continue;
          }

          final data = change.doc.data();

          if (data == null ||
              data['senderId'] == widget.user.uid) {
            continue;
          }

          if (data['candidate'] is! String) {
            continue;
          }

          final candidate = RTCIceCandidate(
            data['candidate'] as String,
            data['sdpMid'] as String?,
            (data['sdpMLineIndex'] as num?)
                ?.toInt(),
          );

          if (!_remoteReady || _peer == null) {
            _pendingCandidates.add(candidate);
          } else {
            try {
              await _peer!.addCandidate(candidate);
            } catch (_) {}
          }
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(
            () => _status =
                'ICE signaling unavailable: $error',
          );
        }
      },
    );
  }

  Future<void> _flushCandidates() async {
    final peer = _peer;

    if (peer == null) {
      return;
    }

    for (final candidate in _pendingCandidates) {
      try {
        await peer.addCandidate(candidate);
      } catch (_) {}
    }

    _pendingCandidates.clear();
  }

  // ------------------------------------------------------------
  // SECURE CLOUDFLARE TURN
  // ------------------------------------------------------------

  Future<List<dynamic>> _getIceServers() async {
    final List<dynamic> iceServers = [
      {
        'urls': 'stun:stun.l.google.com:19302',
      },
      {
        'urls': 'stun:stun1.l.google.com:19302',
      },
    ];

    const endpoint =
        String.fromEnvironment('PUSH_WORKER_URL');

    if (endpoint.isEmpty) {
      return iceServers;
    }

    try {
      final idToken =
          await widget.user.getIdToken();

      if (idToken == null) {
        return iceServers;
      }

      final response =
          await html.HttpRequest.request(
        '$endpoint/turn-credentials',
        method: 'POST',
        requestHeaders: <String, String>{
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.status != 200) {
        return iceServers;
      }

      final dynamic decoded = jsonDecode(
        response.responseText ?? '{}',
      );

      if (decoded is Map &&
          decoded['iceServers'] is List) {
        final servers =
            decoded['iceServers'] as List;

        for (final server in servers) {
          if (server is Map) {
            iceServers.add(
              Map<String, dynamic>.from(server),
            );
          }
        }
      }
    } catch (error) {
      throw StateError('Secure call relay unavailable. Check Cloudflare TURN setup.');
    }

    if (iceServers.length <= 2) {
      throw StateError('Cloudflare TURN returned no relay servers.');
    }

    return iceServers;
  }

  // ------------------------------------------------------------
  // MICROPHONE / CAMERA / WEBRTC
  // ------------------------------------------------------------

  Future<void> _prepareMedia() async {
    await _rendererReady;

    _local =
        await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
      },
      'video': widget.video
          ? {
              'facingMode': 'user',
            }
          : false,
    });

    if (widget.video) {
      _localVideo.srcObject = _local;
    }

    if (_ended) {
      await _cleanupMedia();
      throw StateError(
        'The call has ended.',
      );
    }

    if (mounted) {
      setState(
        () => _status = 'Connecting securely…',
      );
    }

    final iceServers =
        await _getIceServers();

    _peer = await createPeerConnection({
      'iceServers': iceServers,
      'iceCandidatePoolSize': 10,
    });

    _peer!.onTrack = (event) {
      if (_ended || event.streams.isEmpty) {
        return;
      }

      _remoteRenderer.srcObject =
          event.streams.first;

      if (mounted) {
        setState(() {});
      }
    };

    // Audio call = microphone track.
    // Video call = microphone + camera tracks.
    for (final track in _local!.getTracks()) {
      await _peer!.addTrack(
        track,
        _local!,
      );
    }

    _peer!.onIceCandidate = (candidate) {
      if (_ended ||
          candidate.candidate == null) {
        return;
      }

      widget.call
          .collection('candidates')
          .add({
        'senderId': widget.user.uid,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex':
            candidate.sdpMLineIndex,
        'createdAt':
            FieldValue.serverTimestamp(),
      }).then<void>(
        (_) {},
        onError: (Object error) {
          if (mounted && !_ended) {
            setState(
              () => _status =
                  'Call connection data could not be sent: $error',
            );
          }
        },
      );
    };

    _peer!.onConnectionState = (state) {
      if (!mounted || _ended) {
        return;
      }

      if (state ==
          RTCPeerConnectionState
              .RTCPeerConnectionStateConnected) {
        setState(
          () => _status = 'Connected',
        );
      } else if (state ==
          RTCPeerConnectionState
              .RTCPeerConnectionStateFailed) {
        setState(
          () => _status =
              'Connection failed. Please try again.',
        );
      } else if (state ==
          RTCPeerConnectionState
              .RTCPeerConnectionStateDisconnected) {
        setState(
          () => _status = 'Reconnecting…',
        );
      }
    };
  }

  // ------------------------------------------------------------
  // OUTGOING CALL
  // ------------------------------------------------------------

  Future<void> _startOutgoing() async {
    try {
      await _prepareMedia();

      final offer =
          await _peer!.createOffer();

      await _peer!.setLocalDescription(
        offer,
      );

      await widget.call.update({
        'offer': {
          'sdp': offer.sdp,
          'type': 'offer',
        },
        'status': 'ringing',
      });

      if (mounted) {
        setState(
          () => _status = 'Ringing…',
        );
      }

      _startRingback();

      unawaited(
        _sendBackgroundRing(),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _status =
              'Unable to call: $error',
        );
      }

      await _cleanup();
    }
  }

  // ------------------------------------------------------------
  // BACKGROUND CALL NOTIFICATION
  // ------------------------------------------------------------

  Future<void> _sendBackgroundRing() async {
    const endpoint =
        String.fromEnvironment(
      'PUSH_WORKER_URL',
    );

    if (endpoint.isEmpty) {
      return;
    }

    try {
      final idToken =
          await widget.user.getIdToken();

      if (idToken == null) {
        return;
      }

      await html.HttpRequest.request(
        '$endpoint/notify-call',
        method: 'POST',
        requestHeaders: <String, String>{
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        sendData:
            jsonEncode(<String, String>{
          'conversationId':
              widget.conversation.id,
          'callId': widget.call.id,
        }),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Background alert failed: ${error.toString()}',
            ),
          ),
        );
      }
    }
  }

  // ------------------------------------------------------------
  // ANSWER CALL
  // ------------------------------------------------------------

  Future<void> _answer() async {
    if (_busy) {
      return;
    }

    setState(
      () => _busy = true,
    );

    try {
      final snapshot =
          await widget.call.get();

      final offer =
          snapshot.data()?['offer'];

      if (offer is! Map ||
          offer['sdp'] is! String) {
        throw StateError(
          'The caller has not finished connecting. Try again.',
        );
      }

      await _prepareMedia();

      await _peer!.setRemoteDescription(
        RTCSessionDescription(
          offer['sdp'] as String,
          'offer',
        ),
      );

      _remoteReady = true;

      await _flushCandidates();

      final answer =
          await _peer!.createAnswer();

      await _peer!.setLocalDescription(
        answer,
      );

      await widget.call.update({
        'answer': {
          'sdp': answer.sdp,
          'type': 'answer',
        },
        'status': 'accepted',
      });

      if (mounted) {
        setState(
          () => _status = 'Connecting…',
        );
      }
    } catch (error) {
      await _cleanupMedia();

      if (mounted) {
        setState(
          () => _status =
              'Cannot answer: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(
          () => _busy = false,
        );
      }
    }
  }

  // ------------------------------------------------------------
  // CALL HISTORY
  // ------------------------------------------------------------

  Future<void> _saveCallHistory(
    String label,
  ) async {
    try {
      await widget.conversation
          .collection('messages')
          .add({
        'senderId': widget.user.uid,
        'type': 'call',
        'text': label,
        'readBy': [
          widget.user.uid,
        ],
        'createdAt':
            FieldValue.serverTimestamp(),
      });

      await widget.conversation.update({
        'lastMessage': widget.video
            ? '📹 $label'
            : '📞 $label',
        'updatedAt':
            FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _hangUp() async {
    if (_ended) {
      return;
    }

    _ended = true;

    try {
      final declined =
          widget.incoming &&
              _peer == null;

      await widget.call.update({
        'status': declined
            ? 'declined'
            : 'ended',
        'endedAt':
            FieldValue.serverTimestamp(),
      });

      final type =
          widget.video
              ? 'video call'
              : 'voice call';

      String label;

      if (declined) {
        label = 'Declined $type';
      } else if (_remoteReady) {
        label = widget.video
            ? 'Video call'
            : 'Voice call';
      } else {
        label = 'Missed $type';
      }

      await _saveCallHistory(label);
    } catch (_) {}

    await _cleanup();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // ------------------------------------------------------------
  // CLEANUP
  // ------------------------------------------------------------

  Future<void> _cleanup() =>
      _cleanupFuture ??= _cleanupAll();

  Future<void> _cleanupAll() async {
    _stopRingback();

    await _callSubscription?.cancel();
    await _candidateSubscription?.cancel();

    await _cleanupMedia();

    await _rendererReady;

    await _remoteRenderer.dispose();
    await _localVideo.dispose();
  }

  Future<void> _cleanupMedia() async {
    _remoteReady = false;

    _remoteRenderer.srcObject = null;
    _localVideo.srcObject = null;

    for (final track
        in _local?.getTracks() ??
            <MediaStreamTrack>[]) {
      track.stop();
    }

    await _local?.dispose();

    await _peer?.close();
    await _peer?.dispose();

    _local = null;
    _peer = null;
  }

  void _finishLocally() {
    if (_ended) {
      return;
    }

    _ended = true;

    _cleanup();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    if (!_ended) {
      widget.call.update({
        'status':
            widget.incoming &&
                    !_remoteReady
                ? 'declined'
                : 'ended',
        'endedAt':
            FieldValue.serverTimestamp(),
      }).catchError(
        (Object _) {},
      );
    }

    _ended = true;
    ChatVoiceCall.active = false;

    _cleanup();

    super.dispose();
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.video
              ? 'Chat Plus video call'
              : 'Chat Plus voice call',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              if (widget.video)
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          color: Colors.black,
                          child: RTCVideoView(
                            _remoteRenderer,
                            objectFit:
                                RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 16,
                        top: 16,
                        width: 110,
                        height: 150,
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(
                            14,
                          ),
                          child: Container(
                            color: Colors.black,
                            child: RTCVideoView(
                              _localVideo,
                              mirror: true,
                              objectFit:
                                  RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitCover,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                SizedBox(
                  width: 1,
                  height: 1,
                  child: RTCVideoView(
                    _remoteRenderer,
                  ),
                ),
                const CircleAvatar(
                  radius: 48,
                  child: Icon(
                    Icons.person,
                    size: 48,
                  ),
                ),
              ],

              const SizedBox(
                height: 24,
              ),

              Padding(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 20,
                ),
                child: Text(
                  _status,
                  textAlign:
                      TextAlign.center,
                  style:
                      const TextStyle(
                    fontSize: 22,
                  ),
                ),
              ),

              const SizedBox(
                height: 40,
              ),

              if (widget.incoming &&
                  _peer == null)
                FilledButton.icon(
                  onPressed:
                      _busy ? null : _answer,
                  icon:
                      const Icon(Icons.call),
                  label:
                      const Text('Answer'),
                ),

              if (_peer != null)
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  alignment:
                      WrapAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      tooltip: _muted
                          ? 'Unmute'
                          : 'Mute',
                      iconSize: 32,
                      onPressed: () {
                        final next =
                            !_muted;

                        for (final track
                            in _local
                                    ?.getAudioTracks() ??
                                <MediaStreamTrack>[]) {
                          track.enabled =
                              !next;
                        }

                        setState(
                          () => _muted =
                              next,
                        );
                      },
                      icon: Icon(
                        _muted
                            ? Icons.mic_off
                            : Icons.mic,
                      ),
                    ),

                    if (widget.video)
                      IconButton.filledTonal(
                        tooltip: _cameraOff
                            ? 'Turn camera on'
                            : 'Turn camera off',
                        iconSize: 32,
                        onPressed: () {
                          final next =
                              !_cameraOff;

                          for (final track
                              in _local
                                      ?.getVideoTracks() ??
                                  <MediaStreamTrack>[]) {
                            track.enabled =
                                !next;
                          }

                          setState(
                            () => _cameraOff =
                                next,
                          );
                        },
                        icon: Icon(
                          _cameraOff
                              ? Icons
                                  .videocam_off
                              : Icons
                                  .videocam,
                        ),
                      ),

                    if (widget.video)
                      IconButton.filledTonal(
                        tooltip:
                            'Switch camera',
                        iconSize: 32,
                        onPressed:
                            () async {
                          final tracks =
                              _local
                                      ?.getVideoTracks() ??
                                  <MediaStreamTrack>[];

                          if (tracks
                              .isNotEmpty) {
                            try {
                              await Helper
                                  .switchCamera(
                                tracks.first,
                              );
                            } catch (_) {}
                          }
                        },
                        icon: const Icon(
                          Icons.cameraswitch,
                        ),
                      ),
                  ],
                ),

              const SizedBox(
                height: 20,
              ),

              FilledButton.icon(
                style:
                    FilledButton.styleFrom(
                  backgroundColor:
                      Colors.red,
                ),
                onPressed: _hangUp,
                icon: const Icon(
                  Icons.call_end,
                ),
                label: Text(
                  widget.incoming &&
                          _peer == null
                      ? 'Decline'
                      : 'End call',
                ),
              ),

              const SizedBox(
                height: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
