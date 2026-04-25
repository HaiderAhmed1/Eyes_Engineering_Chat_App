import 'dart:async'; // تمت الإضافة من أجل StreamSubscription
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// --- استيراد الشاشات الأساسية ---
import 'package:chat_app/screens/chat_screen.dart';
import 'package:chat_app/screens/create_profile_screen.dart';

// --- استيراد خدمات وشاشات الاتصال الجديدة ---
import 'package:chat_app/services/call_service.dart';
import 'package:chat_app/screens/incoming_call_screen.dart';

class UserDataCheck extends StatefulWidget {
  const UserDataCheck({super.key});

  @override
  State<UserDataCheck> createState() => _UserDataCheckState();
}

class _UserDataCheckState extends State<UserDataCheck> {
  final _user = FirebaseAuth.instance.currentUser;
  late DocumentReference<Map<String, dynamic>> _userRef;

  // 💡 متغيرات جديدة للتحكم في حالة شاشة الاتصال
  StreamSubscription<DocumentSnapshot>? _callSubscription;
  bool _isCallScreenOpen = false;

  @override
  void initState() {
    super.initState();
    if (_user != null) {
      _userRef = FirebaseFirestore.instance.collection('users').doc(_user.uid);
      _setupFcmToken();
      _listenToIncomingCalls(); // بدء الاستماع للمكالمات في الخلفية
    }
  }

  Future<void> _setupFcmToken() async {
    final fcm = FirebaseMessaging.instance;
    try {
      // طلب الإذن أولاً (لضمان عمل الإشعارات على iOS و Android 13+)
      NotificationSettings settings = await fcm.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        final token = await fcm.getToken();
        if (token != null && mounted) {
          await _userRef.update({'fcmToken': token});
        }
      }
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  // 💡 الدالة الجديدة للاستماع للمكالمات الواردة
  void _listenToIncomingCalls() {
    _callSubscription = CallService.getCallStream(_user!.uid).listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final callMap = snapshot.data() as Map<String, dynamic>;
        final call = Call.fromMap(callMap);

        // التحقق من أن المستخدم الحالي هو "المستقبل" (hasDialled = false) وأن الشاشة ليست مفتوحة مسبقاً
        if (!call.hasDialled && !_isCallScreenOpen && mounted) {
          _isCallScreenOpen = true;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => IncomingCallScreen(call: call),
            ),
          ).then((_) {
            // عند إغلاق شاشة الرنين (بالقبول أو الرفض) نُعيد الحالة لـ false
            _isCallScreenOpen = false;
          });
        }
      } else {
        // إذا تم حذف وثيقة المكالمة (الطرف الآخر أنهى الاتصال قبل الرد)
        if (_isCallScreenOpen && mounted) {
          Navigator.pop(context); // إغلاق شاشة الرنين تلقائياً
          _isCallScreenOpen = false;
        }
      }
    });
  }

  @override
  void dispose() {
    _callSubscription?.cancel(); // إغلاق الاستماع لتجنب تسرب الذاكرة
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // إذا لم يكن هناك مستخدم مسجل، نخرجه (هذا إجراء أمان إضافي)
    if (_user == null) {
      return const Scaffold(body: Center(child: Text('يرجى تسجيل الدخول أولاً')));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      // أزلنا handleError من هنا لنتمكن من عرض الخطأ في الواجهة ومعرفة سببه
      stream: _userRef.snapshots(),
      builder: (context, snapshot) {

        // 1. معالجة الأخطاء (هذا ما سيحل مشكلة التعليق)
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 60),
                    const SizedBox(height: 16),
                    const Text(
                      'حدث خطأ أثناء الاتصال بقاعدة البيانات',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'السبب: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: const Text('تسجيل الخروج والمحاولة مجدداً'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // 2. حالة الانتظار (تظهر فقط عند أول تحميل)
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('جاري التحقق من بياناتك...'),
                ],
              ),
            ),
          );
        }

        // 3. معالجة البيانات في حال وجود المستند
        if (snapshot.hasData && snapshot.data!.exists) {
          final userData = snapshot.data!.data();

          if (userData != null) {
            final displayName = userData['displayName'];
            // نتحقق أن الاسم موجود وليس مجرد مسافة فارغة
            if (displayName != null && displayName.toString().trim().isNotEmpty) {
              return const ChatScreen();
            }
          }
        }

        // 4. إذا وصلنا هنا، يعني أن المستند غير موجود أو الاسم ناقص
        return const CreateProfileScreen();
      },
    );
  }
}