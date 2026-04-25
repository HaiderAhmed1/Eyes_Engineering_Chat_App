import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:chat_app/screens/add_group_members_screen.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:chat_app/services/chat_service.dart';

class GroupMember {
  final String uid;
  String role;
  String name;

  GroupMember({required this.uid, required this.role, this.name = '...'});
}

class GroupInfoScreen extends StatefulWidget {
  final String groupId;
  final String groupName; 

  const GroupInfoScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  late final DocumentReference<Map<String, dynamic>> _groupDocRef;
  late final CollectionReference<Map<String, dynamic>> _usersCollection;

  late String _currentUid;
  List<GroupMember> _membersList = [];
  String _myRole = 'member';
  Map<String, dynamic> _currentMembersMap = {}; 
  String _currentGroupName = '';
  
  String? _currentGroupHandle;
  String _currentPrivacy = 'open';

  String? _groupImageUrl;
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _currentUid = _auth.currentUser!.uid;
    _currentGroupName = widget.groupName;

    _groupDocRef = _firestore.collection('groups').doc(widget.groupId);
    _usersCollection = _firestore.collection('users');
    
    _checkIfManager();
  }
  
  void _checkIfManager() async {
    final doc = await _usersCollection.doc(_currentUid).get();
    if (doc.exists && mounted) {
      final phone = doc.data()?['phoneNumber'];
      if (phone == '07858254814') {
        setState(() {
          // نعطي صلاحيات الأدمن لهذا الرقم بغض النظر عن دوره المسجل
          _myRole = 'admin'; 
        });
      }
    }
  }

  Future<void> _fetchMemberNames(Map<String, dynamic> membersData) async {
    final List<GroupMember> loadedMembers = [];

    // إذا لم نكن قد حددنا الدور كـ admin عبر _checkIfManager، نأخذ الدور الطبيعي
    if (_myRole != 'admin') {
      if (membersData[_currentUid] != null) {
        _myRole = membersData[_currentUid] as String;
      }
    }

    for (var entry in membersData.entries) {
      loadedMembers.add(GroupMember(uid: entry.key, role: entry.value as String));
    }

    for (var member in loadedMembers) {
      try {
        final nameSnapshot = await _usersCollection.doc(member.uid).get();
        if (nameSnapshot.exists) {
          member.name = nameSnapshot.data()?['name'] ?? 'مستخدم';
        }
      } catch (e) {
        member.name = 'مستخدم غير معروف';
      }
    }

    if (mounted) {
      setState(() {
        _membersList = loadedMembers;
      });
    }
  }

  String _translateRole(String role) {
    if (role == 'admin') return 'مدير';
    if (role == 'supervisor') return 'مشرف';
    return 'عضو';
  }

  String _translatePrivacy(String privacy) {
    if (privacy == 'open') return 'مفتوح للجميع';
    if (privacy == 'request') return 'طلب انضمام';
    if (privacy == 'closed') return 'مغلقة (خاصة)';
    return privacy;
  }

  Icon _getRoleIcon(String role, ThemeData theme) {
    if (role == 'admin') {
      return Icon(Icons.shield_rounded, color: theme.colorScheme.secondary, size: 16);
    }
    if (role == 'supervisor') {
      return Icon(Icons.security_rounded, color: Colors.blue[300], size: 16);
    }
    return const Icon(Icons.person, color: Colors.grey, size: 16);
  }

  void _showMemberOptions(GroupMember member) {
    if (member.uid == _currentUid) return;
    bool canManage = (_myRole == 'admin' && member.role != 'admin');
    bool supervisorCanManage = (_myRole == 'supervisor' && member.role == 'member');
    if (!canManage && !supervisorCanManage) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.info),
              title: Text('${member.name} (${_translateRole(member.role)})'),
            ),
            const Divider(),
            if (member.role == 'member' && _myRole == 'admin')
              ListTile(
                leading: const Icon(Icons.arrow_upward),
                title: const Text('ترقية إلى مشرف'),
                onTap: () {
                  _updateRole(member.uid, 'supervisor');
                  Navigator.of(ctx).pop();
                },
              ),
            if (member.role == 'supervisor' && _myRole == 'admin')
              ListTile(
                leading: const Icon(Icons.arrow_downward),
                title: const Text('تخفيض إلى عضو'),
                onTap: () {
                  _updateRole(member.uid, 'member');
                  Navigator.of(ctx).pop();
                },
              ),
            ListTile(
              leading: Icon(Icons.remove_circle_outline, color: Colors.red[400]),
              title: Text('إزالة من المجموعة', style: TextStyle(color: Colors.red[400])),
              onTap: () {
                _removeMember(member.uid);
                Navigator.of(ctx).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateRole(String uid, String newRole) async {
    try {
      await _groupDocRef.update({'members.$uid': newRole});
    } catch (e) {
      // print("Failed to update role: $e");
    }
  }

  Future<void> _removeMember(String uid) async {
    try {
      final batch = _firestore.batch();
      batch.update(_groupDocRef, {'members.$uid': FieldValue.delete()});
      final memberGroupDoc = _usersCollection.doc(uid).collection('my_groups').doc(widget.groupId);
      batch.delete(memberGroupDoc);
      await batch.commit();
    } catch (e) {
      // print("Failed to remove member: $e");
    }
  }

  Future<void> _pickAndUploadImage() async {
    if (_myRole != 'admin') return;

    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    setState(() { _isUploadingImage = true; });

    try {
      await ChatService.updateGroupImage(
        groupId: widget.groupId,
        imageFile: file,
        groupDocRef: _groupDocRef,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل رفع الصورة: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isUploadingImage = false; });
      }
    }
  }

  void _showEditGroupNameDialog() {
    final controller = TextEditingController(text: _currentGroupName);
    final formKey = GlobalKey<FormState>();
    
    // Capture context before async gap
    final localContext = context; 

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('تغيير اسم المجموعة'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'الاسم الجديد'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'الاسم لا يمكن أن يكون فارغاً.';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
            TextButton(
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  final newName = controller.text.trim();
                  if (newName == _currentGroupName) {
                    if (localContext.mounted) Navigator.of(localContext).pop();
                    return;
                  }
                  try {
                    await ChatService.updateGroupName(
                      groupId: widget.groupId,
                      newName: newName,
                      groupDocRef: _groupDocRef,
                    );
                    if (localContext.mounted) Navigator.of(localContext).pop();
                  } catch (e) {
                    if (localContext.mounted) {
                      ScaffoldMessenger.of(localContext).showSnackBar(SnackBar(content: Text('فشل التحديث: $e')));
                    }
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
  }

  void _showEditHandleDialog() {
    final controller = TextEditingController(text: _currentGroupHandle);
    final formKey = GlobalKey<FormState>();
    
    // Capture context
    final localContext = context;
    bool isChecking = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('تغيير معرف المجموعة'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'المعرف الجديد',
                        prefixText: '@',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'المعرف مطلوب';
                        if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
                          return 'أحرف إنجليزية وأرقام فقط';
                        }
                        return null;
                      },
                    ),
                    if (isChecking) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
                TextButton(
                  onPressed: isChecking ? null : () async {
                    if (formKey.currentState?.validate() ?? false) {
                      final newHandle = controller.text.trim();
                      if (newHandle == _currentGroupHandle) {
                        if (localContext.mounted) Navigator.of(localContext).pop();
                        return;
                      }

                      setStateDialog(() => isChecking = true);

                      final query = await _firestore.collection('groups')
                          .where('info.handle', isEqualTo: newHandle)
                          .limit(1)
                          .get();

                      if (query.docs.isNotEmpty) {
                        setStateDialog(() => isChecking = false);
                        if (localContext.mounted) ScaffoldMessenger.of(localContext).showSnackBar(const SnackBar(content: Text('المعرف مستخدم بالفعل')));
                        return;
                      }

                      try {
                        await _groupDocRef.update({'info.handle': newHandle});
                        if (localContext.mounted) Navigator.of(localContext).pop();
                      } catch (e) {
                        setStateDialog(() => isChecking = false);
                        if (localContext.mounted) ScaffoldMessenger.of(localContext).showSnackBar(SnackBar(content: Text('فشل التحديث: $e')));
                      }
                    }
                  },
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditPrivacyDialog() {
    String tempPrivacy = _currentPrivacy;
    final localContext = context;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('تغيير الخصوصية'),
              content: DropdownButtonFormField<String>(
                initialValue: tempPrivacy,
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('مفتوح للجميع')),
                  DropdownMenuItem(value: 'request', child: Text('طلب انضمام')),
                  DropdownMenuItem(value: 'closed', child: Text('مغلقة (خاصة)')),
                ],
                onChanged: (val) {
                  if (val != null) setStateDialog(() => tempPrivacy = val);
                },
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(localContext).pop(), child: const Text('إلغاء')),
                TextButton(
                  onPressed: () async {
                    if (tempPrivacy == _currentPrivacy) {
                      if (localContext.mounted) Navigator.of(localContext).pop();
                      return;
                    }
                    try {
                      await _groupDocRef.update({'info.privacy': tempPrivacy});
                      if (localContext.mounted) Navigator.of(localContext).pop();
                    } catch (e) {
                      if (localContext.mounted) ScaffoldMessenger.of(localContext).showSnackBar(SnackBar(content: Text('فشل التحديث: $e')));
                    }
                  },
                  child: const Text('حفظ'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  void _leaveGroup() async {
    final bool isCreator = _myRole == 'admin';
    final localContext = context;

    if (isCreator) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تحذير'),
          content: const Text('أنت مدير هذه المجموعة. إذا غادرت، سيتم حذف المجموعة بالكامل. هل أنت متأكد؟'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _deleteGroup();
              },
              child: const Text('حذف المجموعة', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    } else {
      try {
        await _removeMember(_currentUid);
        if (localContext.mounted) Navigator.of(localContext).popUntil((route) => route.isFirst);
      } catch (e) {
        if (localContext.mounted) ScaffoldMessenger.of(localContext).showSnackBar(SnackBar(content: Text('فشل مغادرة المجموعة: $e')));
      }
    }
  }

  void _deleteGroup() async {
    final localContext = context;
    try {
      final batch = _firestore.batch();
      batch.delete(_groupDocRef);
      for (var memberId in _currentMembersMap.keys) {
        final memberGroupDoc = _usersCollection.doc(memberId).collection('my_groups').doc(widget.groupId);
        batch.delete(memberGroupDoc);
      }
      await batch.commit();
      if (localContext.mounted) Navigator.of(localContext).popUntil((route) => route.isFirst);
    } catch (e) {
      if (localContext.mounted) ScaffoldMessenger.of(localContext).showSnackBar(SnackBar(content: Text('فشل حذف المجموعة: $e')));
    }
  }

  // (جديد) دالة عرض طلبات الانضمام
  void _showJoinRequests() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.7,
          child: Column(
            children: [
              AppBar(
                title: const Text('طلبات الانضمام'),
                automaticallyImplyLeading: false,
                actions: [IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))],
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _groupDocRef.collection('requests').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(child: Text('لا توجد طلبات انضمام معلقة'));
                    }

                    final docs = snapshot.data!.docs;
                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final req = docs[index].data() as Map<String, dynamic>;
                        final reqUid = req['uid'] ?? '';
                        final reqName = req['name'] ?? 'مستخدم';

                        return ListTile(
                          leading: CircleAvatar(child: Text(reqName.isNotEmpty ? reqName[0] : '?')),
                          title: Text(reqName),
                          subtitle: const Text('يريد الانضمام'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check, color: Colors.green),
                                onPressed: () => _acceptRequest(docs[index].reference, reqUid),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                onPressed: () => _rejectRequest(docs[index].reference),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // (جديد) قبول الطلب
  Future<void> _acceptRequest(DocumentReference reqRef, String uid) async {
    try {
      final batch = _firestore.batch();

      // 1. إضافة العضو
      batch.update(_groupDocRef, {'members.$uid': 'member'});

      // 2. إضافة المجموعة للمستخدم
      final userGroupRef = _usersCollection.doc(uid).collection('my_groups').doc(widget.groupId);
      batch.set(userGroupRef, {
        'name': _currentGroupName,
        'chatId': widget.groupId,
        'isGroup': true,
        'lastMessage': 'تم قبول طلب انضمامك',
        'lastMessageTimestamp': DateTime.now().millisecondsSinceEpoch,
        'imageUrl': _groupImageUrl,
        'unreadCount': 0,
      });

      // 3. حذف الطلب
      batch.delete(reqRef);

      await batch.commit();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم قبول العضو')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
    }
  }

  // (جديد) رفض الطلب
  Future<void> _rejectRequest(DocumentReference reqRef) async {
    try {
      await reqRef.delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفض الطلب')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _groupDocRef.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('معلومات المجموعة')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final groupData = snapshot.data!.data();
        if (groupData == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('خطأ')),
            body: const Center(child: Text('لا يمكن تحميل بيانات المجموعة.')),
          );
        }

        final groupInfo = groupData['info'] as Map<String, dynamic>? ?? {};
        final membersData = groupData['members'] as Map<String, dynamic>? ?? {};

        _currentGroupName = groupInfo['name'] ?? widget.groupName;
        _groupImageUrl = groupInfo['imageUrl'] as String?;
        _currentGroupHandle = groupInfo['handle'] as String?;
        _currentPrivacy = groupInfo['privacy'] as String? ?? 'open';

        _currentMembersMap = membersData;

        if (_membersList.isEmpty || _membersList.length != membersData.length) {
          _fetchMemberNames(membersData);
        }

        // إذا كنت أنا المدير (سواء فعلي أو بالرقم المحدد)
        final bool iAmAdminOrSupervisor = (_myRole == 'admin' || _myRole == 'supervisor');
        final bool iAmAdmin = (_myRole == 'admin');

        return Scaffold(
          appBar: AppBar(
            title: const Text('معلومات المجموعة'),
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                             decoration: BoxDecoration(
                               shape: BoxShape.circle,
                               boxShadow: [
                                 BoxShadow(
                                   color: theme.colorScheme.primary.withValues(alpha: 0.3),
                                   blurRadius: 20,
                                   spreadRadius: 5,
                                 )
                               ]
                             ),
                            child: CircleAvatar(
                              radius: 60,
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                              backgroundImage: (_groupImageUrl != null)
                                  ? NetworkImage(_groupImageUrl!)
                                  : null,
                              child: (_groupImageUrl == null)
                                  ? const Icon(Icons.groups, size: 60, color: Colors.white)
                                  : null,
                            ),
                          ),
                          if (_isUploadingImage)
                            const Positioned.fill(
                              child: Center(
                                child: CircularProgressIndicator(color: Colors.white),
                              ),
                            ),
                          if (iAmAdmin && !_isUploadingImage)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: CircleAvatar(
                                backgroundColor: theme.colorScheme.primary,
                                radius: 20,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.camera_alt, size: 20, color: Colors.white),
                                  onPressed: _pickAndUploadImage,
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _currentGroupName,
                            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (iAmAdminOrSupervisor)
                            IconButton(
                              icon: Icon(Icons.edit, size: 20, color: Colors.grey[400]),
                              onPressed: _showEditGroupNameDialog,
                            ),
                        ],
                      ),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _currentGroupHandle != null ? '@$_currentGroupHandle' : 'لا يوجد معرف',
                            style: TextStyle(color: theme.colorScheme.secondary, fontWeight: FontWeight.w500, fontSize: 16),
                          ),
                          if (iAmAdmin)
                            IconButton(
                              icon: Icon(Icons.edit, size: 16, color: Colors.grey[400]),
                              onPressed: _showEditHandleDialog,
                            ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),

                      InkWell(
                        onTap: iAmAdmin ? _showEditPrivacyDialog : null,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _currentPrivacy == 'closed' ? Icons.lock :
                                _currentPrivacy == 'request' ? Icons.lock_clock : Icons.public,
                                size: 16, color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _translatePrivacy(_currentPrivacy),
                                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                              ),
                              if (iAmAdmin)
                                Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),
                      Text(
                        '${_membersList.length} أعضاء',
                        style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                
                // (جديد) زر إدارة الطلبات للمدير
                if (iAmAdmin && _currentPrivacy == 'request')
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: ElevatedButton.icon(
                      onPressed: _showJoinRequests,
                      icon: const Icon(Icons.notifications_active),
                      label: const Text('إدارة طلبات الانضمام'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.tertiaryContainer,
                        foregroundColor: theme.colorScheme.onTertiaryContainer,
                        elevation: 0,
                      ),
                    ),
                  ),

                if (iAmAdminOrSupervisor)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('إضافة أعضاء جدد'),
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (ctx) => AddGroupMembersScreen(
                            groupId: widget.groupId,
                            groupName: _currentGroupName,
                            currentMembers: _currentMembersMap, 
                          ),
                        ));
                      },
                    ),
                  ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Divider(),
                ),
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('الأعضاء', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),

                if (_membersList.isEmpty && snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _membersList.length,
                    itemBuilder: (ctx, index) {
                      final member = _membersList[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.secondaryContainer,
                          child: Text(member.name.isNotEmpty ? member.name[0] : '?', style: TextStyle(color: theme.colorScheme.onSecondaryContainer)),
                        ),
                        title: Text(member.name),
                        subtitle: Text(_translateRole(member.role)),
                        trailing: _getRoleIcon(member.role, theme),
                        onLongPress: () => _showMemberOptions(member),
                      );
                    },
                  ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Divider(),
                ),

                ListTile(
                  leading: Icon(Icons.exit_to_app, color: theme.colorScheme.error),
                  title: Text(
                      _myRole == 'admin' ? 'حذف المجموعة والمغادرة' : 'مغادرة المجموعة',
                      style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold)
                  ),
                  onTap: _leaveGroup,
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }
}
