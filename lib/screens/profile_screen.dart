import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:intl/intl.dart' as intl;
import 'package:file_picker/file_picker.dart';
import 'package:chat_app/services/chat_service.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;

  const ProfileScreen({
    super.key,
    this.userId,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isUploading = false;
  late String _currentUserId;
  late String _profileUserId;

  late DocumentReference<Map<String, dynamic>> _myUserDocRef;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser!.uid;
    _profileUserId = widget.userId ?? _currentUserId;
    _myUserDocRef = FirebaseFirestore.instance.collection('users').doc(_currentUserId);
  }

  String _formatLastSeen(String isoTimestamp) {
    try {
      final lastSeenTime = DateTime.parse(isoTimestamp);
      final now = DateTime.now();
      final difference = now.difference(lastSeenTime);
      if (difference.inSeconds < 60) return 'آخر ظهور قبل لحظات';
      if (difference.inMinutes < 60) return 'آخر ظهور قبل ${difference.inMinutes} دقيقة';
      if (difference.inHours < 24) return 'آخر ظهور اليوم الساعة ${intl.DateFormat('h:mm a').format(lastSeenTime)}';
      if (difference.inDays == 1) return 'آخر ظهور أمس الساعة ${intl.DateFormat('h:mm a').format(lastSeenTime)}';
      return 'آخر ظهور في ${intl.DateFormat('d/M/y').format(lastSeenTime)}';
    } catch (e) {
      return 'آخر ظهور منذ فترة';
    }
  }

  void _showEditDialog(BuildContext context, String uid, String fieldKey, String currentVal, String title) {
    final controller = TextEditingController(text: currentVal);
    final formKey = GlobalKey<FormState>();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('تغيير $title'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(labelText: title),
          validator: (value) {
            if (value == null || value.trim().isEmpty) { return 'الحقل لا يمكن أن يكون فارغاً.'; }
            if (fieldKey == 'displayName' && value.trim().length < 4) { return 'اسم المستخدم يجب أن يكون 4 أحرف على الأقل.'; }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(child: const Text('إلغاء'), onPressed: () => Navigator.of(ctx).pop()),
        TextButton(child: const Text('حفظ'), onPressed: () async {
          if (formKey.currentState?.validate() ?? false) {
            final newValue = controller.text.trim();
            try {
              await FirebaseFirestore.instance.collection('users').doc(uid).update({fieldKey: newValue});
              if (context.mounted) Navigator.of(ctx).pop();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التحديث: $e')));
              }
            }
          }
        }),
      ],
    ));
  }

  Future<void> _pickAndUploadImage() async {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );

    if (result == null || result.files.single.path == null) return;

    setState(() { _isUploading = true; });

    try {
      final file = File(result.files.single.path!);
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('user_images')
          .child('$currentUserId.jpg');

      await storageRef.putFile(file);
      final imageUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .update({'imageUrl': imageUrl});

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل رفع الصورة: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isUploading = false; });
      }
    }
  }

  void _handleBlockUser() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await ChatService.blockUser(_currentUserId, _profileUserId);
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('تم حظر المستخدم وإخفاء المحادثة'), backgroundColor: Colors.green),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('فشل حظر المستخدم: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _handleUnblockUser() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await ChatService.unblockUser(_currentUserId, _profileUserId);
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('تم إلغاء حظر المستخدم'), backgroundColor: Colors.green),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('فشل إلغاء الحظر: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMe = (_profileUserId == _currentUserId);
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(_profileUserId);
    final theme = Theme.of(context);

    return Scaffold(
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userDocRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('لا يمكن تحميل بيانات المستخدم.'));
          }

          final userData = snapshot.data!.data();
          if (userData == null) return const Center(child: Text('بيانات المستخدم فارغة.'));

          final name = userData['name'] ?? 'لا يوجد اسم';
          final displayName = userData['displayName'] ?? 'لا يوجد اسم مستخدم';
          final phone = userData['phoneNumber'] ?? '';
          final bio = userData['bio'] ?? (isMe ? 'أضف نبذة شخصية...' : 'لا توجد نبذة شخصية.');
          final imageUrl = userData['imageUrl'];

          final bool isOnline = userData['isOnline'] ?? false;
          final String lastSeen = userData['lastSeen'] ?? '';

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 320,
                pinned: true,
                backgroundColor: theme.colorScheme.surface,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              theme.colorScheme.primary.withValues(alpha: 0.8),
                              theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                              theme.colorScheme.surface,
                            ],
                          ),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 40),
                            Stack(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                                        blurRadius: 30,
                                        spreadRadius: 5,
                                      )
                                    ],
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 4),
                                  ),
                                  child: CircleAvatar(
                                    radius: 70,
                                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                    backgroundImage: (imageUrl != null && imageUrl.isNotEmpty)
                                        ? NetworkImage(imageUrl)
                                        : null,
                                    child: (imageUrl == null || imageUrl.isEmpty)
                                        ? Icon(Icons.person, size: 70, color: theme.colorScheme.onSurfaceVariant)
                                        : null,
                                  ),
                                ),
                                if (_isUploading)
                                  const Positioned.fill(
                                    child: CircularProgressIndicator(),
                                  ),
                                if (isMe && !_isUploading)
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: _pickAndUploadImage,
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.secondary,
                                          shape: BoxShape.circle,
                                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                        ),
                                        child: const Icon(Icons.camera_alt, size: 20, color: Colors.black),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              name,
                              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '@$displayName',
                              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      // Status Card
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 10, height: 10,
                              decoration: BoxDecoration(
                                color: isOnline ? Colors.greenAccent : Colors.grey,
                                shape: BoxShape.circle,
                                boxShadow: isOnline ? [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.5), blurRadius: 8)] : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              isOnline ? 'متصل الآن' : _formatLastSeen(lastSeen),
                              style: TextStyle(
                                color: isOnline ? Colors.greenAccent : theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Info Cards
                      _buildInfoCard(
                        context,
                        icon: Icons.phone_iphone,
                        title: 'رقم الهاتف',
                        value: phone.isEmpty ? (isMe ? 'اضغط للإضافة' : 'غير متوفر') : phone,
                        onTap: isMe ? () => _showEditDialog(context, _profileUserId, 'phoneNumber', phone, 'رقم الهاتف') : null,
                        theme: theme,
                      ),

                      _buildInfoCard(
                        context,
                        icon: Icons.info_outline,
                        title: 'نبذة عني',
                        value: bio,
                        onTap: isMe ? () => _showEditDialog(context, _profileUserId, 'bio', bio, 'النبذة') : null,
                        theme: theme,
                        isMultiLine: true,
                      ),

                      if (isMe)
                        _buildInfoCard(
                          context,
                          icon: Icons.edit,
                          title: 'الاسم واسم المستخدم',
                          value: 'تعديل البيانات الأساسية',
                          onTap: () {
                             _showEditDialog(context, _profileUserId, 'name', name, 'الاسم');
                             // يمكن فتح دالة أخرى لاسم المستخدم
                          },
                          theme: theme,
                          highlight: true,
                        ),

                      const SizedBox(height: 30),

                      if (!isMe)
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: _myUserDocRef.snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || !snapshot.data!.exists) {
                              return const SizedBox.shrink();
                            }
                            final myData = snapshot.data!.data();
                            final List<dynamic> blockedList = (myData?['blockedUsers'] as List<dynamic>?) ?? [];
                            final bool isBlocked = blockedList.contains(_profileUserId);

                            return SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: isBlocked ? Colors.green : theme.colorScheme.error),
                                  foregroundColor: isBlocked ? Colors.green : theme.colorScheme.error,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: Icon(isBlocked ? Icons.gpp_good : Icons.block),
                                label: Text(isBlocked ? 'إلغاء الحظر' : 'حظر المستخدم'),
                                onPressed: isBlocked ? _handleUnblockUser : _handleBlockUser,
                              ),
                            );
                          },
                        ),
                        
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    VoidCallback? onTap,
    required ThemeData theme,
    bool isMultiLine = false,
    bool highlight = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: highlight ? theme.colorScheme.primary.withValues(alpha: 0.1) : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: highlight ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: highlight ? Colors.white : theme.colorScheme.primary),
        ),
        title: Text(title, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
        subtitle: Text(
          value,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          maxLines: isMultiLine ? 3 : 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: onTap != null ? Icon(Icons.arrow_forward_ios, size: 14, color: theme.colorScheme.onSurfaceVariant) : null,
        onTap: onTap,
      ),
    );
  }
}
