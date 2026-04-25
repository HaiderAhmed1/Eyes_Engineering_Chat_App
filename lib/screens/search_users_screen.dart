import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:chat_app/screens/private_chat_screen.dart';
import 'package:chat_app/screens/profile_screen.dart';

class SearchUsersScreen extends StatefulWidget {
  const SearchUsersScreen({super.key});

  @override
  State<SearchUsersScreen> createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends State<SearchUsersScreen> {
  final _searchController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  List<DocumentSnapshot> _searchResults = [];
  bool _isLoading = false;
  String _errorMessage = '';

  void _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _errorMessage = '';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final currentUserId = _auth.currentUser?.uid;

      // 1. البحث بمطابقة اسم المستخدم (displayName)
      final byUsername = await _firestore
          .collection('users')
          .where('displayName', isGreaterThanOrEqualTo: query)
          .where('displayName', isLessThan: '$query\uf8ff') // تم التعديل لدعم العربية
          .limit(10)
          .get();

      // 2. البحث بالاسم (name)
      final byName = await _firestore
          .collection('users')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThan: '$query\uf8ff') // تم التعديل لدعم العربية
          .limit(10)
          .get();

      // 3. البحث برقم الهاتف (إذا كان الرقم مدخلاً)
      QuerySnapshot? byPhone;
      if (RegExp(r'^[0-9]+$').hasMatch(query)) {
        byPhone = await _firestore
            .collection('users')
            .where('phoneNumber', isGreaterThanOrEqualTo: query)
            .where('phoneNumber', isLessThan: '$query\uf8ff') // تم التعديل
            .limit(5)
            .get();
      }

      // دمج النتائج وحذف المكرر
      final Map<String, DocumentSnapshot> uniqueUsers = {};

      for (var doc in byUsername.docs) {
        uniqueUsers[doc.id] = doc;
      }
      for (var doc in byName.docs) {
        uniqueUsers[doc.id] = doc;
      }
      if (byPhone != null) {
        for (var doc in byPhone.docs) {
          uniqueUsers[doc.id] = doc;
        }
      }

      // إزالة المستخدم الحالي من نتائج البحث
      uniqueUsers.remove(currentUserId);

      if (mounted) {
        setState(() {
          _searchResults = uniqueUsers.values.toList();
          _isLoading = false;
        });
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'حدث خطأ أثناء البحث: $e';
          _isLoading = false;
        });
      }
    }
  }

  String _getChatId(String uid1, String uid2) {
    return uid1.compareTo(uid2) < 0 ? '${uid1}_$uid2' : '${uid2}_$uid1';
  }

  void _startChat(String targetUserId, String targetUserName, String? targetImageUrl) async {
    final currentUserId = _auth.currentUser!.uid;

    try {
      // التحقق من الحظر قبل البدء
      final targetDoc = await _firestore.collection('users').doc(targetUserId).get();
      final List<dynamic> blockedByTarget = targetDoc.data()?['blockedUsers'] ?? [];

      if (blockedByTarget.contains(currentUserId)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يمكنك مراسلة هذا المستخدم (محظور)')),
          );
        }
        return;
      }

      final chatId = _getChatId(currentUserId, targetUserId);

      final myUserDoc = await _firestore.collection('users').doc(currentUserId).get();
      final myName = myUserDoc.data()?['name'] ?? 'مستخدم';
      final myImage = myUserDoc.data()?['imageUrl'];

      final chatDataForMe = {
        'name': targetUserName,
        'imageUrl': targetImageUrl,
        'chatId': chatId,
        'lastMessage': '',
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'unreadCount': 0,
        'isGroup': false,
        'displayName': targetDoc.data()?['displayName'],
        'phoneNumber': targetDoc.data()?['phoneNumber'],
      };

      final chatDataForTarget = {
        'name': myName,
        'imageUrl': myImage,
        'chatId': chatId,
        'lastMessage': '',
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'unreadCount': 0,
        'isGroup': false,
        'displayName': myUserDoc.data()?['displayName'],
        'phoneNumber': myUserDoc.data()?['phoneNumber'],
      };

      // 1. الكتابة في قائمتي (غالباً مسموحة)
      await _firestore.collection('users').doc(currentUserId).collection('my_chats').doc(targetUserId).set(chatDataForMe, SetOptions(merge: true));

      // 2. الكتابة في قائمة الطرف الآخر (قد يتم رفضها بسبب Rules، لذا نفصلها بـ try-catch)
      try {
        await _firestore.collection('users').doc(targetUserId).collection('my_chats').doc(currentUserId).set(chatDataForTarget, SetOptions(merge: true));
      } catch (e) {
        debugPrint('تجاهل خطأ الكتابة للطرف الآخر: $e');
      }

      // الانتقال للمحادثة بشكل مؤكد
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PrivateChatScreen(
              targetUserId: targetUserId,
              targetUserName: targetUserName,
              chatId: chatId,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء فتح المحادثة: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: 'بحث بالاسم، المعرف، أو الرقم...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          ),
          onChanged: (val) {
            _performSearch(val);
          },
        ),
      ),
      body: Column(
        children: [
          if (_isLoading)
            const LinearProgressIndicator(),
          if (_errorMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_errorMessage, style: TextStyle(color: theme.colorScheme.error)),
            ),
          Expanded(
            child: _searchResults.isEmpty && _searchController.text.isNotEmpty && !_isLoading
                ? Center(child: Text('لا توجد نتائج', style: theme.textTheme.bodyLarge))
                : ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final data = _searchResults[index].data() as Map<String, dynamic>;
                final uid = _searchResults[index].id;
                final name = data['name'] ?? 'مستخدم';
                final displayName = data['displayName'] ?? '';
                final imageUrl = data['imageUrl'];
                final phoneNumber = data['phoneNumber'] ?? '';

                return ListTile(
                  leading: GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid)));
                    },
                    child: CircleAvatar(
                      backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
                      child: imageUrl == null ? const Icon(Icons.person) : null,
                    ),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('@$displayName'),
                      if (phoneNumber.toString().isNotEmpty)
                        Text(phoneNumber, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.message_outlined),
                    color: theme.colorScheme.primary,
                    onPressed: () => _startChat(uid, name, imageUrl),
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