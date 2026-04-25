import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:chat_app/services/call_service.dart';
import 'package:chat_app/screens/video_call_screen.dart';

class CallHistoryScreen extends StatelessWidget {
  const CallHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
    const Color goldColor = Color(0xFFFFD700);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'سجل المكالمات',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface.withOpacity(0.9),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: CallService.getCallHistoryStream(currentUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: goldColor));
          }

          if (snapshot.hasError) {
            return const Center(child: Text('حدث خطأ أثناء تحميل السجل'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState(theme, goldColor);
          }

          final logs = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: logs.length,
            separatorBuilder: (context, index) => const Divider(height: 20, color: Colors.white10),
            itemBuilder: (context, index) {
              final logData = logs[index].data() as Map<String, dynamic>;
              final CallLog log = CallLog.fromMap(logData);

              // تحديد هل المستخدم هو المتصل أم المستقبل في هذا السجل
              bool isIWasCaller = log.callerId == currentUserId;
              String displayName = isIWasCaller ? log.receiverName : log.callerName;
              String displayPic = isIWasCaller ? log.receiverPic : log.callerPic;
              String targetUserId = isIWasCaller ? log.receiverId : log.callerId;

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _buildProfileImage(displayPic, goldColor, theme),
                title: Text(
                  displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
                subtitle: Row(
                  children: [
                    _getCallStatusIcon(log.status, isIWasCaller),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(log.timestamp),
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: Icon(
                    log.isVideo ? Icons.videocam_outlined : Icons.call_outlined,
                    color: goldColor.withOpacity(0.8),
                  ),
                  onPressed: () => _reDial(context, currentUserId, targetUserId, displayName, displayPic, log.isVideo),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ويدجت حالة السجل الفارغ
  Widget _buildEmptyState(ThemeData theme, Color goldColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.call_missed_outgoing, size: 80, color: goldColor.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            'لا يوجد مكالمات سابقة',
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  // بناء صورة البروفايل مع الإطار الذهبي الصغير
  Widget _buildProfileImage(String imageUrl, Color goldColor, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: goldColor.withOpacity(0.3), width: 1),
      ),
      child: CircleAvatar(
        radius: 26,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
        child: imageUrl.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
      ),
    );
  }

  // أيقونة توضح حالة المكالمة (فائتة، مقبولة، مرفوضة)
  Widget _getCallStatusIcon(String status, bool isIWasCaller) {
    IconData icon;
    Color color;

    if (status == 'accepted') {
      icon = isIWasCaller ? Icons.call_made : Icons.call_received;
      color = Colors.greenAccent;
    } else if (status == 'rejected') {
      icon = Icons.call_end;
      color = Colors.orangeAccent;
    } else {
      // missed
      icon = isIWasCaller ? Icons.call_made : Icons.call_missed;
      color = Colors.redAccent;
    }

    return Icon(icon, size: 14, color: color);
  }

  // تنسيق الوقت والتاريخ
  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "غير معروف";
    DateTime date = timestamp.toDate();
    return intl.DateFormat('yyyy/MM/dd - hh:mm a').format(date);
  }

  // وظيفة معاودة الاتصال مباشرة من السجل
  void _reDial(BuildContext context, String myId, String targetId, String name, String pic, bool isVideo) async {
    // جلب بياناتي الحالية (يُفضل جلبها من Firestore أو State Management)
    // هنا سنستخدم بيانات افتراضية للسرعة، لكن يُفضل تمريرها بشكل كامل
    Call call = Call(
      callerId: myId,
      callerName: "أنا", // سيتم تحديثها من البروفايل تلقائياً في السيرفس
      callerPic: "",
      receiverId: targetId,
      receiverName: name,
      receiverPic: pic,
      channelId: 'call_${DateTime.now().millisecondsSinceEpoch}',
      hasDialled: true,
      isVideo: isVideo,
    );

    bool success = await CallService.makeCall(call);
    if (success && context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => VideoCallScreen(call: call)));
    }
  }
}