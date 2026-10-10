import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// First-stage one-to-one audio calling. Both people must have Chat Plus open.
/// Firestore rules must authorize calls and candidates for conversation members.
class ChatVoiceCall extends StatefulWidget {
  const ChatVoiceCall({
    super.key,
    required this.conversation,
    required this.user,
    required this.call,
    required this.incoming,
  });

  final DocumentReference<Map<String, dynamic>> conversation;
  final User user;
  final DocumentReference<Map<String, dynamic>> call;
  final bool incoming;

  @override
  State<ChatVoiceCall> createState() => _ChatVoiceCallState();
}

class _ChatVoiceCallState extends State<ChatVoiceCall> {
  RTCPeerConnection? _peer;
  MediaStream? _local;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _candidateSubscription;
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteReady = false;
  bool _muted = false;
  bool _ended = false;
  bool _busy = false;
  String _status = 'Preparing call…';

  @override
  void initState() {
    super.initState();
    _watchCall();
    if (!widget.incoming) {
      _startOutgoing();
    } else {
      _status = 'Incoming voice call';
    }
  }

  void _watchCall() {
    _callSubscription = widget.call.snapshots().listen((snapshot) async {
      if (!mounted || _ended) return;
      final data = snapshot.data();
      if (data == null) return;
      final state = data['status'] as String? ?? 'ringing';
      if (state == 'ended' || state == 'declined') {
        _finishLocally();
        return;
      }
      if (!widget.incoming && state == 'accepted' && !_remoteReady) {
        final answer = data['answer'];
        if (answer is Map && answer['sdp'] is String) {
          try {
            await _peer?.setRemoteDescription(
              RTCSessionDescription(answer['sdp'] as String, 'answer'),
            );
            _remoteReady = true;
            await _flushCandidates();
            if (mounted) setState(() => _status = 'Connecting…');
          } catch (error) {
            if (mounted) setState(() => _status = 'Connection error: $error');
          }
        }
      }
    }, onError: (Object error) {
      if (mounted) setState(() => _status = 'Call signaling unavailable: $error');
    });
    _candidateSubscription = widget.call.collection('candidates').snapshots().listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null || data['senderId'] == widget.user.uid) continue;
        if (data['candidate'] is! String) continue;
        final candidate = RTCIceCandidate(
          data['candidate'] as String,
          data['sdpMid'] as String?,
          (data['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (!_remoteReady || _peer == null) {
          _pendingCandidates.add(candidate);
        } else {
          try { await _peer!.addCandidate(candidate); } catch (_) {}
        }
      }
    }, onError: (Object error) {
      if (mounted) setState(() => _status = 'ICE signaling unavailable: $error');
    });
  }

  Future<void> _flushCandidates() async {
    final peer = _peer;
    if (peer == null) return;
    for (final candidate in _pendingCandidates) {
      try { await peer.addCandidate(candidate); } catch (_) {}
    }
    _pendingCandidates.clear();
  }

  Future<void> _prepareMedia() async {
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true},
      'video': false,
    });
    _peer = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
    });
    for (final track in _local!.getAudioTracks()) {
      await _peer!.addTrack(track, _local!);
    }
    _peer!.onIceCandidate = (candidate) {
      if (_ended || candidate.candidate == null) return;
      widget.call.collection('candidates').add({
        'senderId': widget.user.uid,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'createdAt': FieldValue.serverTimestamp(),
      }).catchError((Object _) => null);
    };
    _peer!.onConnectionState = (state) {
      if (!mounted || _ended) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() => _status = 'Connected');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        setState(() => _status = 'Connection failed — a TURN server may be required');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        setState(() => _status = 'Reconnecting…');
      }
    };
  }

  Future<void> _startOutgoing() async {
    try {
      await _prepareMedia();
      final offer = await _peer!.createOffer();
      await _peer!.setLocalDescription(offer);
      await widget.call.update({
        'offer': {'sdp': offer.sdp, 'type': 'offer'},
        'status': 'ringing',
      });
      if (mounted) setState(() => _status = 'Ringing…');
    } catch (error) {
      if (mounted) setState(() => _status = 'Unable to call: $error');
      await _hangUp();
    }
  }

  Future<void> _answer() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final snapshot = await widget.call.get();
      final offer = snapshot.data()?['offer'];
      if (offer is! Map || offer['sdp'] is! String) {
        throw StateError('The caller has not finished connecting. Try again.');
      }
      await _prepareMedia();
      await _peer!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'] as String, 'offer'),
      );
      _remoteReady = true;
      await _flushCandidates();
      final answer = await _peer!.createAnswer();
      await _peer!.setLocalDescription(answer);
      await widget.call.update({
        'answer': {'sdp': answer.sdp, 'type': 'answer'},
        'status': 'accepted',
      });
      if (mounted) setState(() => _status = 'Connecting…');
    } catch (error) {
      if (mounted) setState(() => _status = 'Cannot answer: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hangUp() async {
    if (_ended) return;
    _ended = true;
    try {
      await widget.call.update({
        'status': widget.incoming && _peer == null ? 'declined' : 'ended',
        'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    await _cleanup();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cleanup() async {
    await _callSubscription?.cancel();
    await _candidateSubscription?.cancel();
    for (final track in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    await _local?.dispose();
    await _peer?.close();
    await _peer?.dispose();
    _local = null;
    _peer = null;
  }

  void _finishLocally() {
    if (_ended) return;
    _ended = true;
    _cleanup();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _ended = true;
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chat Plus voice call')),
    body: SafeArea(
      child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircleAvatar(radius: 48, child: Icon(Icons.person, size: 48)),
          const SizedBox(height: 24),
          Text(_status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 40),
          if (widget.incoming && _peer == null)
            FilledButton.icon(
              onPressed: _busy ? null : _answer,
              icon: const Icon(Icons.call),
              label: const Text('Answer'),
            ),
          if (_peer != null)
            IconButton.filledTonal(
              tooltip: _muted ? 'Unmute' : 'Mute',
              iconSize: 32,
              onPressed: () {
                final next = !_muted;
                for (final track in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
                  track.enabled = !next;
                }
                setState(() => _muted = next);
              },
              icon: Icon(_muted ? Icons.mic_off : Icons.mic),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: _hangUp,
            icon: const Icon(Icons.call_end),
            label: Text(widget.incoming && _peer == null ? 'Decline' : 'End call'),
          ),
        ]),
      ),
    ),
  );
}
