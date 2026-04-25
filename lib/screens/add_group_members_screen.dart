import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // (جديد)

// (ويدجت UserProfile - لا تتغير)
class UserProfile {
  final String uid;
  final String name;
  final String username;
  UserProfile({required this.uid, required this.name, required this.username});
}

class AddGroupMembersScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final Map<String, dynamic> currentMembers; // (هذه لا تزال تُمرر كما هي)

  const AddGroupMembersScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.currentMembers,
  });

  @override
  State<AddGroupMembersScreen> createState() => _AddGroupMembersScreenState();
}

class _AddGroupMembersScreenState extends State<AddGroupMembersScreen> {
  final _searchController = TextEditingController();
  // (جديد) مراجع Firestore
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  bool _isLoading = false;

  List<UserProfile> _searchResults = [];
  final Map<String, UserProfile> _selectedMembers = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // (محدث) دالة البحث (مع فلترة الأعضاء الحاليين)
  void _searchForUser(String username) async {
    if (username.isEmpty) {
      setState(() { _searchResults = []; });
      return;
    }
    setState(() { _isLoading = true; });

    try {
      // (جديد) استعلام Firestore
      final query = _firestore
          .collection('users')
          .where('displayName', isGreaterThanOrEqualTo: username)
          .where('displayName', isLessThanOrEqualTo: '$username\uf8ff')
          .limit(10);

      final snapshot = await query.get();
      final List<UserProfile> results = [];

      if (snapshot.docs.isNotEmpty) {
        for (var doc in snapshot.docs) {
          final userMap = doc.data();
          final uid = userMap['uid'];

          if (uid == _auth.currentUser!.uid) continue;
          // (مهم) فلترة الأعضاء الموجودين حالياً
          if (widget.currentMembers.containsKey(uid)) continue;

          results.add(UserProfile(
            uid: uid,
            name: userMap['name'] ?? 'لا يوجد اسم',
            username: userMap['displayName'] ?? 'لا يوجد اسم مستخدم',
          ));
        }
      }
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (e) {
      // print('خطأ في البحث: $e');
      setState(() { _isLoading = false; });
    }
  }

  // (دالة إضافة أو إزالة عضو - لا تتغير)
  void _toggleMember(UserProfile user) {
    setState(() {
      if (_selectedMembers.containsKey(user.uid)) {
        _selectedMembers.remove(user.uid);
      } else {
        _selectedMembers[user.uid] = user;
      }
    });
  }

  // (مهم جداً) دالة لإضافة الأعضاء المختارين للمجموعة
  void _addMembersToGroup() async {
    if (_selectedMembers.isEmpty) {
      _showErrorSnackBar('الرجاء اختيار أعضاء لإضافتهم');
      return;
    }
    setState(() { _isLoading = true; });

    try {
      // (جديد) مرجع مستند المجموعة
      final groupDocRef = _firestore.collection('groups').doc(widget.groupId);

      // 1. تحضير خريطة التحديث للمستند الرئيسي
      // (جديد) نستخدم "dot notation" لتحديث حقول داخل خريطة
      Map<String, dynamic> membersUpdateMap = {};
      Map<String, String> newMembersMap = {}; // (للاستخدام في الخطوة 2)

      for (var member in _selectedMembers.values) {
        membersUpdateMap['members.${member.uid}'] = 'member';
        newMembersMap[member.uid] = 'member';
      }

      // (جديد) تحديث مستند المجموعة الرئيسي
      await groupDocRef.update(membersUpdateMap);

      // 2. تحضير بيانات المجموعة لإضافتها للأعضاء الجدد
      // (نحتاج لجلب البيانات الحالية للمجموعة مثل الصورة)
      final groupSnapshot = await groupDocRef.get();
      final groupData = groupSnapshot.data();
      final groupInfo = groupData?['info'] as Map<String, dynamic>?;
      final imageUrl = groupInfo?['imageUrl'];

      final groupChatInfo = {
        'name': widget.groupName,
        'chatId': widget.groupId,
        'isGroup': true,
        'lastMessage': 'تمت إضافتك للمجموعة',
        'lastMessageTimestamp': DateTime.now().millisecondsSinceEpoch,
        'imageUrl': imageUrl, // (جديد)
        'unreadCount': 0, // (جديد)
      };

      // (جديد) استخدام WriteBatch لإضافة المجموعة للأعضاء الجدد
      final batch = _firestore.batch();
      for (var memberId in newMembersMap.keys) {
        final memberGroupDoc = _firestore
            .collection('users')
            .doc(memberId)
            .collection('my_groups')
            .doc(widget.groupId);

        batch.set(memberGroupDoc, groupChatInfo);
      }

      await batch.commit(); // تنفيذ الدفعة

      if (mounted) {
        Navigator.of(context).pop();
      }

    } catch (e) {
      _showErrorSnackBar('فشل إضافة الأعضاء: $e');
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  // (دالة عرض الخطأ - لا تتغير)
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // (دالة build - لا تتغير)
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة أعضاء جدد'),
      ),
      body: Column(
        children: [
          if (_selectedMembers.isNotEmpty)
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _selectedMembers.values.map((user) {
                  return Chip(
                    label: Text(user.name),
                    avatar: CircleAvatar(child: Text(user.name[0])),
                    onDeleted: () => _toggleMember(user),
                  );
                }).toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'البحث عن أعضاء (باسم المستخدم @)',
                prefixText: '@',
              ),
              onChanged: _searchForUser,
            ),
          ),
          Expanded(
            child: _isLoading && _searchResults.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                ? const Center(child: Text('لا توجد نتائج (أو تمت إضافتهم)'))
                : ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (ctx, index) {
                final user = _searchResults[index];
                final isSelected = _selectedMembers.containsKey(user.uid);

                return ListTile(
                  leading: CircleAvatar(child: Text(user.name[0])),
                  title: Text(user.name),
                  subtitle: Text('@${user.username}'),
                  trailing: Checkbox(
                    value: isSelected,
                    onChanged: (val) => _toggleMember(user),
                  ),
                  onTap: () => _toggleMember(user),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: (_isLoading || _selectedMembers.isEmpty) ? null : _addMembersToGroup,
        backgroundColor: (_selectedMembers.isEmpty)
            ? Colors.grey
            : theme.colorScheme.secondary,
        foregroundColor: Colors.black,
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.add),
      ),
    );
  }
}