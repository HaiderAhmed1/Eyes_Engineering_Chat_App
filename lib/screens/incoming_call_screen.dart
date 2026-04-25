import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vibration/vibration.dart'; // 📦 إضافة الاهتزاز
import 'package:wakelock_plus/wakelock_plus.dart'; // 📦 بقاء الشاشة مضاءة أثناء الرنين

import 'package:chat_app/services/call_service.dart';
import 'package:chat_app/screens/video_call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  final Call call;

  const IncomingCallScreen({super.key, required this.call});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  StreamSubscription<DocumentSnapshot>? _callSubscription; // مستمع لحالة المكالمة

  @override
  void initState() {
    super.initState();
    _initializeIncomingCall();
    _listenToCallCancellation(); // بدء الاستماع لاحتمالية إنهاء المتصل للمكالمة
  }

  Future<void> _initializeIncomingCall() async {
    // 💡 إبقاء الشاشة مضاءة أثناء الرنين
    WakelockPlus.enable();

    // 💡 تفعيل الاهتزاز المستمر
    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      // انتظار 500 ملي ثانية، ثم اهتزاز 1000، وتكرار ذلك
      Vibration.vibrate(pattern: [500, 1000], repeat: 0);
    }

    // 1. تشغيل نغمة الرنين المحلية للمستقبل
    await CallService.playRingingTone();

    // 2. تحديث حالة المكالمة في Firestore إلى "ringing"
    await CallService.updateCallStatus(
      callerId: widget.call.callerId,
      receiverId: widget.call.receiverId,
      status: 'ringing',
    );
  }

  // 🟢 دالة مجمعة لإيقاف كل تأثيرات الرنين (صوت + اهتزاز)
  Future<void> _stopRingingEffects() async {
    await CallService.stopAudio();
    Vibration.cancel();
    WakelockPlus.disable(); // السماح للشاشة بالانطفاء الطبيعي لاحقاً
  }

  // 🟢 [جديد]: دالة لمراقبة إذا قام المتصل بإنهاء المكالمة قبل أن نرد
  void _listenToCallCancellation() {
    _callSubscription = CallService.getCallStream(widget.call.callerId).listen((snapshot) {
      if (!snapshot.exists) {
        // إذا تم حذف وثيقة المكالمة (بمعنى أن المتصل أغلق الخط)
        _terminateScreenLocally();
      } else {
        final data = snapshot.data() as Map<String, dynamic>;
        if (data['callStatus'] == 'ended' || data['callStatus'] == 'missed') {
          _terminateScreenLocally();
        }
      }
    });
  }

  // 🟢 [جديد]: دالة لإنهاء الشاشة والصوت بأمان إذا ألغى المتصل
  void _terminateScreenLocally() async {
    await _stopRingingEffects();
    if (mounted) {
      Navigator.pop(context); // إغلاق شاشة الاستقبال
    }
  }

  // دالة رفض المكالمة (مستخدمة في الزر الأحمر وعند الضغط على زر الرجوع للهاتف)
  Future<void> _rejectCall() async {
    await _stopRingingEffects();
    await CallService.saveCallHistory(call: widget.call, status: 'rejected');
    await CallService.endCall(
      callerId: widget.call.callerId,
      receiverId: widget.call.receiverId,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _callSubscription?.cancel(); // إيقاف المستمع لمنع تسرب الذاكرة
    _stopRingingEffects(); // تأكيد إيقاف كل شيء عند تدمير الشاشة
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const Color goldColor = Color(0xFFFFD700);

    return PopScope(
      canPop: false, // منع الخروج العشوائي
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // 🟢 [جديد]: إذا ضغط المستخدم على زر الرجوع في الهاتف، نعتبرها "رفض للمكالمة"
        await _rejectCall();
      },
      child: Scaffold(
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
              Text(
                widget.call.isVideo ? "مكالمة فيديو واردة..." : "مكالمة صوتية واردة...",
                style: theme.textTheme.titleMedium?.copyWith(
                  color: goldColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),

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

              Text(
                widget.call.callerName,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const Spacer(),

              Padding(
                padding: const EdgeInsets.only(bottom: 80),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 🔴 زر الرفض
                    _buildCallButton(
                      icon: Icons.call_end,
                      color: Colors.redAccent,
                      onTap: _rejectCall, // استخدام الدالة المجمعة الجديدة
                    ),

                    // 🟢 زر القبول
                    _buildCallButton(
                      icon: widget.call.isVideo ? Icons.videocam : Icons.call,
                      color: Colors.greenAccent[400]!,
                      onTap: () async {
                        // 1. إيقاف التأثيرات (الاهتزاز والصوت) فوراً
                        await _stopRingingEffects();

                        // 2. تحديث الحالة إلى "answered" (تم الرد)
                        await CallService.updateCallStatus(
                          callerId: widget.call.callerId,
                          receiverId: widget.call.receiverId,
                          status: 'answered',
                        );

                        // 3. تسجيل المكالمة في السجل كـ "مقبولة"
                        await CallService.saveCallHistory(call: widget.call, status: 'accepted');

                        if (context.mounted) {
                          // 4. الانتقال لشاشة الاتصال الفعلي (شاشة Agora)
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
      ),
    );
  }

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