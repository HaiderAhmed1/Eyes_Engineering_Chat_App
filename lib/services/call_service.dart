import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart'; // من أجل debugPrint

// ==========================================
// 🔑 إعدادات حساب Agora (ديناميكي)
// ==========================================
class AgoraConfig {
  static const String appId = "221c0d1959d24229b3476970d89c41ad";
  static const String tempToken = "";
  static const String channelName = "";
}

// ==========================================
// 📦 نموذج بيانات المكالمة الحالية (للرنين)
// ==========================================
class Call {
  final String callerId;
  final String callerName;
  final String callerPic;
  final String receiverId;
  final String receiverName;
  final String receiverPic;
  final String channelId;
  final bool hasDialled;
  final bool isVideo;
  final String callStatus;

  Call({
    required this.callerId,
    required this.callerName,
    required this.callerPic,
    required this.receiverId,
    required this.receiverName,
    required this.receiverPic,
    required this.channelId,
    required this.hasDialled,
    required this.isVideo,
    this.callStatus = 'calling',
  });

  Map<String, dynamic> toMap() {
    return {
      'callerId': callerId,
      'callerName': callerName,
      'callerPic': callerPic,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'receiverPic': receiverPic,
      'channelId': channelId,
      'hasDialled': hasDialled,
      'isVideo': isVideo,
      'callStatus': callStatus,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }

  factory Call.fromMap(Map<String, dynamic> map) {
    return Call(
      callerId: map['callerId'] ?? '',
      callerName: map['callerName'] ?? '',
      callerPic: map['callerPic'] ?? '',
      receiverId: map['receiverId'] ?? '',
      receiverName: map['receiverName'] ?? '',
      receiverPic: map['receiverPic'] ?? '',
      channelId: map['channelId'] ?? '',
      hasDialled: map['hasDialled'] ?? false,
      isVideo: map['isVideo'] ?? false,
      callStatus: map['callStatus'] ?? 'calling',
    );
  }
}

// ==========================================
// 🗂️ نموذج سجل المكالمات الدائم (Call Log)
// ==========================================
class CallLog {
  final String callerId;
  final String callerName;
  final String callerPic;
  final String receiverId;
  final String receiverName;
  final String receiverPic;
  final String channelId;
  final bool isVideo;
  final String status;
  final Timestamp? timestamp;

  CallLog({
    required this.callerId,
    required this.callerName,
    required this.callerPic,
    required this.receiverId,
    required this.receiverName,
    required this.receiverPic,
    required this.channelId,
    required this.isVideo,
    required this.status,
    this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'callerId': callerId,
      'callerName': callerName,
      'callerPic': callerPic,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'receiverPic': receiverPic,
      'channelId': channelId,
      'isVideo': isVideo,
      'status': status,
      'timestamp': timestamp ?? FieldValue.serverTimestamp(),
    };
  }

  factory CallLog.fromMap(Map<String, dynamic> map) {
    return CallLog(
      callerId: map['callerId'] ?? '',
      callerName: map['callerName'] ?? '',
      callerPic: map['callerPic'] ?? '',
      receiverId: map['receiverId'] ?? '',
      receiverName: map['receiverName'] ?? '',
      receiverPic: map['receiverPic'] ?? '',
      channelId: map['channelId'] ?? '',
      isVideo: map['isVideo'] ?? false,
      status: map['status'] ?? 'missed',
      timestamp: map['timestamp'],
    );
  }
}

// ==========================================
// 🛠️ خدمة إدارة المكالمات (Call Service)
// ==========================================
class CallService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final AudioPlayer audioPlayer = AudioPlayer();

  // 1️⃣ بدء مكالمة (باستخدام Batch لضمان التزامن)
  static Future<bool> makeCall(Call call) async {
    try {
      Call callerCall = Call(
        callerId: call.callerId,
        callerName: call.callerName,
        callerPic: call.callerPic,
        receiverId: call.receiverId,
        receiverName: call.receiverName,
        receiverPic: call.receiverPic,
        channelId: call.channelId,
        hasDialled: true,
        isVideo: call.isVideo,
        callStatus: 'calling',
      );

      Call receiverCall = Call(
        callerId: call.callerId,
        callerName: call.callerName,
        callerPic: call.callerPic,
        receiverId: call.receiverId,
        receiverName: call.receiverName,
        receiverPic: call.receiverPic,
        channelId: call.channelId,
        hasDialled: false,
        isVideo: call.isVideo,
        callStatus: 'calling',
      );

      final batch = _firestore.batch();

      final callerRef = _firestore.collection('users').doc(call.callerId).collection('call').doc('current_call');
      final receiverRef = _firestore.collection('users').doc(call.receiverId).collection('call').doc('current_call');

      batch.set(callerRef, callerCall.toMap());
      batch.set(receiverRef, receiverCall.toMap());

      await batch.commit();

      // إنشاء سجل أولي للمكالمة بحالة missed (يتم تحديثه لاحقاً إذا تم الرد)
      await saveCallHistory(call: call, status: 'missed');

      // 🎵 تشغيل صوت الاتصال للمتصل
      await playDialingTone();

      return true;
    } catch (e) {
      debugPrint("Error making call: $e");
      return false;
    }
  }

  // 2️⃣ إنهاء المكالمة (باستخدام Batch)
  static Future<bool> endCall({required String callerId, required String receiverId}) async {
    try {
      await stopAudio(); // إيقاف أي صوت فوراً وتحرير الموارد

      final batch = _firestore.batch();
      final callerRef = _firestore.collection('users').doc(callerId).collection('call').doc('current_call');
      final receiverRef = _firestore.collection('users').doc(receiverId).collection('call').doc('current_call');

      batch.delete(callerRef);
      batch.delete(receiverRef);

      await batch.commit();
      return true;
    } catch (e) {
      debugPrint("Error ending call: $e");
      return false;
    }
  }

  // 3️⃣ الاستماع للمكالمات
  static Stream<DocumentSnapshot> getCallStream(String uid) {
    return _firestore.collection('users').doc(uid).collection('call').doc('current_call').snapshots();
  }

  // 4️⃣ تحديث حالة المكالمة بآمان (Merge True)
  static Future<void> updateCallStatus({
    required String callerId,
    required String receiverId,
    required String status,
  }) async {
    try {
      final batch = _firestore.batch();
      final callerRef = _firestore.collection('users').doc(callerId).collection('call').doc('current_call');
      final receiverRef = _firestore.collection('users').doc(receiverId).collection('call').doc('current_call');

      batch.set(callerRef, {'callStatus': status}, SetOptions(merge: true));
      batch.set(receiverRef, {'callStatus': status}, SetOptions(merge: true));

      await batch.commit();
    } catch (e) {
      debugPrint("Error updating call status: $e");
    }
  }

  // 🎵 5️⃣ تشغيل نغمة "جارِ الاتصال" للمتصل
  static Future<void> playDialingTone() async {
    try {
      await audioPlayer.setReleaseMode(ReleaseMode.loop);
      await audioPlayer.play(AssetSource('sounds/dialing.mp3'));
    } catch (e) {
      debugPrint("Audio Error (Dialing): $e");
    }
  }

  // 🎵 6️⃣ تشغيل نغمة "رنين" للمستقبل
  static Future<void> playRingingTone() async {
    try {
      await audioPlayer.setReleaseMode(ReleaseMode.loop);
      await audioPlayer.play(AssetSource('sounds/ringtone.mp3'));
    } catch (e) {
      debugPrint("Audio Error (Ringing): $e");
    }
  }

  // 🎵 7️⃣ إيقاف أي صوت شغال وتحرير موارد النظام
  static Future<void> stopAudio() async {
    try {
      if (audioPlayer.state == PlayerState.playing) {
        await audioPlayer.stop();
      }
      // هذا السطر هو الحل الجذري لمشكلة تعليق المايكروفون مع Agora
      await audioPlayer.release();
    } catch (e) {
      debugPrint("Audio Stop Error: $e");
    }
  }

  // 8️⃣ حفظ أو تحديث حالة سجل المكالمة (باستخدام Batch)
  static Future<void> saveCallHistory({required Call call, required String status}) async {
    try {
      final callLog = CallLog(
        callerId: call.callerId,
        callerName: call.callerName,
        callerPic: call.callerPic,
        receiverId: call.receiverId,
        receiverName: call.receiverName,
        receiverPic: call.receiverPic,
        channelId: call.channelId,
        isVideo: call.isVideo,
        status: status,
      );

      final batch = _firestore.batch();
      final callerHistoryRef = _firestore.collection('users').doc(call.callerId).collection('call_history').doc(call.channelId);
      final receiverHistoryRef = _firestore.collection('users').doc(call.receiverId).collection('call_history').doc(call.channelId);

      batch.set(callerHistoryRef, callLog.toMap(), SetOptions(merge: true));
      batch.set(receiverHistoryRef, callLog.toMap(), SetOptions(merge: true));

      await batch.commit();
    } catch (e) {
      debugPrint("Error saving call history: $e");
    }
  }

  // 9️⃣ جلب سجل مكالمات المستخدم
  static Stream<QuerySnapshot> getCallHistoryStream(String uid) {
    return _firestore.collection('users').doc(uid).collection('call_history').orderBy('timestamp', descending: true).snapshots();
  }
}