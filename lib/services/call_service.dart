import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart'; // 📦 [جديد]: مكتبة تشغيل الصوتيات

// ==========================================
// 🔑 إعدادات حساب Agora (ديناميكي)
// ==========================================
class AgoraConfig {
  static const String appId = "221c0d1959d24229b3476970d89c41ad";
  static const String tempToken = ""; // فارغ لأننا نستخدم النظام الديناميكي
  static const String channelName = ""; // فارغ
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
  final String callStatus; // 🟢 [جديد]: حالة المكالمة ('calling', 'ringing', 'answered')

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
    this.callStatus = 'calling', // الحالة الافتراضية عند بدء المكالمة
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
      'callStatus': callStatus, // 🟢 [جديد]
      'timestamp': FieldValue.serverTimestamp(),
    };
  }

  factory Call.fromMap(Map<String, dynamic> map) {
    return Call(
      callerId: map['callerId'],
      callerName: map['callerName'],
      callerPic: map['callerPic'] ?? '',
      receiverId: map['receiverId'],
      receiverName: map['receiverName'],
      receiverPic: map['receiverPic'] ?? '',
      channelId: map['channelId'],
      hasDialled: map['hasDialled'],
      isVideo: map['isVideo'] ?? false,
      callStatus: map['callStatus'] ?? 'calling', // 🟢 [جديد]
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
  final String status; // 'missed', 'accepted', 'rejected'
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
      callerId: map['callerId'],
      callerName: map['callerName'],
      callerPic: map['callerPic'] ?? '',
      receiverId: map['receiverId'],
      receiverName: map['receiverName'],
      receiverPic: map['receiverPic'] ?? '',
      channelId: map['channelId'],
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
  static final AudioPlayer audioPlayer = AudioPlayer(); // 🎵 [جديد]: مشغل الصوتيات للمكالمات

  // 1️⃣ بدء مكالمة
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
        callStatus: 'calling', // 🟢 بدء المكالمة
      );
      await _firestore.collection('users').doc(call.callerId).collection('call').doc('current_call').set(callerCall.toMap());

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
        callStatus: 'calling', // 🟢 بدء المكالمة
      );
      await _firestore.collection('users').doc(call.receiverId).collection('call').doc('current_call').set(receiverCall.toMap());

      await saveCallHistory(call: call, status: 'missed');

      // 🎵 تشغيل صوت (توت.. توت..) للمتصل
      playDialingTone();

      return true;
    } catch (e) {
      print("Error making call: $e");
      return false;
    }
  }

  // 2️⃣ إنهاء المكالمة
  static Future<bool> endCall({required String callerId, required String receiverId}) async {
    try {
      await stopAudio(); // 🎵 إيقاف الرنين عند إنهاء المكالمة
      await _firestore.collection('users').doc(callerId).collection('call').doc('current_call').delete();
      await _firestore.collection('users').doc(receiverId).collection('call').doc('current_call').delete();
      return true;
    } catch (e) {
      print("Error ending call: $e");
      return false;
    }
  }

  // 3️⃣ الاستماع للمكالمات الواردة والحالية
  static Stream<DocumentSnapshot> getCallStream(String uid) {
    return _firestore.collection('users').doc(uid).collection('call').doc('current_call').snapshots();
  }

  // 🟢 4️⃣ [جديد]: تحديث حالة المكالمة (للتبديل بين: جارِ الاتصال / يرن / تم الرد)
  static Future<void> updateCallStatus({
    required String callerId,
    required String receiverId,
    required String status,
  }) async {
    try {
      await _firestore.collection('users').doc(callerId).collection('call').doc('current_call').update({'callStatus': status});
      await _firestore.collection('users').doc(receiverId).collection('call').doc('current_call').update({'callStatus': status});
    } catch (e) {
      print("Error updating call status: $e");
    }
  }

  // 🎵 5️⃣ [جديد]: تشغيل نغمة "جارِ الاتصال" للمتصل
  static Future<void> playDialingTone() async {
    await audioPlayer.setReleaseMode(ReleaseMode.loop); // تكرار النغمة
    // يجب توفير ملف صوتي في مجلد assets
    await audioPlayer.play(AssetSource('sounds/dialing.mp3'));
  }

  // 🎵 6️⃣ [جديد]: تشغيل نغمة "رنين" للمستقبل
  static Future<void> playRingingTone() async {
    await audioPlayer.setReleaseMode(ReleaseMode.loop);
    await audioPlayer.play(AssetSource('sounds/ringtone.mp3'));
  }

  // 🎵 7️⃣ [جديد]: إيقاف أي صوت شغال حالياً
  static Future<void> stopAudio() async {
    await audioPlayer.stop();
  }

  // 8️⃣ حفظ أو تحديث حالة سجل المكالمة الدائم
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
      print("Error saving call history: $e");
    }
  }

  // 9️⃣ جلب سجل مكالمات المستخدم
  static Stream<QuerySnapshot> getCallHistoryStream(String uid) {
    return _firestore.collection('users').doc(uid).collection('call_history').orderBy('timestamp', descending: true).snapshots();
  }
}