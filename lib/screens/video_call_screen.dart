import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chat_app/services/call_service.dart';
import 'package:chat_app/widgets/call_overlay.dart'; // استيراد نظام الطبقة العائمة

class VideoCallScreen extends StatefulWidget {
  final Call call;

  const VideoCallScreen({super.key, required this.call});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  late RtcEngine _engine;

  bool _localUserJoined = false;
  int? _remoteUid;
  bool _muted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = false;
  bool _isScreenSharing = false;

  Timer? _timer;
  int _seconds = 0;
  String _callStatusText = "جارِ الاتصال...";
  StreamSubscription<DocumentSnapshot>? _callSubscription;

  @override
  void initState() {
    super.initState();
    _isCameraOff = !widget.call.isVideo;
    _isSpeakerOn = widget.call.isVideo;

    _initAgora();
    _listenToCallStatus();
  }

  void _listenToCallStatus() {
    _callSubscription = CallService.getCallStream(widget.call.callerId).listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        final status = data['callStatus'] ?? 'calling';

        if (mounted) {
          setState(() {
            if (status == 'calling') {
              _callStatusText = "جارِ الاتصال...";
            } else if (status == 'ringing') {
              _callStatusText = "يـرن...";
            } else if (status == 'answered') {
              _callStatusText = "تم الرد";
              _startTimer();
            }
          });
        }
      } else {
        _endCall(remoteEnded: true);
      }
    });
  }

  void _startTimer() {
    if (_timer != null && _timer!.isActive) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _seconds++);
      }
    });
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _initAgora() async {
    _engine = createAgoraRtcEngine();
    await _engine.initialize(const RtcEngineContext(
      appId: AgoraConfig.appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          if (mounted) setState(() => _localUserJoined = true);
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          if (mounted) {
            setState(() {
              _remoteUid = remoteUid;
              _callStatusText = "متصل";
            });
            _startTimer();
          }
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          _endCall(remoteEnded: true);
        },
      ),
    );

    await _engine.enableAudio();
    if (widget.call.isVideo) {
      await _engine.enableVideo();
      await _engine.startPreview();
    }

    await _engine.setEnableSpeakerphone(_isSpeakerOn);

    await _engine.joinChannel(
      token: AgoraConfig.tempToken,
      channelId: widget.call.channelId,
      uid: 0,
      options: const ChannelMediaOptions(),
    );
  }

  Future<void> _endCall({bool remoteEnded = false}) async {
    _timer?.cancel();

    try {
      await _engine.leaveChannel();
      await _engine.release();
    } catch (e) {
      debugPrint("Error releasing Agora: $e");
    }

    if (!remoteEnded) {
      await CallService.endCall(
        callerId: widget.call.callerId,
        receiverId: widget.call.receiverId,
      );
    }

    // 🟢 استخدام CallOverlay بدلاً من Navigator.pop
    CallOverlay.dismiss();
  }

  Future<void> _toggleCamera() async {
    if (_isCameraOff) {
      await _engine.enableVideo();
      await _engine.startPreview();
      setState(() => _isCameraOff = false);
    } else {
      await _engine.disableVideo();
      setState(() => _isCameraOff = true);
    }
  }

  Future<void> _toggleScreenShare() async {
    if (_isScreenSharing) {
      await _engine.stopScreenCapture();
      setState(() => _isScreenSharing = false);
    } else {
      // 🛠️ تم التصحيح: استخدام startScreenCapture بدلاً من startScreenCaptureMobile
      await _engine.startScreenCapture(const ScreenCaptureParameters2());
      setState(() => _isScreenSharing = true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _callSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // 🛠️ تم التصحيح: استخدام onPopInvokedWithResult بدلاً من المنتهية صلاحيتها
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // 🟢 عند محاولة الرجوع، نقوم بتصغير المكالمة فقط
        CallOverlay.minimize();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(child: _remoteVideoOrAudioUI()),
            if (!_isCameraOff && _localUserJoined)
              Positioned(
                top: 50,
                right: 20,
                child: SizedBox(
                  width: 110,
                  height: 150,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _engine,
                        canvas: const VideoCanvas(uid: 0),
                      ),
                    ),
                  ),
                ),
              ),
            _buildToolbar(),
          ],
        ),
      ),
    );
  }

  Widget _remoteVideoOrAudioUI() {
    if (_remoteUid != null && !_isCameraOff && widget.call.isVideo) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: _engine,
          canvas: VideoCanvas(uid: _remoteUid),
          connection: RtcConnection(channelId: widget.call.channelId),
        ),
      );
    } else {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 70,
            backgroundImage: widget.call.receiverPic.isNotEmpty ? NetworkImage(widget.call.receiverPic) : null,
            backgroundColor: Colors.grey[800],
            child: widget.call.receiverPic.isEmpty ? const Icon(Icons.person, size: 70, color: Colors.white) : null,
          ),
          const SizedBox(height: 20),
          Text(
            widget.call.receiverName,
            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            _seconds > 0 ? _formatDuration(_seconds) : _callStatusText,
            style: TextStyle(
              color: _seconds > 0 ? const Color(0xFFFFD700) : Colors.white70,
              fontSize: 18,
              letterSpacing: 2,
            ),
          ),
        ],
      );
    }
  }

  Widget _buildToolbar() {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildCircleButton(
              icon: _muted ? Icons.mic_off : Icons.mic,
              color: _muted ? Colors.white : Colors.white24,
              iconColor: _muted ? Colors.black : Colors.white,
              onTap: () {
                setState(() => _muted = !_muted);
                _engine.muteLocalAudioStream(_muted);
              },
            ),
            const SizedBox(width: 15),
            _buildCircleButton(
              icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
              color: _isSpeakerOn ? Colors.white : Colors.white24,
              iconColor: _isSpeakerOn ? Colors.black : Colors.white,
              onTap: () {
                setState(() => _isSpeakerOn = !_isSpeakerOn);
                _engine.setEnableSpeakerphone(_isSpeakerOn);
              },
            ),
            const SizedBox(width: 15),
            _buildCircleButton(
              icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
              color: _isCameraOff ? Colors.white : Colors.white24,
              iconColor: _isCameraOff ? Colors.black : Colors.white,
              onTap: _toggleCamera,
            ),
            const SizedBox(width: 15),
            _buildCircleButton(
              icon: _isScreenSharing ? Icons.stop_screen_share : Icons.screen_share,
              color: _isScreenSharing ? const Color(0xFFFFD700) : Colors.white24,
              iconColor: _isScreenSharing ? Colors.black : Colors.white,
              onTap: _toggleScreenShare,
            ),
            const SizedBox(width: 15),
            _buildCircleButton(
              icon: Icons.call_end,
              color: Colors.redAccent,
              iconSize: 32,
              padding: 16,
              onTap: () => _endCall(remoteEnded: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color color,
    Color iconColor = Colors.white,
    required VoidCallback onTap,
    double iconSize = 25,
    double padding = 12,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: Icon(icon, color: iconColor, size: iconSize),
      ),
    );
  }
}