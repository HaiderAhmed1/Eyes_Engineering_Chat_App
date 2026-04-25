import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateService {
  // 🔗 إعدادات GitHub (قم بتغييرها لتطابق حسابك)
  static const String githubOwner = "HaiderAhmed1"; // اسم حسابك في جيت هب
  static const String githubRepo = "Eyes_Engineering_Chat_App";

  // رابط الـ API الخاص بـ GitHub لجلب أحدث إصدار
  static const String apiUrl = "https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest";

  // 1️⃣ فحص التحديثات
  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      // جلب رقم الإصدار الحالي للتطبيق
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version; // مثال: 1.0.0

      // الاتصال بـ GitHub
      final response = await Dio().get(apiUrl);

      if (response.statusCode == 200) {
        final data = response.data;
        String latestVersion = data['tag_name'].toString().replaceAll('v', ''); // نزيل حرف v إذا كان موجوداً (v1.0.1 -> 1.0.1)

        // البحث عن ملف الـ APK داخل المرفقات
        List assets = data['assets'];
        String? apkDownloadUrl;

        for (var asset in assets) {
          if (asset['name'].toString().endsWith('.apk')) {
            apkDownloadUrl = asset['browser_download_url'];
            break;
          }
        }

        // مقارنة الإصدارات
        if (_isUpdateAvailable(currentVersion, latestVersion) && apkDownloadUrl != null) {
          if (context.mounted) {
            _showUpdateDialog(context, latestVersion, apkDownloadUrl, data['body']);
          }
        } else {
          print("التطبيق محدث لأخر إصدار.");
        }
      }
    } catch (e) {
      print("خطأ في فحص التحديثات: $e");
    }
  }

  // 2️⃣ مقارنة أرقام الإصدارات
  static bool _isUpdateAvailable(String current, String latest) {
    List<int> currentParts = current.split('.').map(int.parse).toList();
    List<int> latestParts = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < currentParts.length; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  // 3️⃣ نافذة التحديث وشريط التقدم
  static void _showUpdateDialog(BuildContext context, String latestVersion, String downloadUrl, String releaseNotes) {
    double progress = 0.0;
    bool isDownloading = false;

    showDialog(
      context: context,
      barrierDismissible: false, // لا يمكن إغلاقها عند الضغط خارجها
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFFFFD700), width: 1.5), // حواف ذهبية
              ),
              title: const Row(
                children: [
                  Icon(Icons.system_update, color: Color(0xFFFFD700)),
                  SizedBox(width: 10),
                  Text('تحديث جديد متاح!'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("الإصدار $latestVersion متاح الآن.", style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(releaseNotes, style: const TextStyle(fontSize: 13, color: Colors.grey)), // الميزات الجديدة المكتوبة في جيت هب
                  const SizedBox(height: 20),

                  if (isDownloading) ...[
                    const Text("جاري تحميل التحديث..."),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey[800],
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                    ),
                    const SizedBox(height: 5),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text("${(progress * 100).toStringAsFixed(1)}%"),
                    ),
                  ]
                ],
              ),
              actions: [
                if (!isDownloading)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('لاحقاً', style: TextStyle(color: Colors.grey)),
                  ),
                if (!isDownloading)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () async {
                      setState(() {
                        isDownloading = true;
                      });
                      await _downloadAndInstall(downloadUrl, (downloadProgress) {
                        setState(() {
                          progress = downloadProgress;
                        });
                      });
                      if (context.mounted) Navigator.pop(context); // إغلاق النافذة بعد اكتمال التحميل
                    },
                    child: const Text('تحديث الآن'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  // 4️⃣ وظيفة التحميل الداخلي والتثبيت
  static Future<void> _downloadAndInstall(String url, Function(double) onProgress) async {
    try {
      // تحديد مسار آمن للحفظ داخل الجهاز
      Directory? dir = await getExternalStorageDirectory();
      String filePath = "${dir!.path}/app_update.apk";

      // بدء التحميل عبر Dio
      Dio dio = Dio();
      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
      );

      // بعد اكتمال التحميل، نقوم بفتح الملف لبدء التثبيت
      print("تم التحميل إلى: $filePath");
      final result = await OpenFilex.open(filePath);

      if (result.type != ResultType.done) {
        print("حدث خطأ أثناء فتح الـ APK: ${result.message}");
      }
    } catch (e) {
      print("خطأ أثناء التحميل: $e");
    }
  }
}