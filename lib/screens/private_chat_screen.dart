import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:io';

// --- استيراد الشاشات والخدمات والويدجت ---
import 'package:chat_app/screens/profile_screen.dart';
import 'package:chat_app/services/audio_recorder_service.dart';
import 'package:chat_app/services/chat_features.dart';
import 'package:chat_app/services/chat_sender.dart';
import 'package:chat_app/services/chat_service.dart'; // الخدمة الشاملة
import 'package:chat_app/widgets/chat_input_bar.dart';
import 'package:chat_app/widgets/chat_message_list.dart';

// --- استيراد خدمات وشاشات الاتصال الجديدة ---
import 'package:chat_app/services/call_service.dart';
import 'package:chat_app/widgets/call_overlay.dart'; // 🟢 [تم التحديث]: استيراد نظام الطبقة العائمة

class MessageReply {
  final String message;
  final String senderName;
  final bool isMe;

  MessageReply({required this.message, required this.senderName, required this.isMe});
}

class PrivateChatScreen extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;
  final String chatId;

  const PrivateChatScreen({
    super.key,
    required this.targetUserId,
    required this.targetUserName,
    required this.chatId,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  late DocumentReference<Map<String, dynamic>> _chatDocRef;
  late CollectionReference _messagesCollection;

  late Stream<QuerySnapshot> _messagesStream;

  late String _currentUserId;
  late DocumentReference<Map<String, dynamic>> _myUserDocRef;
  late DocumentReference<Map<String, dynamic>> _targetUserChatDocRef;

  final AudioRecorderService _audioRecorderService = AudioRecorderService();
  final ScrollController _scrollController = ScrollController();

  double? _uploadProgress;

  MessageReply? _replyingToMessage;
  String? _draftText;

  String? _playingMessageId;
  Timer? _typingTimer;
  bool _isOtherTyping = false;

  String? _myUserName;
  String? _myUserImage;
  String? _targetUserImage;

  final Color _goldColor = const Color(0xFFFFD700);

  @override
  void initState() {
    super.initState();
    _currentUserId = _auth.currentUser!.uid;
    _myUserDocRef = _firestore.collection('users').doc(_currentUserId);

    _chatDocRef = _firestore.collection('chats').doc(widget.chatId);
    _messagesCollection = _chatDocRef.collection('messages');

    _messagesStream = _messagesCollection.orderBy('timestamp', descending: true).snapshots();

    _targetUserChatDocRef = _firestore.collection('users').doc(widget.targetUserId).collection('my_chats').doc(_currentUserId);

    _fetchUserInfos();
    _initAudioService();
    _markMessagesAsRead();
    _listenToTypingStatus();
  }

  Future<void> _fetchUserInfos() async {
    final myDoc = await _myUserDocRef.get();
    final targetDoc = await _firestore.collection('users').doc(widget.targetUserId).get();

    if (mounted) {
      setState(() {
        _myUserName = myDoc.data()?['name'] ?? 'مستخدم';
        _myUserImage = myDoc.data()?['imageUrl'];
        _targetUserImage = targetDoc.data()?['imageUrl'];
      });
    }
  }

  Future<void> _initAudioService() async {
    await _audioRecorderService.init();
    _audioRecorderService.addListener(() {
      if (mounted) {
        setState(() {
          if (_audioRecorderService.recordingState == RecordingState.stopped) {
            _playingMessageId = null;
          }
        });
      }
    });
  }

  void _markMessagesAsRead() {
    ChatService.markPrivateMessagesAsRead(
      messagesCollection: _messagesCollection,
      myChatListDoc: _myUserDocRef.collection('my_chats').doc(widget.targetUserId),
      currentUserId: _currentUserId,
    );
  }

  void _listenToTypingStatus() {
    final myChatWithTargetRef = _myUserDocRef.collection('my_chats').doc(widget.targetUserId);
    myChatWithTargetRef.snapshots().listen((snapshot) {
      if (snapshot.exists && mounted) {
        setState(() {
          _isOtherTyping = snapshot.data()?['isTyping'] ?? false;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioRecorderService.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _updateTypingStatus(false);
    super.dispose();
  }

  // 🟢 [تم التحديث]: دالة بدء المكالمة تستخدم CallOverlay بدلاً من Navigator
  void _startCall({required bool isVideo}) async {
    String channelId = 'call_${DateTime.now().millisecondsSinceEpoch}';

    Call call = Call(
      callerId: _currentUserId,
      callerName: _myUserName ?? 'مستخدم',
      callerPic: _myUserImage ?? '',
      receiverId: widget.targetUserId,
      receiverName: widget.targetUserName,
      receiverPic: _targetUserImage ?? '',
      channelId: channelId,
      hasDialled: true,
      isVideo: isVideo,
    );

    bool callMade = await CallService.makeCall(call);

    if (callMade && mounted) {
      // فتح شاشة الاتصال في طبقة عائمة لتفعيل ميزة "تصغير المكالمة"
      CallOverlay.show(context, call);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر بدء المكالمة، يرجى المحاولة لاحقاً.')),
        );
      }
    }
  }

  void _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final replyData = _replyingToMessage != null
        ? {
      'message': _replyingToMessage!.message,
      'senderName': _replyingToMessage!.senderName,
      'isMe': _replyingToMessage!.isMe,
    } : null;

    await ChatSender.sendTextMessage(
      chatDocRef: _chatDocRef,
      text: text,
      senderId: _currentUserId,
      senderName: _myUserName ?? 'مستخدم',
      senderImage: _myUserImage,
      replyTo: replyData,
    );

    if (_myUserName != null) {
      await ChatSender.updateChatList(
        myId: _currentUserId,
        targetId: widget.targetUserId,
        lastMessage: text,
        myName: _myUserName!,
        targetName: widget.targetUserName,
        myImage: _myUserImage,
        targetImage: _targetUserImage,
        chatId: widget.chatId,
        isGroup: false,
      );
    }

    _clearReply();
    _updateTypingStatus(false);
  }

  List<double> _downsample(List<double> data, int targetCount) {
    if (data.isEmpty) return [];
    if (data.length <= targetCount) return data;
    final step = data.length / targetCount;
    final result = <double>[];
    for (var i = 0; i < targetCount; i++) {
      final index = (i * step).floor();
      if (index < data.length) {
        result.add(data[index]);
      }
    }
    return result;
  }

  Future<void> _sendAudioMessage(int durationInSeconds) async {
    await _audioRecorderService.stopRecording();
    final path = _audioRecorderService.recordedFilePath;
    final rawWaveform = _audioRecorderService.waveformData;
    final waveform = _downsample(rawWaveform, 50);

    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        bool success = await _uploadFile(file, 'audio', duration: durationInSeconds * 1000, waveform: waveform);
        if (success) {
          await _audioRecorderService.cancelRecording();
        }
      }
    }
  }

  Future<bool> _uploadFile(File file, String type, {String? fileName, int? duration, List<double>? waveform}) async {
    setState(() => _uploadProgress = 0.0);
    bool success = false;
    try {
      Map<String, dynamic>? extraFields;
      if (waveform != null) {
        extraFields = {'waveform': waveform};
      }

      await ChatSender.sendFileMessage(
        chatDocRef: _chatDocRef,
        file: file,
        type: type,
        senderId: _currentUserId,
        senderName: _myUserName ?? '',
        senderImage: _myUserImage,
        fileName: fileName,
        duration: duration,
        extraFields: extraFields,
        replyTo: _replyingToMessage != null ? {
          'message': _replyingToMessage!.message,
          'senderName': _replyingToMessage!.senderName,
          'isMe': _replyingToMessage!.isMe,
        } : null,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _uploadProgress = progress;
            });
          }
        },
      );
      _clearReply();

      String msgText = type == 'image' ? '📷 صورة'
          : type == 'video' ? '🎥 فيديو'
          : type == 'audio' ? '🎤 صوت'
          : '📎 ملف';

      if (_myUserName != null) {
        await ChatSender.updateChatList(
          myId: _currentUserId,
          targetId: widget.targetUserId,
          lastMessage: msgText,
          myName: _myUserName!,
          targetName: widget.targetUserName,
          myImage: _myUserImage,
          targetImage: _targetUserImage,
          chatId: widget.chatId,
          isGroup: false,
        );
      }

      success = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الإرسال: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
      success = false;
    } finally {
      if (mounted) setState(() => _uploadProgress = null);
    }
    return success;
  }

  void _showAttachmentMenu() {
    ChatFeatures.showAttachmentMenu(
      context,
      onImagePicked: (file) => _uploadFile(file, 'image'),
      onVideoPicked: (file) => _uploadFile(file, 'video'),
      onFilePicked: (platformFile) {
        if (platformFile.path != null) {
          _uploadFile(File(platformFile.path!), 'file', fileName: platformFile.name);
        }
      },
    );
  }

  void _handleReply(String message, String senderName, bool isMe) {
    setState(() {
      _replyingToMessage = MessageReply(
        message: message,
        senderName: senderName,
        isMe: isMe,
      );
    });
  }

  void _clearReply() {
    setState(() {
      _replyingToMessage = null;
    });
  }

  void _onTyping() {
    _updateTypingStatus(true);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _updateTypingStatus(false);
    });
  }

  void _updateTypingStatus(bool isTyping) {
    ChatService.setPrivateTypingStatus(
      recipientChatListDoc: _targetUserChatDocRef,
      isTyping: isTyping,
    );
  }

  String _getLastSeenText(String? lastSeenIso) {
    if (lastSeenIso == null) return 'غير متصل';
    try {
      final lastSeen = DateTime.parse(lastSeenIso);
      final diff = DateTime.now().difference(lastSeen);
      if (diff.inMinutes < 1) return 'نشط قبل لحظات';
      if (diff.inMinutes < 60) return 'نشط قبل ${diff.inMinutes} د';
      if (diff.inHours < 24) return 'نشط قبل ${diff.inHours} س';
      return 'نشط منذ فترة';
    } catch (e) {
      return 'غير متصل';
    }
  }

  void _showExpandedProfile() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _goldColor, width: 2),
                image: DecorationImage(
                  image: _targetUserImage != null ? NetworkImage(_targetUserImage!) : const AssetImage('assets/placeholder.png') as ImageProvider,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    icon: const Icon(Icons.person),
                    label: const Text('الملف الشخصي'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: widget.targetUserId)));
                    }
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  void _showChatOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: const Text('تثبيت المحادثة'),
              onTap: () {
                Navigator.pop(ctx);
                ChatService.togglePin(uid: _currentUserId, targetId: widget.targetUserId, isGroup: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('أرشفة المحادثة'),
              onTap: () {
                Navigator.pop(ctx);
                ChatService.toggleArchive(uid: _currentUserId, targetId: widget.targetUserId, isGroup: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: const Text('كتم الإشعارات'),
              onTap: () {
                Navigator.pop(ctx);
                ChatService.toggleMute(uid: _currentUserId, targetId: widget.targetUserId, isGroup: false);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: const Text('حظر المستخدم', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                bool confirm = await showDialog(context: context, builder: (c) => AlertDialog(
                  title: const Text('تأكيد الحظر'),
                  content: const Text('هل أنت متأكد؟ لن تستلم رسائل من هذا المستخدم.'),
                  actions: [
                    TextButton(onPressed: ()=>Navigator.pop(c,false), child: const Text('إلغاء')),
                    TextButton(onPressed: ()=>Navigator.pop(c,true), child: const Text('حظر', style: TextStyle(color: Colors.red))),
                  ],
                )) ?? false;

                if(confirm) {
                  await ChatService.blockUser(_currentUserId, widget.targetUserId);
                  if(mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حظر المستخدم")));
                    Navigator.pop(context);
                  }
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.9),
        elevation: 0,
        scrolledUnderElevation: 4,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileScreen(userId: widget.targetUserId),
              ),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              children: [
                StreamBuilder<DocumentSnapshot>(
                  stream: _firestore.collection('users').doc(widget.targetUserId).snapshots(),
                  builder: (context, snapshot) {
                    var imageUrl = '';
                    bool isOnline = false;
                    if (snapshot.hasData && snapshot.data!.exists) {
                      imageUrl = snapshot.data!.get('imageUrl') ?? '';
                      isOnline = snapshot.data!.get('isOnline') ?? false;

                      if (imageUrl != _targetUserImage && mounted) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _targetUserImage = imageUrl);
                        });
                      }
                    }

                    return GestureDetector(
                      onTap: _showExpandedProfile,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                            child: imageUrl.isEmpty
                                ? Text(
                                widget.targetUserName.isNotEmpty ? widget.targetUserName[0].toUpperCase() : '?',
                                style: const TextStyle(fontWeight: FontWeight.bold)
                            ) : null,
                          ),
                          if (isOnline)
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: theme.colorScheme.surface, width: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.targetUserName.isNotEmpty ? widget.targetUserName : 'مستخدم',
                        style: theme.textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_isOtherTyping)
                        Text(
                          'يكتب الآن...',
                          style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              fontStyle: FontStyle.italic
                          ),
                        )
                      else
                        StreamBuilder<DocumentSnapshot>(
                          stream: _firestore.collection('users').doc(widget.targetUserId).snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data!.exists && snapshot.data!.data() != null) {
                              final data = snapshot.data!.data() as Map<String, dynamic>;
                              final bool isOnline = data['isOnline'] ?? false;
                              final String? lastSeen = data['lastSeen'];

                              return Text(
                                isOnline ? 'متصل الآن' : _getLastSeenText(lastSeen),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isOnline ? Colors.greenAccent : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () => _startCall(isVideo: true),
          ),
          IconButton(
            icon: const Icon(Icons.call_outlined),
            onPressed: () => _startCall(isVideo: false),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showChatOptions,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
        ),
        child: Column(
          children: [
            if (_uploadProgress != null)
              Container(
                color: theme.colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.cloud_upload_rounded, color: _goldColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("جاري الرفع...", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              Text("${(_uploadProgress! * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: _uploadProgress,
                            backgroundColor: theme.colorScheme.surface,
                            valueColor: AlwaysStoppedAnimation<Color>(_goldColor),
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),

            Expanded(
              child: ChatMessageList(
                messagesStream: _messagesStream,
                currentUserId: _currentUserId,
                scrollController: _scrollController,
                audioRecorderService: _audioRecorderService,
                playingMessageId: _playingMessageId,
                onPlayAudio: (path, messageId) async {
                  if (_playingMessageId != messageId) {
                    await _audioRecorderService.stopPlaying();
                    if (mounted) {
                      setState(() {
                        _playingMessageId = messageId;
                      });
                    }
                    await _audioRecorderService.startPlaying(filePath: path);
                  } else {
                    await _audioRecorderService.startPlaying(filePath: path);
                  }
                },
                onStopAudio: () async {
                  await _audioRecorderService.stopPlaying();
                },
                onReply: _handleReply,
              ),
            ),

            ChatInputBar(
              audioRecorderService: _audioRecorderService,
              isUploading: _uploadProgress != null,
              replyingToMessage: _replyingToMessage,
              draftText: _draftText,
              onCancelReply: _clearReply,
              onSendMessage: (text) {
                _sendMessage(text);
                setState(() => _draftText = null);
              },
              onSendAudio: _sendAudioMessage,
              onSendFile: _showAttachmentMenu,
              onTyping: _onTyping,
              onDraftChanged: (text) {
                _draftText = text;
              },
            ),
          ],
        ),
      ),
    );
  }
}