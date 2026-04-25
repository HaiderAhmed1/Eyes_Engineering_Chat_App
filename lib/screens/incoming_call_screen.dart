import 'package:flutter/material.dart';
import 'package:chat_app/services/call_service.dart';
import 'package:chat_app/screens/video_call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  final Call call; // استخدام نموذج Call المعرف في call_service.dart

  const IncomingCallScreen({super.key, required this.call});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {

  @override
  void initState() {
    super.initState();
    _initializeIncomingCall();
  }

  // 🟢 [جديد]: دالة تعمل بمجرد ظهور شاشة استقبال المكالمة
  Future<void> _initializeIncomingCall() async {
    // 1. تشغيل نغمة الرنين المحلية للمستقبل
    await CallService.playRingingTone();

    // 2. تحديث حالة المكالمة في Firestore إلى "ringing" (يرن)
    // لكي تتغير الكلمة عند المتصل من "جارِ الاتصال" إلى "يرن"
    await CallService.updateCallStatus(
      callerId: widget.call.callerId,
      receiverId: widget.call.receiverId,
      status: 'ringing',
    );
  }

  @override
  void dispose() {
    // 🎵 التأكد من إيقاف الصوت عند إغلاق الشاشة لأي سبب
    CallService.stopAudio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const Color goldColor = Color(0xFFFFD700);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withOpacity(0.1),
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            // حالة الاتصال
            Text(
              widget.call.isVideo ? "مكالمة فيديو واردة..." : "مكالمة صوتية واردة...",
              style: theme.textTheme.titleMedium?.copyWith(
                color: goldColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),

            // صورة المتصل بتصميم دائري ذهبي
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: goldColor, width: 2),
              ),
              child: CircleAvatar(
                radius: 60,
                backgroundImage: widget.call.callerPic.isNotEmpty
                    ? NetworkImage(widget.call.callerPic)
                    : null,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                child: widget.call.callerPic.isEmpty
                    ? const Icon(Icons.person, size: 60, color: Colors.white)
                    : null,
              ),
            ),

            const SizedBox(height: 20),

            // اسم المتصل
            Text(
              widget.call.callerName,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),

            const Spacer(),

            // أزرار التحكم (القبول والرفض)
            Padding(
              padding: const EdgeInsets.only(bottom: 80),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 🔴 زر الرفض
                  _buildCallButton(
                    icon: Icons.call_end,
                    color: Colors.redAccent,
                    onTap: () async {
                      // 1. إيقاف الرنين فوراً
                      await CallService.stopAudio();

                      // 2. تسجيل المكالمة كمرفوضة
                      await CallService.saveCallHistory(call: widget.call, status: 'rejected');

                      // 3. إنهاء المكالمة في النظام
                      await CallService.endCall(
                        callerId: widget.call.callerId,
                        receiverId: widget.call.receiverId,
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),

                  // 🟢 زر القبول
                  _buildCallButton(
                    icon: widget.call.isVideo ? Icons.videocam : Icons.call,
                    color: Colors.greenAccent[400]!,
                    onTap: () async {
                      // 1. إيقاف الرنين فوراً
                      await CallService.stopAudio();

                      // 2. تحديث الحالة إلى "answered" (تم الرد)
                      // لكي يتوقف الرنين عند المتصل ويبدأ عداد الوقت بالعمل
                      await CallService.updateCallStatus(
                        callerId: widget.call.callerId,
                        receiverId: widget.call.receiverId,
                        status: 'answered',
                      );

                      // 3. تسجيل المكالمة في السجل
                      await CallService.saveCallHistory(call: widget.call, status: 'accepted');

                      if (context.mounted) {
                        // 4. الانتقال لشاشة الاتصال الفعلي
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => VideoCallScreen(call: widget.call),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ويدجت مخصص لبناء أزرار الاتصال
  Widget _buildCallButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 2,
            )
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 32),
      ),
    );
  }
}