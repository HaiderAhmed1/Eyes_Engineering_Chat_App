import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SearchGroupScreen extends StatefulWidget {
  const SearchGroupScreen({super.key});

  @override
  State<SearchGroupScreen> createState() => _SearchGroupScreenState();
}

class _SearchGroupScreenState extends State<SearchGroupScreen> {
  final _searchController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  List<DocumentSnapshot> _searchResults = [];
  bool _isLoading = false;

  void _searchGroup(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. البحث عن طريق المعرف (handle)
      final byHandle = await _firestore
          .collection('groups')
          .where('info.handle', isGreaterThanOrEqualTo: query)
          .where('info.handle', isLessThan: '$query\uf8ff')
          .limit(10)
          .get();

      // 2. البحث عن طريق اسم المجموعة (دعم للغة العربية)
      final byName = await _firestore
          .collection('groups')
          .where('info.name', isGreaterThanOrEqualTo: query)
          .where('info.name', isLessThan: '$query\uf8ff')
          .limit(10)
          .get();

      // دمج النتائج وحذف المكرر (في حال تطابق الاسم والمعرف)
      final Map<String, DocumentSnapshot> uniqueGroups = {};

      for (var doc in byHandle.docs) {
        uniqueGroups[doc.id] = doc;
      }
      for (var doc in byName.docs) {
        uniqueGroups[doc.id] = doc;
      }

      if (mounted) {
        setState(() {
          _searchResults = uniqueGroups.values.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في البحث: $e')));
      }
    }
  }

  Future<void> _handleJoin(DocumentSnapshot groupDoc) async {
    if (!mounted) return;

    final groupData = groupDoc.data() as Map<String, dynamic>;
    final groupInfo = groupData['info'] as Map<String, dynamic>;
    final members = groupData['members'] as Map<String, dynamic>;

    final groupId = groupDoc.id;
    final privacy = groupInfo['privacy'] ?? 'closed'; // Default to closed
    final currentUid = _auth.currentUser!.uid;

    // 1. التحقق مما إذا كان المستخدم عضواً بالفعل
    if (members.containsKey(currentUid)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أنت عضو في هذه المجموعة بالفعل')));
      }
      return;
    }

    try {
      if (privacy == 'closed') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('هذه المجموعة مغلقة ولا تقبل انضماماً جديداً')));
        }
        return;
      }

      if (privacy == 'open') {
        // --- انضمام مباشر ---
        final batch = _firestore.batch();

        // إضافة العضو للمجموعة
        batch.update(groupDoc.reference, {'members.$currentUid': 'member'});

        // إضافة المجموعة للمستخدم
        final userGroupRef = _firestore.collection('users').doc(currentUid).collection('my_groups').doc(groupId);
        batch.set(userGroupRef, {
          'name': groupInfo['name'],
          'chatId': groupId,
          'isGroup': true,
          'lastMessage': 'انضم عضو جديد',
          'lastMessageTimestamp': DateTime.now().millisecondsSinceEpoch,
          'imageUrl': groupInfo['imageUrl'],
          'unreadCount': 0,
        });

        await batch.commit();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الانضمام بنجاح!')));

      } else if (privacy == 'request') {
        // --- إرسال طلب انضمام ---

        final existingRequest = await groupDoc.reference.collection('requests').doc(currentUid).get();
        if (existingRequest.exists) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لقد أرسلت طلباً بالفعل وهو قيد الانتظار')));
          return;
        }

        // جلب بيانات المستخدم الحالية لإرسالها مع الطلب بشكل كامل (الاسم والصورة)
        final userDoc = await _firestore.collection('users').doc(currentUid).get();
        final userData = userDoc.data();
        final String userName = userData?['name'] ?? 'مستخدم';
        final String? userImage = userData?['imageUrl'];

        await groupDoc.reference.collection('requests').doc(currentUid).set({
          'uid': currentUid,
          'name': userName,
          'imageUrl': userImage, // تمت الإضافة ليراها مدير المجموعة
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'pending',
        });

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال طلب الانضمام للمدير')));
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ أثناء محاولة الانضمام: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('البحث عن مجموعات'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'ابحث باسم المجموعة أو المعرف (@)',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _searchGroup,
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty && _searchController.text.isNotEmpty
                ? const Center(child: Text('لا توجد نتائج مطابقة'))
                : ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (ctx, index) {
                final doc = _searchResults[index];
                final data = doc.data() as Map<String, dynamic>;
                final info = data['info'] as Map<String, dynamic>;
                final privacy = info['privacy'] ?? 'closed';
                final handle = info['handle'] ?? '';
                final imageUrl = info['imageUrl'];

                String actionText = 'انضمام';
                IconData actionIcon = Icons.add;
                bool canJoin = false;

                if (privacy == 'closed') {
                  actionText = 'مغلقة';
                  actionIcon = Icons.lock;
                  canJoin = false;
                } else if (privacy == 'request') {
                  actionText = 'طلب انضمام';
                  actionIcon = Icons.send;
                  canJoin = true;
                } else {
                  actionText = 'انضمام';
                  actionIcon = Icons.add;
                  canJoin = true;
                }

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
                    child: imageUrl == null ? const Icon(Icons.group) : null,
                  ),
                  title: Text(info['name'] ?? 'مجموعة', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('@$handle \n${privacy == 'open' ? 'عامة' : privacy == 'request' ? 'تحتاج موافقة' : 'مغلقة'}'),
                  isThreeLine: true,
                  trailing: ElevatedButton.icon(
                    onPressed: canJoin ? () => _handleJoin(doc) : null,
                    icon: Icon(actionIcon, size: 16),
                    label: Text(actionText),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canJoin ? Theme.of(context).colorScheme.primary : Colors.grey[700],
                      foregroundColor: canJoin ? Theme.of(context).colorScheme.onPrimary : Colors.white,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}