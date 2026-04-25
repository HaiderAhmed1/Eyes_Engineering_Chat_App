import 'package:flutter/material.dart';
import 'package:chat_app/services/audio_recorder_service.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chat_app/screens/media_viewer_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:chat_app/screens/forward_screen.dart';

class MessageBubble extends StatelessWidget {
  final String messageId;
  final String text;
  final String? fileUrl;
  final String? fileName;
  final String type;
  final bool isMe;
  final String senderId;
  final String? senderName;
  final String? senderImageUrl;
  final Map<String, dynamic>? replyTo;
  final String status;
  final bool isRead;
  final bool isEdited;
  final Map<dynamic, dynamic>? reactions;
  final bool isForwarded;

  final dynamic timestamp;
  final int? duration;
  final List<dynamic>? waveform;

  final AudioRecorderService audioRecorderService;
  final bool isPlayingAudio;
  final VoidCallback onPlayAudio;
  final VoidCallback onStopAudio;
  
  final Function(String emoji)? onReactionSelected;

  const MessageBubble({
    super.key,
    required this.messageId,
    required this.text,
    this.fileUrl,
    this.fileName,
    required this.type,
    required this.isMe,
    required this.senderId,
    this.senderName,
    this.senderImageUrl,
    this.replyTo,
    required this.status,
    required this.isRead,
    this.isEdited = false,
    this.reactions,
    this.isForwarded = false,
    required this.timestamp,
    this.duration,
    this.waveform,
    required this.audioRecorderService,
    required this.isPlayingAudio,
    required this.onPlayAudio,
    required this.onStopAudio,
    this.onReactionSelected,
  });

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    DateTime date;
    try {
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is int) {
        date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else {
        return '';
      }
      return intl.DateFormat('h:mm a', 'en').format(date);
    } catch (e) {
      return '';
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  void _showMessageOptions(BuildContext context) {
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
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['❤️', '😂', '😮', '😢', '👍', '👎'].map((emoji) {
                  return InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      if (onReactionSelected != null) {
                        onReactionSelected!(emoji);
                      }
                    },
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  );
                }).toList(),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('رد'),
              onTap: () {
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('إعادة توجيه'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ForwardScreen(messageToForward: ForwardedMessage(
                    text: text,
                    type: type,
                    fileUrl: fileUrl,
                    fileName: fileName,
                  )),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('نسخ'),
              onTap: () {
                Navigator.pop(ctx);
              },
            ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('حذف', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioPlayerBubble(BuildContext context, Color contentColor) {
    final dbDuration = duration != null
        ? Duration(milliseconds: duration!)
        : Duration.zero;
        
    final hasWaveform = waveform != null && waveform!.isNotEmpty;
    final List<double> samples = hasWaveform 
        ? waveform!.map((e) => (e as num).toDouble()).toList() 
        : [];

    return Container(
      width: 260,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: isPlayingAudio ? onStopAudio : onPlayAudio,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: contentColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))
                ],
              ),
              child: Icon(
                isPlayingAudio ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: contentColor,
                size: 30,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StreamBuilder<PlaybackDisposition>(
              stream: audioRecorderService.onProgress,
              builder: (context, snapshot) {
                final isThisMessagePlaying = isPlayingAudio && snapshot.hasData;
                final totalDuration = isThisMessagePlaying ? snapshot.data!.duration : dbDuration;
                final currentPosition = isThisMessagePlaying ? snapshot.data!.position : Duration.zero;

                final maxDurationMs = totalDuration.inMilliseconds.toDouble();
                final currentPosMs = currentPosition.inMilliseconds.toDouble();
                final safeMax = maxDurationMs > 0 ? maxDurationMs : 1.0;
                final safePos = currentPosMs.clamp(0.0, safeMax);
                final progress = safePos / safeMax;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (hasWaveform)
                      SizedBox(
                        height: 36,
                        child: CustomPaint(
                          painter: ModernWaveformPlaybackPainter(
                            samples: samples,
                            color: contentColor,
                            progress: progress,
                          ),
                          size: Size.infinite,
                        ),
                      )
                    else
                       SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: contentColor,
                          inactiveTrackColor: contentColor.withValues(alpha: 0.2),
                          thumbColor: contentColor,
                        ),
                        child: Slider(
                          value: safePos,
                          min: 0.0,
                          max: safeMax,
                          onChanged: (value) {
                            if (isPlayingAudio) {
                              audioRecorderService.seekToPlayer(value.toInt());
                            }
                          },
                        ),
                      ),
                    
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(currentPosition), 
                          style: TextStyle(fontSize: 10, color: contentColor.withValues(alpha: 0.9), fontWeight: FontWeight.bold)
                        ),
                        Text(
                          _formatDuration(totalDuration), 
                          style: TextStyle(fontSize: 10, color: contentColor.withValues(alpha: 0.7), fontWeight: FontWeight.w500)
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileWidget(BuildContext context, Color contentColor) {
    IconData iconData = type == 'video' ? Icons.videocam_rounded : Icons.insert_drive_file_rounded;

    return InkWell(
      onTap: () async {
        if (fileUrl == null) return;
        if (type == 'video') {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (ctx) => MediaViewerScreen(mediaUrl: fileUrl!, mediaType: 'video'),
          ));
        } else {
          final uri = Uri.parse(fileUrl!);
          if (!await launchUrl(uri)) {}
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: contentColor.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: contentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(iconData, color: contentColor, size: 24),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName ?? (type == 'video' ? 'فيديو' : 'ملف'),
                    style: TextStyle(color: contentColor, fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    type == 'video' ? 'انقر للمشاهدة' : 'انقر للفتح',
                    style: TextStyle(color: contentColor.withValues(alpha: 0.6), fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // التعديل هنا: هذا الويدجت لم يعد يستخدم Positioned بداخله، بل يتم استدعاؤه داخل Stack الفقاعة
  Widget _buildReactionsWidget(BuildContext context) {
    if (reactions == null || reactions!.isEmpty) return const SizedBox.shrink();
    
    final Map<String, int> reactionCounts = {};
    reactions!.forEach((_, emoji) => reactionCounts[emoji] = (reactionCounts[emoji] ?? 0) + 1);

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1), width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: reactionCounts.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 12)),
                if (entry.value > 1) ...[
                  const SizedBox(width: 2),
                  Text(entry.value.toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildReadReceiptIcon() {
    if (!isMe) return const SizedBox.shrink();
    
    IconData icon;
    Color color;
    const activeColor = Color(0xFF00E5FF); 
    const inactiveColor = Colors.white38;

    if (isRead) {
      icon = Icons.done_all_rounded;
      color = activeColor;
    } else if (status == 'delivered') {
      icon = Icons.done_all_rounded;
      color = inactiveColor;
    } else {
      icon = Icons.check_rounded;
      color = inactiveColor;
    }
    return Icon(icon, size: 16, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeString = _formatTime(timestamp);
    const contentColor = Colors.white;

    const rBig = Radius.circular(22);
    const rSmall = Radius.circular(4);

    final borderRadius = BorderRadius.only(
      topLeft: rBig,
      topRight: rBig,
      bottomLeft: isMe ? rBig : rSmall,
      bottomRight: isMe ? rSmall : rBig,
    );

    final bubbleDecoration = BoxDecoration(
      gradient: isMe
          ? LinearGradient(
              colors: [
                theme.colorScheme.primary,
                Color.lerp(theme.colorScheme.primary, Colors.black, 0.2)!
              ], 
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
      color: isMe ? null : const Color(0xFF2A2D3A),
      borderRadius: borderRadius,
      border: Border.all(
        color: isMe ? Colors.transparent : Colors.white.withValues(alpha: 0.05), 
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 6,
          offset: const Offset(0, 3),
        )
      ],
    );

    Widget bubbleContent;
    if (type == 'image' && fileUrl != null) {
      bubbleContent = GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MediaViewerScreen(mediaUrl: fileUrl!, mediaType: 'image'))),
        child: Hero(
          tag: fileUrl!,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
            ),
            child: ClipRRect(
              borderRadius: borderRadius,
              child: Image.network(
                fileUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (ctx, child, p) => p == null ? child : Container(
                  height: 180, width: 180,
                  color: Colors.black26,
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
            ),
          ),
        ),
      );
    } else if (type == 'audio' && fileUrl != null) {
      bubbleContent = _buildAudioPlayerBubble(context, contentColor);
    } else if (type == 'video' || type == 'file') {
      bubbleContent = _buildFileWidget(context, contentColor);
    } else {
      bubbleContent = Text.rich(
        TextSpan(
          text: text,
          style: const TextStyle(
              color: contentColor,
              fontSize: 16,
              height: 1.5,
              letterSpacing: 0.3,
              fontFamily: 'Cairo', 
          ),
          children: [
            if (isEdited)
              TextSpan(
                text: ' (معدل)',
                style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: contentColor.withValues(alpha: 0.6)),
              ),
          ],
        ),
      );
    }

    return GestureDetector(
      onLongPress: () => _showMessageOptions(context),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe && senderName != null && senderName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 56.0, bottom: 4),
                child: Text(
                  senderName!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),

            Row(
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Avatar for sender
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0, left: 8.0),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3), width: 1.5),
                      ),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        backgroundImage: (senderImageUrl != null && senderImageUrl!.isNotEmpty) ? NetworkImage(senderImageUrl!) : null,
                        child: (senderImageUrl == null || senderImageUrl!.isEmpty) ? Icon(Icons.person, size: 16, color: theme.colorScheme.onSurfaceVariant) : null,
                      ),
                    ),
                  )
                 else
                   const SizedBox(width: 16), // مسافة في اليسار إذا كان أنا للحفاظ على التنسيق

                Flexible(
                  child: Stack(
                    clipBehavior: Clip.none, // للسماح للإيموجي بالظهور على الحافة
                    children: [
                      // 1. الفقاعة الرئيسية
                      Container(
                        margin: EdgeInsets.only(bottom: (reactions != null && reactions!.isNotEmpty) ? 14.0 : 0), // مسافة للرياكشن
                        decoration: type == 'image' ? null : bubbleDecoration,
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                        child: Padding(
                          padding: type == 'image' ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isForwarded)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.forward, size: 12, color: contentColor.withValues(alpha: 0.8)),
                                      const SizedBox(width: 4),
                                      Text('محولة', style: TextStyle(fontSize: 10, color: contentColor.withValues(alpha: 0.8), fontStyle: FontStyle.italic)),
                                    ],
                                  ),
                                ),

                              if (replyTo != null)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border(left: BorderSide(color: theme.colorScheme.secondary, width: 4))
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(replyTo!['senderName'] ?? 'مجهول', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: theme.colorScheme.secondary)),
                                      const SizedBox(height: 2),
                                      Text(replyTo!['message'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: contentColor.withValues(alpha: 0.8))),
                                    ],
                                  ),
                                ),

                              bubbleContent,

                              if (type != 'image') ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    const SizedBox(width: 20),
                                    Text(timeString, style: TextStyle(fontSize: 10, color: contentColor.withValues(alpha: 0.6))),
                                    if (isMe) ...[
                                      const SizedBox(width: 4),
                                      _buildReadReceiptIcon(),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // 2. الرياكشنز (مثبتة بالنسبة للفقاعة)
                      if (reactions != null && reactions!.isNotEmpty)
                        Positioned(
                          bottom: -2, // تداخل خفيف مع الأسفل
                          right: isMe ? 10 : null, // إذا أنا: على اليمين
                          left: isMe ? null : 10,  // إذا الطرف الآخر: على اليسار
                          child: _buildReactionsWidget(context),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ModernWaveformPlaybackPainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  final double progress; 

  ModernWaveformPlaybackPainter({
    required this.samples,
    required this.color,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final playedPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;
      
    final unplayedPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    if (samples.isEmpty) return;

    final count = samples.length;
    final barWidth = (size.width / count) * 0.65;
    final gap = (size.width / count) * 0.35;
    final centerY = size.height / 2;

    for (int i = 0; i < count; i++) {
      double value = samples[i];
      double height = (value * size.height * 1.2).clamp(4.0, size.height);
      double left = i * (barWidth + gap) + gap / 2;
      double top = centerY - (height / 2);
      double barProgress = i / count;
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, height),
          Radius.circular(barWidth),
        ),
        barProgress < progress ? playedPaint : unplayedPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ModernWaveformPlaybackPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.samples != samples;
  }
}
