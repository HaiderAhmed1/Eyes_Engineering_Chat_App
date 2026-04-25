import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'firebase_options.dart';

// الشاشات
import 'package:chat_app/screens/auth_screen.dart';
import 'package:chat_app/screens/user_data_check.dart';
import 'package:chat_app/theme.dart';
import 'package:chat_app/services/notification_service.dart';

// 🟢 [تم التحديث]: استيراد خدمة التحديثات الجديدة
import 'package:chat_app/services/app_update_service.dart';

// الحزم المساعدة
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';

// --- نقطة البداية (Main Function) ---
void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // تهيئة الإشعارات
    await NotificationService.initialize();
    FirebaseMessaging.onBackgroundMessage(NotificationService.firebaseMessagingBackgroundHandler);

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    runApp(const MyApp());

  }, (error, stack) {
    debugPrint("Global Error: $error");
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // 🟢 [تم التحديث]: إنشاء مفتاح عام للتحكم بالتنقل وإظهار النوافذ المنبثقة من أي مكان
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        _updateUserPresence(user.uid, true);
      }
    });

    // الاستماع للرسائل في المقدمة
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      NotificationService.showNotification(message);
    });

    // 🟢 [تم التحديث]: فحص التحديثات من GitHub بمجرد اكتمال رسم الشاشة الأولى
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_navigatorKey.currentContext != null) {
        AppUpdateService.checkForUpdate(_navigatorKey.currentContext!);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (state == AppLifecycleState.resumed) {
      _updateUserPresence(user.uid, true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _updateUserPresence(user.uid, false);
    }
  }

  Future<void> _updateUserPresence(String uid, bool isOnline) async {
    try {
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final Map<String, dynamic> presenceData = {
        'isOnline': isOnline,
        'lastSeen': DateTime.now().toIso8601String(),
      };
      await userDocRef.set(presenceData, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to update presence: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final customTheme = AppTheme.darkTheme.copyWith(
      textTheme: GoogleFonts.cairoTextTheme(AppTheme.darkTheme.textTheme),
    );

    return MaterialApp(
      // 🟢 [تم التحديث]: ربط المفتاح العام بالتطبيق
      navigatorKey: _navigatorKey,

      title: 'عيون الهندسة',
      debugShowCheckedModeBanner: false,
      theme: customTheme,
      locale: const Locale('ar', 'IQ'),
      supportedLocales: const [
        Locale('ar', ''),
        Locale('en', ''),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, widget) {
        ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 50),
                  const SizedBox(height: 16),
                  const Text("حدث خطأ غير متوقع!", style: TextStyle(color: Colors.white)),
                  Text(errorDetails.exceptionAsString(),
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          );
        };
        return widget!;
      },
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: CircularProgressIndicator(color: AppTheme.darkTheme.colorScheme.primary),
              ),
            );
          }

          if (snapshot.hasData && snapshot.data != null) {
            return UserDataCheck(key: ValueKey(snapshot.data!.uid));
          } else {
            return const AuthScreen();
          }
        },
      ),
    );
  }
}