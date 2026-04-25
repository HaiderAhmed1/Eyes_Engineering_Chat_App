import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

// --- استيراد الخدمات والويدجت ---
import 'package:chat_app/services/audio_recorder_service.dart';
import 'package:chat_app/services/chat_features.dart';
import 'package:chat_app/services/chat_service.dart'; // الخدمة الشاملة
import 'package:chat_app/widgets/chat_input_bar.dart';
import 'package:chat_app/widgets/chat_message_list.dart';
import 'package:chat_app/screens/group_info_screen.dart';
import 'package:chat_app/screens/private_chat_screen.dart'; // لاستخدام MessageReply

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  // --- Firebase ---
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  late DocumentReference<Map<String, dynamic>> _groupDocRef;
  late CollectionReference _messagesCollection;

  // 💡 التعديل هنا: إضافة متغير لتثبيت الـ Stream
  late Stream<QuerySnapshot> _messagesStream;

  late String _currentUserId;

  // --- Services & Controllers ---
  final AudioRecorderService _audioRecorderService = AudioRecorderService();
  final ScrollController _scrollController = ScrollController();

  // --- State Variables ---
  bool _isUploading = false;
  MessageReply? _replyingToMessage;
  String? _draftText;

  String? _playingMessageId;

  Timer? _typingTimer;

  // اللون الذهبي
  final Color _goldColor = const Color(0xFFFFD700);

  @override
  void initState() {
    super.initState();
    _currentUserId = _auth.currentUser!.uid;
    _groupDocRef = _firestore.collection('groups').doc(widget.groupId);
    _messagesCollection = _groupDocRef.collection('messages');

    // 💡 التعديل هنا: تهيئة الـ Stream مرة واحدة فقط
    _messagesStream = _messagesCollection.orderBy('timestamp', descending: true).snapshots();

    _initAudioService();
    _updateGroupReadStatus();
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

  void _updateGroupReadStatus() {
    // تحديث آخر قراءة للمستخدم في وثيقة المجموعة (لتتبع القراءة الجماعية)
    _groupDocRef.update({
      'members.$_currentUserId.lastRead': DateTime.now().millisecondsSinceEpoch,
    }).catchError((e) {});

    // تصفير العداد في قائمتي
    _firestore.collection('users').doc(_currentUserId).collection('my_groups').doc(widget.groupId).update({
      'unreadCount': 0,
    }).catchError((e) {});
  }

  @override
  void dispose() {
    _audioRecorderService.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _updateTypingStatus(false); // التأكد من إيقاف حالة الكتابة
    super.dispose();
  }

  // --- Helper Methods ---

  void _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final replyData = _replyingToMessage != null
        ? {
      'message': _replyingToMessage!.message,
      'senderName': _replyingToMessage!.senderName,
      'isMe': _replyingToMessage!.isMe,
    }
        : null;

    await ChatService.sendGroupDatabaseMessage(
      messagesCollection: _messagesCollection,
      groupDocRef: _groupDocRef,
      currentUserId: _currentUserId,
      text: text,
      type: 'text',
      fileUrl: null,
      fileName: null,
      replyData: replyData,
    );

    _clearReply();
    _updateTypingStatus(false);
  }

  Future<void> _sendAudioMessage(int durationInSeconds) async {
    await _audioRecorderService.stopRecording();
    final path = _audioRecorderService.recordedFilePath;
    final rawWaveform = _audioRecorderService.waveformData;
    final waveform = _downsample(rawWaveform, 50); // تقليل حجم البيانات

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

  Future<bool> _uploadFile(File file, String type, {String? fileName, int? duration, List<double>? waveform}) async {
    setState(() => _isUploading = true);
    bool success = false;
    try {
      Map<String, dynamic>? extraFields;
      if (waveform != null) {
        extraFields = {'waveform': waveform};
      } else {
        extraFields = {};
      }

      if (type == 'video') {
        extraFields.addAll({
          'isMubashara': true,
          'senderPhone': '',
        });

        try {
          final userDoc = await _firestore.collection('users').doc(_currentUserId).get();
          if (userDoc.exists) {
            extraFields['senderPhone'] = userDoc.data()?['phoneNumber'] ?? '';
          }
        } catch (e) {
          // Ignore
        }
      }

      // 1. الرفع
      final storagePath = 'group_files/${widget.groupId}/${type}s'; // مسار منظم
      final fileUrl = await ChatService.uploadFile(file, storagePath);

      // 2. الإرسال
      final replyData = _replyingToMessage != null
          ? {
        'message': _replyingToMessage!.message,
        'senderName': _replyingToMessage!.senderName,
        'isMe': _replyingToMessage!.isMe,
      } : null;

      await ChatService.sendGroupDatabaseMessage(
        messagesCollection: _messagesCollection,
        groupDocRef: _groupDocRef,
        currentUserId: _currentUserId,
        text: '', // نص فارغ للمرفقات
        type: type,
        fileUrl: fileUrl,
        fileName: fileName,
        replyData: replyData,
        extraFields: extraFields,
      );

      _clearReply();
      success = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الإرسال: $e'), backgroundColor: Colors.red));
      }
      success = false;
    } finally {
      if (mounted) setState(() => _isUploading = false);
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

  void _clearReply() => setState(() => _replyingToMessage = null);

  void _onTyping() {
    _updateTypingStatus(true);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () => _updateTypingStatus(false));
  }

  void _updateTypingStatus(bool isTyping) {
    ChatService.setGroupTypingStatus(
      groupDocRef: _groupDocRef,
      currentUserId: _currentUserId,
      isTyping: isTyping,
    );
  }

  void _openGroupInfo() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => GroupInfoScreen(
          groupId: widget.groupId,
          groupName: widget.groupName,
        ),
      ),
    );
  }

  void _showGroupOptions() {
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
              leading: const Icon(Icons.info_outline),
              title: const Text('معلومات المجموعة'),
              onTap: () {
                Navigator.pop(ctx);
                _openGroupInfo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: const Text('تثبيت المجموعة'),
              onTap: () {
                Navigator.pop(ctx);
                ChatService.togglePin(uid: _currentUserId, targetId: widget.groupId, isGroup: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('أرشفة المجموعة'),
              onTap: () {
                Navigator.pop(ctx);
                ChatService.toggleArchive(uid: _currentUserId, targetId: widget.groupId, isGroup: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: const Text('كتم الإشعارات'),
              onTap: () {
                Navigator.pop(ctx);
                ChatService.toggleMute(uid: _currentUserId, targetId: widget.groupId, isGroup: true);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: Colors.red),
              title: const Text('مغادرة المجموعة', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                bool confirm = await showDialog(context: context, builder: (c) => AlertDialog(
                  title: const Text('مغادرة المجموعة'),
                  content: const Text('هل أنت متأكد أنك تريد المغادرة؟'),
                  actions: [
                    TextButton(onPressed: ()=>Navigator.pop(c,false), child: const Text('إلغاء')),
                    TextButton(onPressed: ()=>Navigator.pop(c,true), child: const Text('مغادرة', style: TextStyle(color: Colors.red))),
                  ],
                )) ?? false;

                if(confirm) {
                  await ChatService.removeGroupMember(widget.groupId, _currentUserId);
                  if(mounted) {
                    Navigator.pop(context); // العودة للقائمة الرئيسية
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

    return StreamBuilder<DocumentSnapshot>(
      stream: _groupDocRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && !snapshot.data!.exists) {
          return const Scaffold(body: Center(child: Text("هذه المجموعة لم تعد موجودة")));
        }

        String currentGroupName = widget.groupName;
        String? groupImage;
        Map<String, dynamic>? groupData;

        if (snapshot.hasData && snapshot.data!.data() != null) {
          groupData = snapshot.data!.data() as Map<String, dynamic>;
          final info = groupData['info'] as Map<String, dynamic>?;
          currentGroupName = info?['name'] ?? widget.groupName;
          groupImage = info?['imageUrl'];
        }

        final String groupType = groupData != null && groupData['info'] != null ? (groupData['info']['type'] ?? '') : '';
        final bool isMubasharaGroup = groupType == 'mubashara';

        return Scaffold(
          appBar: AppBar(
            backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.9),
            elevation: 0,
            scrolledUnderElevation: 2,
            titleSpacing: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: InkWell(
              onTap: _openGroupInfo,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    backgroundImage: groupImage != null ? NetworkImage(groupImage) : null,
                    child: groupImage == null ? const Icon(Icons.groups, color: Colors.white, size: 20) : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(currentGroupName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        if (groupData != null && groupData['members'] != null)
                          Text(
                            "${(groupData['members'] as Map).length} أعضاء",
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: _showGroupOptions,
              ),
            ],
          ),
          body: Container(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
            ),
            child: Column(
              children: [
                if (_isUploading)
                  LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(_goldColor),
                    minHeight: 2,
                  ),

                Expanded(
                  child: ChatMessageList(
                    // 💡 التعديل هنا: استخدام المتغير الثابت بدلاً من استدعاء snapshots() مباشرة
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

                if (groupData != null && groupData['typingUsers'] != null)
                  Builder(builder: (ctx) {
                    final typingList = List.from(groupData!['typingUsers'] ?? []);
                    typingList.remove(_currentUserId);

                    if (typingList.isNotEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(left: 20, bottom: 5),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            typingList.length == 1
                                ? 'عضو يكتب...'
                                : '${typingList.length} أعضاء يكتبون...',
                            style: TextStyle(color: theme.colorScheme.primary, fontSize: 12, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }),

                ChatInputBar(
                  audioRecorderService: _audioRecorderService,
                  isUploading: _isUploading,
                  replyingToMessage: _replyingToMessage,
                  draftText: _draftText,
                  onCancelReply: _clearReply,
                  onSendMessage: (text) {
                    _sendMessage(text);
                    setState(() => _draftText = null);
                  },
                  onSendAudio: _sendAudioMessage,
                  onSendFile: isMubasharaGroup
                      ? () {}
                      : _showAttachmentMenu,
                  onTyping: _onTyping,
                  onDraftChanged: (text) => _draftText = text,
                  isMubasharaMode: isMubasharaGroup,
                  onMubasharaAction: (isCamera) async {
                    final picker = ImagePicker();
                    final XFile? pickedFile = await picker.pickVideo(
                      source: isCamera ? ImageSource.camera : ImageSource.gallery,
                    );
                    if (pickedFile != null) {
                      _uploadFile(File(pickedFile.path), 'video');
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}