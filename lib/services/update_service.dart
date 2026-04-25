import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      // 1. جلب إعدادات التحديث من Firebase
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('android_config')
          .get();

      if (!doc.exists) return;

      final data = doc.data()!;
      final String latestVersion = data['latest_version'];
      final String apkUrl = data['apk_url'];
      final bool forceUpdate = data['force_update'] ?? false;

      // 2. جلب نسخة التطبيق الحالية
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      // 3. مقارنة النسخ
      if (_isUpdateAvailable(currentVersion, latestVersion)) {
        if (context.mounted) {
          _showUpdateDialog(context, apkUrl, forceUpdate);
        }
      }
    } catch (e) {
      // print("Error checking for update: $e");
    }
  }

  // دالة مساعدة لمقارنة الأرقام (مثلاً 1.0.0 مع 1.0.1)
  static bool _isUpdateAvailable(String current, String latest) {
    List<int> currentParts = current.split('.').map(int.parse).toList();
    List<int> latestParts = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < latestParts.length; i++) {
      // إذا كان الجزء الحالي أصغر من الجديد، يوجد تحديث
      if (i >= currentParts.length || currentParts[i] < latestParts[i]) {
        return true;
      }
      // إذا كان الجزء الحالي أكبر، فلا يوجد تحديث (نحن أحدث)
      else if (currentParts[i] > latestParts[i]) {
        return false;
      }
    }
    return false; // متطابقان
  }

  static void _showUpdateDialog(BuildContext context, String url, bool force) {
    showDialog(
      context: context,
      barrierDismissible: !force, // إذا كان إجبارياً، لا يمكن إغلاق النافذة بالضغط خارجها
      builder: (ctx) => PopScope(
        canPop: !force, // منع زر الرجوع إذا كان إجبارياً
        child: AlertDialog(
          title: const Text('تحديث جديد متوفر 🚀'),
          content: const Text(
            'يوجد إصدار جديد من التطبيق يحتوي على تحسينات هامة.\nيرجى التحديث للمتابعة.',
          ),
          actions: [
            if (!force)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('لاحقاً'),
              ),
            ElevatedButton(
              onPressed: () async {
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('تحديث الآن'),
            ),
          ],
        ),
      ),
    );
  }
}
