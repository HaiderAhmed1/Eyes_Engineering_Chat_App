import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:permission_handler/permission_handler.dart';

class ChatFeatures {
  
  // اللون الذهبي المعتمد في التطبيق
  static const Color _goldColor = Color(0xFFFFD700);

  // --- 1. قائمة المرفقات المطورة (Legendary Bottom Sheet) ---
  static void showAttachmentMenu(
      BuildContext context, {
        required Function(File file) onImagePicked,
        required Function(File file) onVideoPicked,
        required Function(PlatformFile file) onFilePicked,
        VoidCallback? onLocationPressed, // خيار إضافي للمستقبل
      }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _buildGlassBottomSheet(
        ctx,
        onImagePicked,
        onVideoPicked,
        onFilePicked,
        onLocationPressed,
      ),
    );
  }

  static Widget _buildGlassBottomSheet(
      BuildContext context,
      Function(File) onImagePicked,
      Function(File) onVideoPicked,
      Function(PlatformFile) onFilePicked,
      VoidCallback? onLocationPressed,
      ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(
          top: BorderSide(color: _goldColor.withValues(alpha: 0.3), width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: _goldColor.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // مقبض السحب
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: theme.dividerColor.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 24),
          
          Text(
            'مشاركة محتوى',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 32),
          
          // شبكة الخيارات
          Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: [
              _buildLegendaryOption(
                context,
                icon: Icons.image_rounded,
                label: 'المعرض',
                color: Colors.purpleAccent,
                gradient: const LinearGradient(colors: [Colors.purpleAccent, Colors.deepPurple]),
                onTap: () => _handleMediaPick(context, ImageSource.gallery, false, onImagePicked, onVideoPicked),
              ),
              _buildLegendaryOption(
                context,
                icon: Icons.camera_alt_rounded,
                label: 'كاميرا',
                color: Colors.redAccent,
                gradient: const LinearGradient(colors: [Colors.redAccent, Colors.orangeAccent]),
                onTap: () => _handleMediaPick(context, ImageSource.camera, false, onImagePicked, onVideoPicked),
              ),
              _buildLegendaryOption(
                context,
                icon: Icons.videocam_rounded,
                label: 'فيديو',
                color: Colors.blueAccent,
                gradient: const LinearGradient(colors: [Colors.blueAccent, Colors.cyan]),
                onTap: () => _handleMediaPick(context, ImageSource.gallery, true, onImagePicked, onVideoPicked),
              ),
              _buildLegendaryOption(
                context,
                icon: Icons.insert_drive_file_rounded,
                label: 'ملف',
                color: Colors.orange,
                gradient: const LinearGradient(colors: [Colors.orange, Colors.amber]),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickFile(context, onFilePicked);
                },
              ),
              // يمكن إضافة المزيد هنا بسهولة
              if (onLocationPressed != null)
                _buildLegendaryOption(
                  context,
                  icon: Icons.location_on_rounded,
                  label: 'موقع',
                  color: Colors.green,
                  gradient: const LinearGradient(colors: [Colors.green, Colors.teal]),
                  onTap: () {
                     Navigator.pop(context);
                     onLocationPressed();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _buildLegendaryOption(
      BuildContext context, {
        required IconData icon,
        required String label,
        required Color color,
        required LinearGradient gradient,
        required VoidCallback onTap,
      }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      splashColor: color.withValues(alpha: 0.2),
      highlightColor: color.withValues(alpha: 0.1),
      child: Container(
        width: 75,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // استخدمنا لون الخلفية بشفافية بدلاً من التدرج لتجنب التعقيد
                color: color.withValues(alpha: 0.1),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
                border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // --- 2. منطق اختيار الصور والفيديو (مع الأذونات) ---
  static Future<void> _handleMediaPick(
      BuildContext context,
      ImageSource source,
      bool isVideo,
      Function(File) onImagePicked,
      Function(File) onVideoPicked,
      ) async {
    
    Navigator.pop(context); // إغلاق القائمة أولاً

    // التحقق من الأذونات
    PermissionStatus status;
    if (source == ImageSource.camera) {
      status = await Permission.camera.request();
    } else {
      // في أندرويد 13+ نستخدم photos/videos، في القديم storage
      if (Platform.isAndroid) {
        // تبسيط: طلب storage بشكل عام أو photos حسب الإصدار
        // هنا نعتمد على image_picker لطلب الأذن تلقائياً في الغالب،
        // ولكن يفضل التحقق الصريح.
        // سنترك المكتبة تتعامل معها لتجنب التعقيد الزائد إلا إذا فشلت.
        // لكن سنجرب طلب الكاميرا فقط بشكل صريح لأنه حساس.
        status = PermissionStatus.granted; 
      } else {
        status = await Permission.photos.request();
      }
    }

    if (source == ImageSource.camera && status.isDenied) {
       if (context.mounted) {
         _showPermissionError(context, 'نحتاج إذن الكاميرا لالتقاط الصور.');
       }
       return;
    }

    try {
      final picker = ImagePicker();
      XFile? pickedFile;
      
      if (isVideo) {
        pickedFile = await picker.pickVideo(
            source: source,
            maxDuration: const Duration(minutes: 5), // حد أقصى للفيديو
        );
      } else {
        pickedFile = await picker.pickImage(
            source: source,
            imageQuality: 80, // جودة أفضل قليلاً من 70
            maxWidth: 1920,   // تحجيم الصور الكبيرة جداً
        );
      }

      if (pickedFile != null) {
        final file = File(pickedFile.path);
        if (isVideo) {
          onVideoPicked(file);
        } else {
          onImagePicked(file);
        }
      }
    } catch (e) {
      debugPrint("Error picking media: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("حدث خطأ: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- 3. منطق اختيار الملفات ---
  static Future<void> _pickFile(BuildContext context, Function(PlatformFile) onFilePicked) async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.isNotEmpty) {
        // يمكن هنا إضافة تحقق من الحجم مثلاً (مثلاً 50 ميجا)
        final file = result.files.first;
        if (file.size > 50 * 1024 * 1024) { // 50 MB
           if (context.mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text("الملف كبير جداً (الحد الأقصى 50 ميجابايت)")),
             );
           }
           return;
        }
        onFilePicked(file);
      }
    } catch (e) {
      debugPrint("Error picking file: $e");
    }
  }
  
  static void _showPermissionError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'الإعدادات',
          onPressed: () => openAppSettings(),
        ),
      ),
    );
  }

  // --- 4. فواصل التواريخ الذكية (Smart Date Headers) ---
  static String formatDateHeader(DateTime date, {String locale = 'ar'}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToCheck = DateTime(date.year, date.month, date.day);

    if (dateToCheck == today) {
      return 'اليوم';
    } else if (dateToCheck == yesterday) {
      return 'أمس';
    } else {
      // إذا كان في نفس الأسبوع، اعرض اسم اليوم
      final difference = today.difference(dateToCheck).inDays;
      if (difference < 7) {
        return intl.DateFormat('EEEE', locale).format(date); // السبت، الأحد...
      }
      // وإلا اعرض التاريخ الكامل
      return intl.DateFormat('d MMMM yyyy', locale).format(date);
    }
  }

  static bool isSameDay(int timestamp1, int timestamp2) {
    final date1 = DateTime.fromMillisecondsSinceEpoch(timestamp1);
    final date2 = DateTime.fromMillisecondsSinceEpoch(timestamp2);
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}
