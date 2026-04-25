import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:chat_app/firebase_options.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // تهيئة الخدمة
  static Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/launcher_icon');

    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTapBackground,
    );

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _createNotificationChannels();
  }

  static Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel defaultChannel = AndroidNotificationChannel(
      'high_importance_channel',
      'إشعارات الرسائل والمكالمات', // تم تحديث الاسم
      description: 'تستخدم هذه القناة للإشعارات المهمة والمكالمات الواردة.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(defaultChannel);
  }

  // دالة مساعدة لتحميل الصور
  static Future<String> _downloadAndSaveFile(String url, String fileName) async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final String filePath = '${directory.path}/$fileName';
    final http.Response response = await http.get(Uri.parse(url));
    final File file = File(filePath);
    await file.writeAsBytes(response.bodyBytes);
    return filePath;
  }

  // عرض الإشعار المتطور
  static Future<void> showNotification(RemoteMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    final bool enabled = prefs.getBool('notifications_enabled') ?? true;
    if (!enabled) return;

    const String channelId = 'high_importance_channel';
    final Map<String, dynamic> data = message.data;
    final RemoteNotification? notification = message.notification;

    String title = notification?.title ?? data['senderName'] ?? 'إشعار جديد';
    String body = notification?.body ?? data['text'] ?? '';
    String? imageUrl = data['imageUrl'] ?? data['fileUrl']; // إذا كانت الرسالة صورة
    String? senderImage = data['senderImage']; // صورة البروفايل
    String? type = data['type'];

    // 🟢 إضافة هامة: التمييز بين المكالمة والرسالة العادية
    // نتحقق إذا كان الإشعار مكالمة بناءً على الـ type أو وجود channelId الخاص بـ Agora
    bool isCall = type == 'call' || data['isCall'] == 'true' || data.containsKey('channelId');

    // تحسين النص بناءً على النوع
    if (isCall) {
      body = '📞 مكالمة واردة...';
    } else if (type == 'image') {
      body = '📷 صورة';
      imageUrl = data['fileUrl']; // تأكيد استخدام رابط الصورة
    } else if (type == 'video') {
      body = '🎥 فيديو';
    } else if (type == 'audio') {
      body = '🎤 رسالة صوتية';
    } else if (type == 'file') {
      body = '📎 ملف';
    }

    if (body.isEmpty) body = 'محتوى جديد';

    // إعداد الأنماط المتقدمة
    StyleInformation? styleInformation;
    String? bigPicturePath;
    String? largeIconPath;

    try {
      // 1. تحميل صورة البروفايل (Large Icon)
      if (senderImage != null && senderImage.isNotEmpty) {
        largeIconPath = await _downloadAndSaveFile(senderImage, 'large_icon_${DateTime.now().millisecondsSinceEpoch}.jpg');
      }

      // 2. تحميل الصورة الكبيرة (Big Picture) إذا كانت الرسالة صورة
      if (type == 'image' && imageUrl != null && imageUrl.isNotEmpty) {
        bigPicturePath = await _downloadAndSaveFile(imageUrl, 'big_picture_${DateTime.now().millisecondsSinceEpoch}.jpg');

        styleInformation = BigPictureStyleInformation(
          FilePathAndroidBitmap(bigPicturePath),
          largeIcon: largeIconPath != null ? FilePathAndroidBitmap(largeIconPath) : null,
          contentTitle: title,
          summaryText: body,
          hideExpandedLargeIcon: true,
        );
      } else {
        // نمط النص الكبير للرسائل الطويلة
        styleInformation = BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: body, // يظهر عند الطي
        );
      }
    } catch (e) {
      debugPrint("Error loading images for notification: $e");
    }

    await _flutterLocalNotificationsPlugin.show(
      notification?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'إشعارات الرسائل والمكالمات',
          channelDescription: 'تنبيهات الرسائل والمكالمات الواردة',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/launcher_icon',
          largeIcon: largeIconPath != null ? FilePathAndroidBitmap(largeIconPath) : null,
          styleInformation: styleInformation,
          playSound: true,
          enableVibration: true,

          // 🟢 التعديل الجذري لحل مشكلة الشاشة المغلقة والمكالمات المخفية
          fullScreenIntent: isCall, // يوقظ الشاشة ويظهر الإشعار فوق القفل إذا كانت مكالمة
          category: isCall ? AndroidNotificationCategory.call : AndroidNotificationCategory.message,

          visibility: NotificationVisibility.public,

          // تجميع الإشعارات للرسائل فقط (لضمان عدم دمج المكالمات مع الرسائل)
          groupKey: isCall ? null : (data['chatId'] ?? 'com.haider.chat.app.WORK_EMAIL'),
          setAsGroupSummary: false,

          // أزرار التفاعل (نظهرها فقط إذا لم تكن مكالمة، لأن المكالمة لها شاشتها الخاصة)
          actions: isCall ? [] : [
            const AndroidNotificationAction(
              'reply_action',
              'رد',
              inputs: [AndroidNotificationActionInput(label: 'اكتب ردك...')],
            ),
            const AndroidNotificationAction(
              'mark_read',
              'تمت القراءة',
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          attachments: [],
        ),
      ),
      payload: data.toString(),
    );
  }

  static void _onNotificationTap(NotificationResponse details) {
    debugPrint("Tap Notification: ${details.payload}");
  }

  @pragma('vm:entry-point')
  static void _onNotificationTapBackground(NotificationResponse details) {
    debugPrint("Background Tap: ${details.payload}");
  }

  @pragma('vm:entry-point')
  static Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await showNotification(message);
  }
}