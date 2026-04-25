import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:video_compress/video_compress.dart';

class ChatSender {
  static final _storage = FirebaseStorage.instance;
  static final _firestore = FirebaseFirestore.instance;

  // --- 1. التحديث الذري للمحادثات (Atomic Chat List Update) ---
  // تم تحسينها لتعمل كجزء من عملية دفع واحدة (Batch) إذا أمكن، أو بشكل مستقل وموثوق.
  static Future<void> updateChatList({
    required String myId,
    required String targetId,
    required String lastMessage,
    required String myName,
    required String targetName,
    String? myImage,
    String? targetImage,
    required String chatId,
    bool isGroup = false,
  }) async {
    final timestamp = FieldValue.serverTimestamp();
    final batch = _firestore.batch();

    // تحديث للمرسل (أنا)
    // نستخدم set مع merge لضمان عدم مسح البيانات الأخرى
    final myChatRef = _firestore.collection('users').doc(myId).collection(isGroup ? 'my_groups' : 'my_chats').doc(targetId);
    batch.set(myChatRef, {
      'chatId': chatId,
      'name': targetName,
      'imageUrl': targetImage,
      'lastMessage': lastMessage,
      'lastMessageTimestamp': timestamp,
      'lastMessageSenderId': myId,
      'isRead': true, // أنا المرسل
      'isGroup': isGroup,
      'isMuted': false, // افتراضي
    }, SetOptions(merge: true));

    // تحديث للمستلم (الطرف الآخر) إذا لم تكن مجموعة
    // في المجموعات، المنطق يختلف قليلاً (يتم التحديث لكل الأعضاء عبر Cloud Function عادةً، أو هنا بحلقة تكرار إذا العدد صغير)
    // سنفترض هنا المحادثات الفردية أو أن caller يتعامل مع المجموعات بشكل منفصل.
    if (!isGroup) {
      final targetChatRef = _firestore.collection('users').doc(targetId).collection('my_chats').doc(myId);
      batch.set(targetChatRef, {
        'chatId': chatId,
        'name': myName,
        'imageUrl': myImage,
        'lastMessage': lastMessage,
        'lastMessageTimestamp': timestamp,
        'lastMessageSenderId': myId,
        'isRead': false,
        'unreadCount': FieldValue.increment(1),
        'isGroup': false,
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  // --- 2. إرسال رسالة نصية متطور ---
  static Future<void> sendTextMessage({
    required DocumentReference chatDocRef,
    required String text,
    required String senderId,
    required String senderName,
    String? senderImage,
    Map<String, dynamic>? replyTo,
  }) async {
    if (text.trim().isEmpty) return;

    final messageData = _createBaseMessageData(
      type: 'text',
      senderId: senderId,
      senderName: senderName,
      senderImage: senderImage,
      replyTo: replyTo,
    );
    messageData['text'] = text.trim();

    // استخدام Batch لضمان إضافة الرسالة وتحديث "آخر رسالة" معاً
    final batch = _firestore.batch();
    final newMessageRef = chatDocRef.collection('messages').doc();
    
    batch.set(newMessageRef, messageData);
    
    batch.set(chatDocRef, {
      'lastMessage': text.trim(),
      'lastMessageTimestamp': FieldValue.serverTimestamp(),
      'lastMessageSenderId': senderId,
      'lastMessageType': 'text',
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // --- 3. إرسال ملف (صور، فيديو، صوت) مع إدارة الرفع ---
  static Future<void> sendFileMessage({
    required DocumentReference chatDocRef,
    required File file,
    required String type, // 'image', 'video', 'audio', 'file'
    required String senderId,
    required String senderName,
    String? senderImage,
    String? fileName,
    int? duration,
    Map<String, dynamic>? extraFields,
    Map<String, dynamic>? replyTo,
    Function(double progress)? onProgress, // Callback للتقدم
  }) async {
    try {
      File fileToUpload = file;

      // --- ضغط الفيديو (Video Compression) ---
      if (type == 'video') {
        try {
          // ضغط بجودة متوسطة (مناسب جداً لتطبيقات الدردشة - يقلل الحجم 80-90%)
          final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
            file.path,
            quality: VideoQuality.MediumQuality, 
            deleteOrigin: false, 
            includeAudio: true,
          );
          
          if (mediaInfo != null && mediaInfo.file != null) {
            fileToUpload = mediaInfo.file!;
            debugPrint("Original size: ${await file.length()}, Compressed: ${await fileToUpload.length()}");
          }
        } catch (e) {
          debugPrint("Video compression failed: $e");
          // في حال الفشل، نرفع الملف الأصلي
        }
      }

      // 1. الرفع
      final ext = p.extension(fileToUpload.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref().child('chat_files/${type}s/${senderId}_$timestamp$ext');
      
      // إمكانية إضافة metadata للملف
      final metadata = SettableMetadata(
        contentType: _getContentType(type, ext),
        customMetadata: {
          'senderId': senderId,
          'originalName': fileName ?? 'unknown',
        },
      );

      final uploadTask = ref.putFile(fileToUpload, metadata);
      
      // الاستماع لتقدم الرفع
      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((event) {
           if (event.totalBytes > 0) {
             double progress = event.bytesTransferred / event.totalBytes;
             onProgress(progress);
           }
        });
      }

      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();
      
      // تنظيف ذاكرة الكاش للفيديو المضغوط (اختياري ولكن جيد للأداء)
      if (type == 'video' && fileToUpload.path != file.path) {
         // VideoCompress.deleteAllCache(); // يمكن استدعاؤها لاحقاً عند الخروج أو بشكل دوري
      }

      // 2. تجهيز نص الرسالة للعرض في القائمة
      String msgText = _getMediaMessageText(type);

      // 3. تجهيز بيانات الرسالة
      final messageData = _createBaseMessageData(
        type: type,
        senderId: senderId,
        senderName: senderName,
        senderImage: senderImage,
        replyTo: replyTo,
      );
      
      messageData.addAll({
        'text': '', // الوسائط عادة لا تملك نصاً رئيسياً، أو يمكن إضافته كـ caption
        'fileUrl': url,
        'fileName': fileName ?? p.basename(file.path),
        'fileSize': await fileToUpload.length(), // إضافة حجم الملف
      });

      if (duration != null) messageData['duration'] = duration;
      if (extraFields != null) messageData.addAll(extraFields);

      // 4. الحفظ في قاعدة البيانات (Atomic Batch)
      final batch = _firestore.batch();
      final newMessageRef = chatDocRef.collection('messages').doc();

      batch.set(newMessageRef, messageData);
      
      batch.set(chatDocRef, {
        'lastMessage': msgText,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'lastMessageSenderId': senderId,
        'lastMessageType': type,
      }, SetOptions(merge: true));

      await batch.commit();

    } catch (e) {
      debugPrint("Error sending file message: $e");
      rethrow; // إعادة رمي الخطأ ليتم التعامل معه في الواجهة (إخفاء التحميل مثلاً)
    }
  }

  // --- مساعدات (Helpers) ---

  static Map<String, dynamic> _createBaseMessageData({
    required String type,
    required String senderId,
    required String senderName,
    String? senderImage,
    Map<String, dynamic>? replyTo,
  }) {
    return {
      'type': type,
      'senderId': senderId,
      'senderName': senderName,
      'senderImage': senderImage,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent', // sent, delivered, read
      'isRead': false,
      'isEdited': false,
      'isForwarded': false,
      if (replyTo != null) 'replyTo': replyTo,
    };
  }

  static String _getContentType(String type, String ext) {
    switch (type) {
      case 'image': return 'image/${ext.replaceAll('.', '')}';
      case 'video': return 'video/${ext.replaceAll('.', '')}';
      case 'audio': return 'audio/${ext.replaceAll('.', '')}';
      default: return 'application/octet-stream';
    }
  }

  static String _getMediaMessageText(String type) {
    switch (type) {
      case 'image': return '📷 صورة';
      case 'video': return '🎥 فيديو';
      case 'audio': return '🎤 رسالة صوتية';
      case 'file': return '📎 ملف';
      case 'location': return '📍 موقع';
      case 'contact': return '👤 جهة اتصال';
      default: return 'مرفق';
    }
  }
}
