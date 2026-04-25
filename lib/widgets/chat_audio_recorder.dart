import 'dart:async';
import 'package:flutter/material.dart';
import 'package:chat_app/services/audio_recorder_service.dart';

class ChatAudioRecorder extends StatefulWidget {
  final AudioRecorderService audioRecorderService;
  final VoidCallback onCancel;
  final Future<void> Function(int duration) onSend;

  const ChatAudioRecorder({
    super.key,
    required this.audioRecorderService,
    required this.onCancel,
    required this.onSend,
  });

  @override
  State<ChatAudioRecorder> createState() => _ChatAudioRecorderState();
}

class _ChatAudioRecorderState extends State<ChatAudioRecorder> with SingleTickerProviderStateMixin {
  Timer? _timer;
  int _recordDuration = 0;
  StreamSubscription? _amplitudeSubscription;
  final List<double> _liveWaveform = List.filled(60, 0.05); // 60 عينة
  
  late AnimationController _micAnimationController;

  @override
  void initState() {
    super.initState();
    _micAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    
    _startTimerAndWaveform();
  }

  void _startTimerAndWaveform() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _recordDuration++);
    });

    _amplitudeSubscription = widget.audioRecorderService.amplitudeStream.listen((amp) {
      if (mounted) {
        setState(() {
          _liveWaveform.add(amp);
          if (_liveWaveform.length > 60) {
            _liveWaveform.removeAt(0);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _micAnimationController.dispose();
    _timer?.cancel();
    _amplitudeSubscription?.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final int min = seconds ~/ 60;
    final int sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // تدرج لوني للموجات
    final waveGradient = LinearGradient(
      colors: [
        Colors.redAccent.withValues(alpha: 0.4),
        Colors.redAccent,
        Colors.redAccent.withValues(alpha: 0.4),
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    return Container(
      height: 70, // ارتفاع ثابت
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(35), // شكل دائري
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2)
          )
        ],
      ),
      child: Row(
        children: [
          // زر الحذف بتأثير نبضي
          GestureDetector(
            onTap: widget.onCancel,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 26),
            ),
          ),
          const SizedBox(width: 12),
          
          // التوقيت والموجات
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // التوقيت مع أيقونة تسجيل نابضة
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: _micAnimationController,
                      child: Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatDuration(_recordDuration),
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // رسم الموجات
                SizedBox(
                  height: 36,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: UltraWaveformPainter(
                      samples: _liveWaveform,
                      gradient: waveGradient,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 12),
          
          // زر الإرسال
          GestureDetector(
            onTap: () => widget.onSend(_recordDuration),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}

class UltraWaveformPainter extends CustomPainter {
  final List<double> samples;
  final Gradient gradient;

  UltraWaveformPainter({required this.samples, required this.gradient});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final count = samples.length;
    // حساب العرض والفراغ بدقة
    final totalGapWidth = size.width * 0.3; // 30% فراغات
    final totalBarWidth = size.width - totalGapWidth;
    final barWidth = totalBarWidth / count;
    final gap = totalGapWidth / (count - 1);
    
    final centerY = size.height / 2;

    for (int i = 0; i < count; i++) {
      double value = samples[i];
      // تنعيم القيم المنخفضة جداً للحفاظ على خط أساسي
      if (value < 0.05) value = 0.05;
      
      // تكبير التأثير البصري للأصوات العالية
      double height = value * size.height;
      
      // تأثير التلاشي للأطراف (الأقدم والأحدث) لتبدو الموجة وكأنها تدخل وتخرج
      double opacity = 1.0;
      if (i < 5) opacity = i / 5.0;
      if (i > count - 5) opacity = (count - i) / 5.0;
      
      paint.color = Colors.redAccent.withValues(alpha: opacity.clamp(0.2, 1.0)); // Fallback if shader fails or for opacity simulation logic

      double left = i * (barWidth + gap);
      double top = centerY - (height / 2);
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, height),
          Radius.circular(barWidth),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant UltraWaveformPainter oldDelegate) {
    return oldDelegate.samples != samples;
  }
}
