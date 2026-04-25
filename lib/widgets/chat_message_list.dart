import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:chat_app/services/audio_recorder_service.dart';
import 'package:chat_app/services/chat_features.dart';
import 'package:chat_app/services/chat_service.dart'; // استيراد الخدمة للوصول إلى التفاعلات
import 'dart:ui'; // For ImageFilter

class ChatMessageList extends StatefulWidget {
  final Stream<QuerySnapshot> messagesStream;
  final String currentUserId;
  final ScrollController scrollController;
  final AudioRecorderService audioRecorderService;

  final String? playingMessageId;

  final Function(String path, String messageId) onPlayAudio;

  final VoidCallback onStopAudio;
  final Function(String message, String senderName, bool isMe) onReply;

  const ChatMessageList({
    super.key,
    required this.messagesStream,
    required this.currentUserId,
    required this.scrollController,
    required this.audioRecorderService,
    required this.playingMessageId,
    required this.onPlayAudio,
    required this.onStopAudio,
    required this.onReply,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (widget.scrollController.hasClients) {
      // إظهار الزر إذا صعد المستخدم للأعلى بأكثر من 400 بيكسل
      final show = widget.scrollController.offset > 400;
      if (show != _showScrollToBottom) {
        setState(() {
          _showScrollToBottom = show;
        });
      }
    }
  }

  void _scrollToBottom() {
    if (widget.scrollController.hasClients) {
      widget.scrollController.animateTo(
        0, // في القائمة المعكوسة، 0 هو الأسفل
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutQuart,
      );
    }
  }

  int _getTimestampInMilliseconds(dynamic timestamp) {
    if (timestamp == null) return DateTime.now().millisecondsSinceEpoch;
    if (timestamp is Timestamp) {
      return timestamp.millisecondsSinceEpoch;
    } else if (timestamp is int) {
      return timestamp;
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Stack(
      children: [
        // --- قائمة الرسائل ---
        StreamBuilder<QuerySnapshot>(
          stream: widget.messagesStream,
          builder: (context, snapshot) {
            // 💡 التعديل الأهم هنا: إضافة !snapshot.hasData لمنع الرمشة (Flickering)
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyState(theme);
            }

            final docs = snapshot.data!.docs;

            return ListView.builder(
              controller: widget.scrollController,
              reverse: true, // لتبدأ الرسائل من الأسفل إلى الأعلى
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final String messageId = docs[index].id;
                final bool isMe = data['senderId'] == widget.currentUserId;

                final currentMsgTime = _getTimestampInMilliseconds(data['timestamp']);

                // منطق فواصل التاريخ
                bool showDateHeader = false;
                if (index < docs.length - 1) {
                  final nextData = docs[index + 1].data() as Map<String, dynamic>;
                  final nextMsgTime = _getTimestampInMilliseconds(nextData['timestamp']);
                  showDateHeader = !ChatFeatures.isSameDay(currentMsgTime, nextMsgTime);
                } else {
                  showDateHeader = true; // أقدم رسالة (في الأعلى)
                }

                // منطق تجميع الرسائل (Message Grouping)
                bool isSameSenderAsPrevious = false;
                if (index < docs.length - 1) {
                  final nextData = docs[index + 1].data() as Map<String, dynamic>;
                  if (nextData['senderId'] == data['senderId']) {
                    isSameSenderAsPrevious = true;
                  }
                }

                // المسافة العلوية (بين الرسالة الحالية والرسالة الأقدم منها)
                double topSpacing = (isSameSenderAsPrevious && !showDateHeader) ? 2.0 : 12.0;

                return Column(
                  children: [
                    // فاصل التاريخ الزجاجي (يظهر فوق الرسائل لليوم الجديد)
                    if (showDateHeader)
                      _buildGlassDateHeader(theme, currentMsgTime, isDark),

                    Padding(
                      padding: EdgeInsets.only(top: topSpacing),
                      child: Dismissible(
                        key: Key(messageId),
                        direction: DismissDirection.startToEnd,
                        background: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 24),
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.reply_rounded, color: theme.colorScheme.onPrimaryContainer),
                          ),
                        ),
                        confirmDismiss: (direction) async {
                          widget.onReply(
                              data['text'] ?? (data['type'] == 'audio' ? 'رسالة صوتية' : 'مرفق'),
                              data['senderName'] ?? '',
                              isMe
                          );
                          // إرجاع false حتى لا يتم حذف الرسالة من الواجهة بعد السحب (نحن نستخدم السحب للرد فقط)
                          return false;
                        },
                        child: MessageBubble(
                          messageId: messageId,
                          text: data['text'] ?? '',
                          fileUrl: data['fileUrl'],
                          fileName: data['fileName'],
                          type: data['type'] ?? 'text',
                          isMe: isMe,
                          senderId: data['senderId'],
                          senderName: data['senderName'],
                          senderImageUrl: data['senderImage'],
                          replyTo: data['replyTo'],
                          status: data['status'] ?? 'sent',
                          isRead: data['isRead'] ?? false,
                          isEdited: data['isEdited'] ?? false,
                          isForwarded: data['isForwarded'] ?? false,
                          reactions: data['reactions'],
                          timestamp: data['timestamp'],

                          duration: data['duration'],
                          waveform: data['waveform'],

                          audioRecorderService: widget.audioRecorderService,
                          isPlayingAudio: widget.playingMessageId == messageId,
                          onPlayAudio: () {
                            if (data['fileUrl'] != null) {
                              widget.onPlayAudio(data['fileUrl'], messageId);
                            }
                          },
                          onStopAudio: widget.onStopAudio,

                          // إضافة منطق التفاعل (Reactions)
                          onReactionSelected: (emoji) {
                            ChatService.updateMessageReaction(
                              messageDocRef: docs[index].reference,
                              currentUserId: widget.currentUserId,
                              reactionEmoji: emoji,
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),

        // --- زر النزول للأسفل (Scroll to Bottom) ---
        Positioned(
          right: 20,
          bottom: 20,
          child: AnimatedScale(
            scale: _showScrollToBottom ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: FloatingActionButton.small(
              onPressed: _scrollToBottom,
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              elevation: 4,
              child: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          ),
        ),
      ],
    );
  }

  // --- تصميم فاصل التاريخ الزجاجي (Legendary Glass Header) ---
  Widget _buildGlassDateHeader(ThemeData theme, int timestamp, bool isDark) {
    final dateStr = ChatFeatures.formatDateHeader(DateTime.fromMillisecondsSinceEpoch(timestamp));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    spreadRadius: 1,
                  )
                ],
              ),
              child: Text(
                dateStr,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- تصميم الحالة الفارغة (Legendary Empty State) ---
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "لا توجد رسائل بعد",
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "ابدأ المحادثة بإرسال رسالة ترحيب! 👋",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}