import 'package:flutter/material.dart';
import 'package:chat_app/services/call_service.dart';
import 'package:chat_app/screens/video_call_screen.dart';

class CallOverlay {
  static OverlayEntry? _overlayEntry;
  // استخدام ValueNotifier لمراقبة حالة التصغير
  static final ValueNotifier<bool> isMinimized = ValueNotifier<bool>(false);

  // مرجع لتخزين السياق (Context) لضمان الإغلاق الصحيح
  static BuildContext? _savedContext;

  // 1️⃣ فتح المكالمة كطبقة عائمة
  static void show(BuildContext context, Call call) {
    if (_overlayEntry != null) return;

    _savedContext = context;
    isMinimized.value = false;

    _overlayEntry = OverlayEntry(
      builder: (context) => ValueListenableBuilder<bool>(
        valueListenable: isMinimized,
        builder: (context, minimized, child) {
          return Material( // إضافة Material لضمان عمل العناصر التفاعلية
            color: Colors.transparent,
            child: Stack(
              children: [
                // الشاشة الكاملة
                Offstage(
                  offstage: minimized,
                  child: VideoCallScreen(call: call),
                ),

                // الشريط العائم (يظهر فقط عند التصغير)
                if (minimized) _buildFloatingBar(context, call),
              ],
            ),
          );
        },
      ),
    );

    // إدراج الطبقة في أعلى شجرة الودجت (rootOverlay لضمان ظهورها فوق الكيبورد والقوائم)
    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
  }

  // 2️⃣ تصغير المكالمة
  static void minimize() {
    isMinimized.value = true;
  }

  // 3️⃣ تكبير المكالمة
  static void maximize() {
    isMinimized.value = false;
  }

  // 4️⃣ إنهاء وإزالة الطبقة نهائياً (مع الحماية من الانهيار)
  static void dismiss() {
    if (_overlayEntry != null) {
      try {
        _overlayEntry!.remove();
      } catch (e) {
        debugPrint("Overlay already removed: $e");
      }
      _overlayEntry = null;
      _savedContext = null;
    }
  }

  // 🎨 تصميم الشريط العائم المحسّن
  static Widget _buildFloatingBar(BuildContext context, Call call) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return Positioned(
      top: statusBarHeight + 10,
      left: 15,
      right: 15,
      child: GestureDetector(
        onTap: maximize,
        onVerticalDragUpdate: (details) {
          // ميزة إضافية: إذا سحب المستخدم الشريط للأسفل يتم التكبير
          if (details.primaryDelta! > 10) maximize();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            // استخدام تدرج لوني ليعطي طابعاً احترافياً (أرجواني مثل تصميم تطبيقك)
            gradient: const LinearGradient(
              colors: [Color(0xFF7C4DFF), Color(0xFF6200EA)],
            ),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: Row(
            children: [
              // وميض بسيط للإشارة إلى أن المكالمة جارية
              const _RecordingDot(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      call.receiverName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const Text(
                      "اضغط للعودة للمكالمة",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_full, color: Colors.white, size: 22),
                onPressed: maximize,
              ),
              // زر إنهاء سريع من الشريط المصغر
              IconButton(
                icon: const Icon(Icons.call_end, color: Colors.redAccent, size: 22),
                onPressed: () {
                  CallService.endCall(
                      callerId: call.callerId,
                      receiverId: call.receiverId
                  );
                  dismiss();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ويدجت صغير لنقطة الوميض (تحسين جمالي)
class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 18),
    );
  }
}