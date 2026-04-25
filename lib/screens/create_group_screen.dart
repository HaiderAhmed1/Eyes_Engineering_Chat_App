import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// (ويدجت UserProfile - لا تتغير)
class UserProfile {
  final String uid;
  final String name;
  final String username;
  UserProfile({required this.uid, required this.name, required this.username});
}

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _groupNameController = TextEditingController();
  final _groupHandleController = TextEditingController(); // (جديد)
  final _searchController = TextEditingController();

  // (جديد) حالة الخصوصية
  String _privacy = 'open'; // القيم: 'open', 'request', 'closed'

  // (جديد) مراجع Firestore
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  bool _isLoading = false;

  List<UserProfile> _searchResults = [];
  final Map<String, UserProfile> _selectedMembers = {};

  @override
  void dispose() {
    _groupNameController.dispose();
    _groupHandleController.dispose(); // (جديد)
    _searchController.dispose();
    super.dispose();
  }

  // (محدث) دالة البحث عن المستخدمين
  void _searchForUser(String username) async {
    if (username.isEmpty) {
      setState(() { _searchResults = []; });
      return;
    }

    setState(() { _isLoading = true; });

    try {
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
          if (userMap['uid'] == _auth.currentUser!.uid) continue;

          results.add(UserProfile(
            uid: userMap['uid'],
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
      setState(() { _isLoading = false; });
    }
  }

  void _toggleMember(UserProfile user) {
    setState(() {
      if (_selectedMembers.containsKey(user.uid)) {
        _selectedMembers.remove(user.uid);
      } else {
        _selectedMembers[user.uid] = user;
      }
    });
  }

  // (محدث) دالة إنشاء المجموعة
  void _createGroup() async {
    final groupName = _groupNameController.text.trim();
    final groupHandle = _groupHandleController.text.trim(); // (جديد)

    if (groupName.isEmpty) {
      _showErrorSnackBar('الرجاء إدخال اسم للمجموعة');
      return;
    }
    if (groupHandle.isEmpty) {
      _showErrorSnackBar('الرجاء إدخال معرف (Handle) للمجموعة');
      return;
    }
    // التحقق من صحة المعرف (حروف وأرقام فقط مثلاً)
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(groupHandle)) {
      _showErrorSnackBar('المعرف يجب أن يحتوي على أحرف إنجليزية وأرقام و _ فقط');
      return;
    }

    if (_selectedMembers.isEmpty) {
      _showErrorSnackBar('الرجاء إضافة عضو واحد على الأقل');
      return;
    }

    setState(() { _isLoading = true; });

    try {
      // (جديد) التحقق من تفرد المعرف (Handle)
      final handleQuery = await _firestore
          .collection('groups')
          .where('info.handle', isEqualTo: groupHandle)
          .limit(1)
          .get();

      if (handleQuery.docs.isNotEmpty) {
        _showErrorSnackBar('هذا المعرف مستخدم بالفعل، يرجى اختيار غيره');
        setState(() { _isLoading = false; });
        return;
      }

      final currentUser = _auth.currentUser!;
      final newGroupRef = _firestore.collection('groups').doc();
      final groupId = newGroupRef.id;

      Map<String, String> membersMap = {};
      membersMap[currentUser.uid] = 'admin';
      for (var member in _selectedMembers.values) {
        membersMap[member.uid] = 'member';
      }

      final nowForSort = DateTime.now().millisecondsSinceEpoch;

      // 3. كتابة بيانات المجموعة
      await newGroupRef.set({
        'info': {
          'name': groupName,
          'handle': groupHandle, // (جديد)
          'privacy': _privacy,   // (جديد)
          'createdAt': FieldValue.serverTimestamp(),
          'creator': currentUser.uid,
          'groupId': groupId,
          'imageUrl': null,
        },
        'members': membersMap,
        'lastMessage': 'تم إنشاء المجموعة',
        'lastMessageTimestamp': nowForSort,
      });

      final batch = _firestore.batch();
      final groupChatInfo = {
        'name': groupName,
        'chatId': groupId,
        'isGroup': true,
        'lastMessage': 'تم إنشاء المجموعة',
        'lastMessageTimestamp': nowForSort,
        'imageUrl': null,
        'unreadCount': 0,
      };

      for (var memberId in membersMap.keys) {
        final memberGroupDoc = _firestore
            .collection('users')
            .doc(memberId)
            .collection('my_groups')
            .doc(groupId);

        batch.set(memberGroupDoc, groupChatInfo);
      }

      await batch.commit();

      if (mounted) {
        Navigator.of(context).pop();
      }

    } catch (e) {
      _showErrorSnackBar('فشل إنشاء المجموعة: $e');
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('إنشاء مجموعة جديدة'),
      ),
      body: SingleChildScrollView( // (تعديل) لدعم التمرير
        child: Column(
          children: [
            const SizedBox(height: 24),
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.groups_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextField(
                controller: _groupNameController,
                decoration: InputDecoration(
                  labelText: 'اسم المجموعة',
                  prefixIcon: const Icon(Icons.group),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // (جديد) حقل المعرف
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextField(
                controller: _groupHandleController,
                decoration: InputDecoration(
                  labelText: 'معرف المجموعة (Handle)',
                  prefixText: '@',
                  prefixIcon: const Icon(Icons.link),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  helperText: 'يستخدم للبحث عن المجموعة',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // (جديد) قائمة الخصوصية
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: DropdownButtonFormField<String>(
                initialValue: _privacy,
                decoration: InputDecoration(
                  labelText: 'خصوصية الانضمام',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'open',
                    child: Text('مفتوح للجميع (Open)'),
                  ),
                  DropdownMenuItem(
                    value: 'request',
                    child: Text('طلب انضمام (Request to Join)'),
                  ),
                  DropdownMenuItem(
                    value: 'closed',
                    child: Text('مغلقة/خاصة (Closed)'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _privacy = val);
                  }
                },
              ),
            ),

            const SizedBox(height: 24),

            // --- عرض الأعضاء المختارين ---
            if (_selectedMembers.isNotEmpty)
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _selectedMembers.values.map((user) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Chip(
                        label: Text(user.name),
                        avatar: CircleAvatar(child: Text(user.name.isNotEmpty ? user.name[0] : '?')),
                        onDeleted: () => _toggleMember(user),
                        backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.2),
                        side: BorderSide.none,
                      ),
                    );
                  }).toList(),
                ),
              ),

            // --- شريط البحث ---
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'إضافة أعضاء (بحث بالاسم أو المعرف)',
                  prefixIcon: const Icon(Icons.person_add_alt),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                ),
                onChanged: _searchForUser,
              ),
            ),

            // --- نتائج البحث ---
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_searchResults.isNotEmpty)
              ListView.builder(
                shrinkWrap: true, // مهم داخل SingleChildScrollView
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _searchResults.length,
                itemBuilder: (ctx, index) {
                  final user = _searchResults[index];
                  final isSelected = _selectedMembers.containsKey(user.uid);

                  return ListTile(
                    leading: CircleAvatar(child: Text(user.name.isNotEmpty ? user.name[0] : '?')),
                    title: Text(user.name),
                    subtitle: Text('@${user.username}'),
                    trailing: Checkbox(
                      value: isSelected,
                      onChanged: (val) => _toggleMember(user),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    onTap: () => _toggleMember(user),
                  );
                },
              )
            else if (_searchController.text.isNotEmpty)
                Center(child: Text('لا توجد نتائج', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)))),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_isLoading || _selectedMembers.isEmpty) ? null : _createGroup,
        backgroundColor: (_selectedMembers.isEmpty)
            ? theme.disabledColor
            : theme.colorScheme.primary,
        foregroundColor: Colors.white,
        icon: _isLoading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.check),
        label: Text(_isLoading ? 'جاري الإنشاء...' : 'إنشاء المجموعة'),
      ),
    );
  }
}
