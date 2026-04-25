import 'dart:async';
import 'package:flutter/material.dart';
import 'package:chat_app/services/audio_recorder_service.dart';
import 'package:chat_app/screens/private_chat_screen.dart';
import 'package:chat_app/widgets/chat_audio_recorder.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'dart:math' as math;

class ChatInputBar extends StatefulWidget {
  final AudioRecorderService audioRecorderService;
  final bool isUploading;
  final MessageReply? replyingToMessage;
  final String? draftText;

  final VoidCallback onCancelReply;
  final Function(String) onSendMessage;
  
  final Future<void> Function(int durationInSeconds) onSendAudio;
  
  final VoidCallback onSendFile;
  final VoidCallback onTyping;
  final Function(String) onDraftChanged;

  final bool isMubasharaMode;
  final Function(bool isCamera)? onMubasharaAction;

  const ChatInputBar({
    super.key,
    required this.audioRecorderService,
    required this.isUploading,
    this.replyingToMessage,
    this.draftText,
    required this.onCancelReply,
    required this.onSendMessage,
    required this.onSendAudio,
    required this.onSendFile,
    required this.onTyping,
    required this.onDraftChanged,
    this.isMubasharaMode = false,
    this.onMubasharaAction,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> with SingleTickerProviderStateMixin {
  late TextEditingController _messageController;
  late AnimationController _sendButtonController;
  late Animation<double> _sendButtonScale;

  bool _showSendButton = false;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(text: widget.draftText ?? '');
    _showSendButton = _messageController.text.trim().isNotEmpty;

    _messageController.addListener(_onTextChanged);
    widget.audioRecorderService.addListener(_onRecorderStateChanged);

    _sendButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _sendButtonScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _sendButtonController, curve: Curves.easeOutBack),
    );

    if (_showSendButton) {
      _sendButtonController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    widget.audioRecorderService.removeListener(_onRecorderStateChanged);
    _messageController.dispose();
    _sendButtonController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    widget.onTyping();
    widget.onDraftChanged(_messageController.text);
    
    final shouldShowSend = _messageController.text.trim().isNotEmpty;
    if (shouldShowSend != _showSendButton) {
      setState(() {
        _showSendButton = shouldShowSend;
      });
      if (shouldShowSend) {
        _sendButtonController.forward();
      } else {
        _sendButtonController.reverse();
      }
    }
  }

  void _onRecorderStateChanged() {
    if (mounted) setState(() {});
  }

  void _sendTextMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    widget.onSendMessage(text);
    _messageController.clear();
    _onTextChanged(); 
  }

  void _showMubasharaOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true, // إضافة هذه الخاصية لتحسين العرض
      builder: (BuildContext ctx) {
        return SingleChildScrollView( // إضافة التمرير لتجنب الخطأ في الشاشات الصغيرة
          child: Container(
            padding: const EdgeInsets.all(24),
            // حذفنا height: 220 وجعلناه يعتمد على المحتوى
            child: Column(
              mainAxisSize: MainAxisSize.min, // جعل العمود يأخذ أقل مساحة ممكنة
              children: [
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2)
                  ),
                ),
                Text(
                  'اختر نوع الإرسال',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildOptionButton(
                        context,
                        icon: Icons.videocam_rounded,
                        color: Colors.redAccent,
                        label: 'تصوير مباشرة',
                        onTap: () {
                          Navigator.pop(ctx);
                          widget.onMubasharaAction?.call(true);
                        }
                    ),
                    _buildOptionButton(
                        context,
                        icon: Icons.video_library_rounded,
                        color: Colors.blueAccent,
                        label: 'رفع فيديو',
                        onTap: () {
                          Navigator.pop(ctx);
                          widget.onMubasharaAction?.call(false);
                        }
                    ),
                  ],
                ),
                const SizedBox(height: 20), // مسافة أمان في الأسفل
              ],
            ),
          ),
        );
      },
    );
  }
  Widget _buildOptionButton(BuildContext context, {required IconData icon, required Color color, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recordingState = widget.audioRecorderService.recordingState;

    // --- 1. حالة التسجيل ---
    if (recordingState == RecordingState.recording && !widget.isMubasharaMode) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 12, left: 12, right: 12, top: 12),
        child: ChatAudioRecorder(
          audioRecorderService: widget.audioRecorderService,
          onCancel: () {
            widget.audioRecorderService.cancelRecording();
          },
          onSend: (duration) async {
            await widget.onSendAudio(duration);
          },
        ),
      );
    }

    // --- 2. حالة المعاينة (Preview) ---
    if (widget.audioRecorderService.recordedFilePath != null &&
        (recordingState == RecordingState.stopped || recordingState == RecordingState.playing) && !widget.isMubasharaMode) {

      final isPlaying = recordingState == RecordingState.playing;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0)
            .copyWith(bottom: MediaQuery.of(context).padding.bottom + 12.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5, offset: const Offset(0, -2))],
        ),
        child: Row(
          children: [
            // زر الحذف
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 28),
              onPressed: () {
                widget.audioRecorderService.cancelRecording();
              },
            ),
            // زر التشغيل/الإيقاف
            GestureDetector(
              onTap: () {
                if (isPlaying) {
                  widget.audioRecorderService.stopPlaying();
                } else {
                  widget.audioRecorderService.startPlaying();
                }
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
                ),
                child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28, color: theme.colorScheme.primary),
              ),
            ),
            const SizedBox(width: 12),
            // عرض الموجات التفاعلي
            Expanded(
              child: StreamBuilder<PlaybackDisposition>(
                stream: widget.audioRecorderService.onProgress,
                builder: (context, snapshot) {
                  double progress = 0.0;
                  if (snapshot.hasData && isPlaying) {
                    final duration = snapshot.data!.duration.inMilliseconds;
                    final position = snapshot.data!.position.inMilliseconds;
                    if (duration > 0) {
                      progress = (position / duration).clamp(0.0, 1.0);
                    }
                  } else if (!isPlaying && snapshot.hasData && snapshot.data!.position.inMilliseconds > 0) {
                     // للحفاظ على التقدم عند الإيقاف المؤقت (تقريبي)
                     final duration = snapshot.data!.duration.inMilliseconds;
                     final position = snapshot.data!.position.inMilliseconds;
                     if (duration > 0) progress = (position / duration).clamp(0.0, 1.0);
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       Text(
                        'معاينة التسجيل',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 36,
                        child: CustomPaint(
                          painter: InteractivePreviewPainter(
                             samples: _downsample(widget.audioRecorderService.waveformData, 50),
                             color: theme.colorScheme.primary,
                             progress: progress,
                          ),
                          size: Size.infinite,
                        ),
                      )
                    ],
                  );
                }
              ),
            ),
            const SizedBox(width: 12),
            // زر الإرسال
            widget.isUploading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : GestureDetector(
                  onTap: () async {
                    await widget.onSendAudio(0);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.3), blurRadius: 8, spreadRadius: 1)
                      ]
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 24),
                  ),
                ),
          ],
        ),
      );
    }

    // --- 3. الوضع العادي (Normal Mode) ---
    return Container(
      color: theme.colorScheme.surface, 
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // منطقة الرد على رسالة
          if (widget.replyingToMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: Border(top: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.1))),
              ),
              child: Row(
                children: [
                  Icon(Icons.reply_rounded, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                          border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.replyingToMessage!.isMe ? 'أنت' : widget.replyingToMessage!.senderName,
                            style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 12),
                          ),
                          Text(widget.replyingToMessage!.message, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: widget.onCancelReply,
                  )
                ],
              ),
            ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0)
                .copyWith(bottom: MediaQuery.of(context).padding.bottom + 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // زر المرفقات
                IconButton(
                  icon: Icon(Icons.attach_file_rounded, color: theme.colorScheme.onSurfaceVariant),
                  onPressed: widget.isUploading 
                    ? null 
                    : (widget.isMubasharaMode 
                        ? () => _showMubasharaOptions(context)
                        : widget.onSendFile),
                ),
                
                // حقل الكتابة
                Expanded(
                  child: widget.isMubasharaMode 
                  ? InkWell(
                      onTap: () => _showMubasharaOptions(context),
                      child: Container(
                        height: 50,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.videocam_outlined, color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Text(
                              "اضغط لرفع فيديو مباشرة",
                              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _messageController,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالة...',
                        hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // زر الإرسال أو الميكروفون (مع أنيميشن)
                if (!widget.isMubasharaMode) ...[
                  widget.isUploading
                      ? const Padding(
                        padding: EdgeInsets.all(10.0),
                        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                      : Stack(
                        alignment: Alignment.center,
                        children: [
                          // زر الميكروفون (يظهر عندما لا يوجد نص)
                          if (!_showSendButton)
                            GestureDetector(
                              onTap: () async {
                                await widget.audioRecorderService.startRecording();
                              },
                              child: Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.secondary, // لون مختلف للميكروفون
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))]
                                ),
                                child: const Icon(
                                  Icons.mic_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),

                          // زر الإرسال (يظهر عند الكتابة)
                          ScaleTransition(
                            scale: _sendButtonScale,
                            child: GestureDetector(
                              onTap: _sendTextMessage,
                              child: Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(0, 2))]
                                ),
                                child: const Icon(Icons.send_rounded, color: Colors.white, size: 24),
                              ),
                            ),
                          ),
                        ],
                      )
                ] else ...[
                   if (widget.isUploading)
                     const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                ]
              ],
            ),
          ),
        ],
      ),
    );
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
}

class InteractivePreviewPainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  final double progress;

  InteractivePreviewPainter({required this.samples, required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paintPlayed = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;
      
    final paintUnplayed = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final count = samples.length;
    final barWidth = (size.width / count) * 0.6; 
    final gap = (size.width / count) * 0.4;
    final centerY = size.height / 2;

    for (int i = 0; i < count; i++) {
      double value = samples[i];
      double height = (value * size.height).clamp(4.0, size.height);
      double left = i * (barWidth + gap) + gap / 2;
      double top = centerY - (height / 2);
      
      // تحديد حالة التشغيل للعمود
      final barProgress = i / count;
      final isPlayed = barProgress <= progress;
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, height),
          Radius.circular(barWidth / 2),
        ),
        isPlayed ? paintPlayed : paintUnplayed,
      );
    }
  }

  @override
  bool shouldRepaint(covariant InteractivePreviewPainter oldDelegate) {
    return oldDelegate.samples != samples || oldDelegate.progress != progress;
  }
}
