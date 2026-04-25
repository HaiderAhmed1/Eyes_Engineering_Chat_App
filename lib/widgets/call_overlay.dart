import 'package:flutter/material.dart';
import 'package:chat_app/services/call_service.dart';
import 'package:chat_app/screens/video_call_screen.dart';

class CallOverlay {
  static OverlayEntry? _overlayEntry;
  // متغير لمراقبة حالة الشاشة (هل هي مصغرة أم لا)
  static final ValueNotifier<bool> isMinimized = ValueNotifier<bool>(false);

  // 1️⃣ فتح المكالمة كطبقة عائمة فوق التطبيق
  static void show(BuildContext context, Call call) {
    if (_overlayEntry != null) return; // منع فتح أكثر من مكالمة في نفس الوقت

    isMinimized.value = false;

    _overlayEntry = OverlayEntry(
      builder: (context) => ValueListenableBuilder<bool>(
        valueListenable: isMinimized,
        builder: (context, minimized, child) {
          return Stack(
            children: [
              // الشاشة الكاملة: نستخدم Offstage لإخفائها دون تدميرها (لكي لا ينقطع الاتصال)
              Offstage(
                offstage: minimized,
                child: VideoCallScreen(call: call),
              ),

              // الشريط الأخضر العائم: يظهر فقط عندما تكون الشاشة مصغرة
              if (minimized) _buildFloatingBar(context, call),
            ],
          );
        },
      ),
    );

    // إضافة الطبقة للتطبيق
    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
  }

  // 2️⃣ تصغير المكالمة
  static void minimize() {
    isMinimized.value = true;
  }

  // 3️⃣ تكبير المكالمة (العودة للشاشة الكاملة)
  static void maximize() {
    isMinimized.value = false;
  }

  // 4️⃣ إنهاء المكالمة وإزالة الطبقة نهائياً
  static void dismiss() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // 🎨 تصميم الشريط العائم (الذي يظهر بالأعلى)
  static Widget _buildFloatingBar(BuildContext context, Call call) {
    // نستخدم SafeArea لكي لا يختفي الشريط تحت نوتش الكاميرا العلوية
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 10,
      right: 10,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: maximize, // عند الضغط نعود للمكالمة
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.green[600],
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                        call.isVideo ? Icons.videocam : Icons.call,
                        color: Colors.white,
                        size: 20
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "مكالمة جارية مع ${call.receiverName}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        decoration: TextDecoration.none, // مهم لأننا في Overlay
                      ),
                    ),
                  ],
                ),
                // أيقونة التوسيع
                const Icon(Icons.open_in_full, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}