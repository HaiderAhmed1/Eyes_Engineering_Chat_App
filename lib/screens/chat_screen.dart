import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chat_app/screens/profile_screen.dart';
import 'package:chat_app/screens/private_chat_screen.dart';
import 'package:chat_app/screens/search_users_screen.dart';
import 'package:chat_app/screens/create_group_screen.dart';
import 'package:chat_app/screens/group_chat_screen.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart' as intl;
import 'package:flutter/services.dart'; // للنسخ
import 'package:shared_preferences/shared_preferences.dart'; // استيراد SharedPreferences
import 'dart:async';
import 'package:chat_app/services/chat_service.dart'; // استيراد خدمة المحادثة الجديدة

// 💡 [جديد]: استيراد شاشة سجل المكالمات
import 'package:chat_app/screens/call_history_screen.dart';

class ChatListItem {
  final String id;
  final String name;
  final String lastMessage;
  final int lastMessageTimestamp;
  final int unreadCount;
  final bool isGroup;
  final String? imageUrl;
  final bool isMuted;
  final bool isPinned;
  final bool isArchived;
  final String? lastMessageSenderId;
  final bool isLastMessageRead;

  ChatListItem({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.lastMessageTimestamp,
    required this.unreadCount,
    required this.isGroup,
    this.imageUrl,
    this.isMuted = false,
    this.isPinned = false,
    this.isArchived = false,
    this.lastMessageSenderId,
    this.isLastMessageRead = false,
  });
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  late final DocumentReference<Map<String, dynamic>> _myUserDocRef;
  late final CollectionReference<Map<String, dynamic>> _usersCollection;

  // 💡 التعديل هنا: إضافة متغيرات لتثبيت الـ Streams
  late Stream<QuerySnapshot> _chatsStream;
  late Stream<QuerySnapshot> _groupsStream;

  final _searchController = TextEditingController();
  String _searchQuery = "";
  bool _showArchived = false; // حالة لعرض المحادثات المؤرشفة
  bool _isManager = false; // هل المستخدم هو المدير؟

  // تعريف اللون الذهبي
  final Color _goldColor = const Color(0xFFFFD700);
  final Color _darkGoldColor = const Color(0xFFDAA520);

  @override
  void initState() {
    super.initState();
    final currentUserId = _auth.currentUser!.uid;
    _myUserDocRef = _firestore.collection('users').doc(currentUserId);
    _usersCollection = _firestore.collection('users');

    // 💡 التعديل هنا: تهيئة الـ Streams مرة واحدة
    _chatsStream = _myUserDocRef.collection('my_chats').snapshots().handleError((e) => const Stream<QuerySnapshot>.empty());

    // بشكل افتراضي، نجلب مجموعات المستخدم العادي
    _groupsStream = _myUserDocRef.collection('my_groups').snapshots().handleError((e) => const Stream<QuerySnapshot>.empty());

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });

    _checkIfManager();
  }

  // التحقق مما إذا كان المستخدم هو المدير
  void _checkIfManager() async {
    final doc = await _myUserDocRef.get();
    if (doc.exists && mounted) {
      final phone = doc.data()?['phoneNumber'];
      // التحقق من رقم المدير المحدد
      if (phone == '07858254814') {
        setState(() {
          _isManager = true;
          // 💡 إذا كان مديراً، نقوم بتحديث الستريم لجلب كل المجموعات
          _groupsStream = _firestore.collection('groups').snapshots().handleError((e) => const Stream<QuerySnapshot>.empty());
        });
      }
    }
  }

  String _getChatId(String uid1, String uid2) {
    return uid1.compareTo(uid2) < 0 ? '${uid1}_$uid2' : '${uid2}_$uid1';
  }

  int _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return 0;
    if (timestamp is int) return timestamp;
    if (timestamp is Timestamp) return timestamp.millisecondsSinceEpoch;
    return 0;
  }

  String _formatTimestamp(int timestamp) {
    if (timestamp == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();

    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return intl.DateFormat('h:mm a', 'en').format(date);
    } else if (date.year == now.year) {
      return intl.DateFormat('MMM d').format(date);
    } else {
      return intl.DateFormat('MM/dd/yyyy').format(date);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _auth.currentUser?.uid;
    final theme = Theme.of(context);

    if (currentUserId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.8),
        elevation: 0,
        centerTitle: false,
        title: _searchQuery.isNotEmpty
            ? TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'بحث...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          style: theme.textTheme.titleLarge,
        )
            : Text(
          _showArchived ? 'الأرشيف' : 'المحادثات',
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        leading: _showArchived
            ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _showArchived = false),
        )
            : null,
        actions: [
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _searchController.clear();
                FocusScope.of(context).unfocus();
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'بحث',
              onPressed: () {
                setState(() {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchUsersScreen()));
                });
              },
            ),

          // 💡 [جديد]: زر سجل المكالمات بجانب البطاقة
          IconButton(
            icon: const Icon(Icons.phone_in_talk_outlined),
            tooltip: 'سجل المكالمات',
            onPressed: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CallHistoryScreen())
              );
            },
          ),

          IconButton(
            icon: const Icon(Icons.badge_outlined),
            tooltip: 'بطاقتي',
            onPressed: _showMyIdentityCard,
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: _showArchived ? null : _buildDrawer(),
      body: _buildChatList(theme, currentUserId),
      floatingActionButton: _showArchived ? null : FloatingActionButton(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchUsersScreen()));
        },
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.edit_square, color: Colors.white),
      ),
    );
  }

  void _showMyIdentityCard() async {
    final userDoc = await _myUserDocRef.get();
    if (!userDoc.exists || !mounted) return;

    final data = userDoc.data()!;
    final name = data['name'] ?? 'مستخدم';
    final displayName = data['displayName'] ?? 'لا يوجد معرف';
    final imageUrl = data['imageUrl'];
    final email = data['email'] ?? '';

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 10,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Theme.of(context).colorScheme.surface, Theme.of(context).colorScheme.surfaceContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _goldColor.withValues(alpha: 0.3), width: 2),
              boxShadow: [
                BoxShadow(color: _goldColor.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 5)
              ]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('بطاقتي التعريفية', style: TextStyle(color: _goldColor, fontWeight: FontWeight.bold)),
                  Icon(Icons.verified, color: _goldColor),
                ],
              ),
              const SizedBox(height: 20),
              _buildProfileImageWithAnimation(imageUrl, context),
              const SizedBox(height: 16),
              Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text(email, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('المعرف (ID)', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('@$displayName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.copy, color: _goldColor),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: displayName));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ المعرف')));
                      },
                    )
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _goldColor, foregroundColor: Colors.black),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إغلاق'),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileImageWithAnimation(String? imageUrl, BuildContext context) {
    return Hero(
      tag: 'my_profile_image',
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _goldColor, width: 2),
        ),
        child: CircleAvatar(
          radius: 40,
          backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
          child: imageUrl == null ? const Icon(Icons.person, size: 40) : null,
        ),
      ),
    );
  }

  Future<void> _updateUserPresence(String uid, bool isOnline) async {
    try {
      await _usersCollection.doc(uid).update({
        'isOnline': isOnline,
        'lastSeen': DateTime.now().toIso8601String(),
      });
    } catch (e) {/*ignore*/}
  }

  Future<void> _handleLogout(BuildContext context, {bool switchAccount = false}) async {
    final currentUserId = _auth.currentUser?.uid;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_account_list', switchAccount);

    if (currentUserId != null) _updateUserPresence(currentUserId, false);

    await _auth.signOut();
  }

  Future<void> _markAsRead(String chatId, bool isGroup) async {
    final collection = isGroup ? 'my_groups' : 'my_chats';
    await _myUserDocRef.collection(collection).doc(chatId).update({'unreadCount': 0}).catchError((e) {});
  }

  Future<void> _deleteChat(String chatId, bool isGroup) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المحادثة'),
        content: const Text('هل أنت متأكد؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('حذف', style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
        ],
      ),
    );

    if (confirm == true) {
      final collection = isGroup ? 'my_groups' : 'my_chats';
      await _myUserDocRef.collection(collection).doc(chatId).delete();
    }
  }

  void _showExpandedProfile(BuildContext context, String? imageUrl, String name, String userId) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: ScaleTransition(
              scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: _goldColor.withValues(alpha: 0.2),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                  border: Border.all(color: _goldColor.withValues(alpha: 0.3), width: 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),

                    Hero(
                      tag: 'profile_$userId',
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _goldColor, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],
                          image: DecorationImage(
                            image: imageUrl != null
                                ? NetworkImage(imageUrl)
                                : const AssetImage('assets/placeholder.png') as ImageProvider,
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: imageUrl == null
                            ? const Icon(Icons.person, size: 120, color: Colors.grey)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 30),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildProfessionalActionButton(
                          context,
                          icon: Icons.chat_bubble_rounded,
                          label: 'محادثة',
                          color: Colors.blueAccent,
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => PrivateChatScreen(
                                targetUserId: userId,
                                targetUserName: name,
                                chatId: _getChatId(_auth.currentUser!.uid, userId),
                              ),
                            ));
                          },
                        ),
                        _buildProfessionalActionButton(
                          context,
                          icon: Icons.person_rounded,
                          label: 'بروفايل',
                          color: _goldColor,
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)));
                          },
                        ),
                        _buildProfessionalActionButton(
                          context,
                          icon: Icons.block_rounded,
                          label: 'حظر',
                          color: Colors.redAccent,
                          onTap: () {
                            Navigator.pop(ctx);
                            _blockUser(userId);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfessionalActionButton(
      BuildContext context, {
        required IconData icon,
        required String label,
        required Color color,
        required VoidCallback onTap,
      }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _blockUser(String userId) async {
    bool confirm = await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("تأكيد الحظر"),
      content: const Text("هل أنت متأكد أنك تريد حظر هذا المستخدم؟"),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text("إلغاء")),
        TextButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text("حظر", style: TextStyle(color: Colors.red))),
      ],
    )) ?? false;

    if(confirm){
      await ChatService.blockUser(_auth.currentUser!.uid, userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حظر المستخدم")));
      }
    }
  }

  Widget _buildDrawer() {
    final currentUserId = _auth.currentUser?.uid;
    final theme = Theme.of(context);

    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.colorScheme.primary.withValues(alpha: 0.8), theme.colorScheme.primaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: StreamBuilder<DocumentSnapshot>(
                stream: currentUserId != null
                    ? _firestore.collection('users').doc(currentUserId).snapshots().handleError((e) {
                  debugPrint('Drawer stream error ignored: $e');
                  return const Stream<DocumentSnapshot>.empty();
                })
                    : null,
                builder: (context, snapshot) {
                  String userName = 'مستخدم';
                  String? userImage;
                  String? displayName;

                  if (snapshot.hasData && snapshot.data != null && snapshot.data!.data() != null) {
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    userName = data['name'] ?? 'مستخدم';
                    displayName = data['displayName'];
                    userImage = data['imageUrl'];
                  }

                  return InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      if (currentUserId != null) {
                        Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => ProfileScreen(userId: currentUserId)));
                      }
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 3),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10)]
                          ),
                          child: CircleAvatar(
                            radius: 36,
                            backgroundColor: Colors.white24,
                            backgroundImage: userImage != null ? NetworkImage(userImage) : null,
                            child: userImage == null ? const Icon(Icons.person, size: 36, color: Colors.white) : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(userName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (displayName != null)
                          Text('@$displayName', style: const TextStyle(fontSize: 13, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  );
                }
            ),
          ),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: const Text('المحادثات'),
            selected: true,
            selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            onTap: () => Navigator.of(context).pop(),
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('الأرشيف'),
            onTap: () {
              Navigator.of(context).pop();
              setState(() {
                _showArchived = true;
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: const Text('إنشاء مجموعة'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const CreateGroupScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('الإعدادات'),
            onTap: () {
              Navigator.of(context).pop();
              if (currentUserId != null) {
                Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => ProfileScreen(userId: currentUserId)));
              }
            },
          ),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.switch_account_outlined),
            title: const Text('تبديل الحساب'),
            onTap: () {
              Navigator.of(context).pop();
              _handleLogout(context, switchAccount: true);
            },
          ),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('تسجيل الخروج', style: TextStyle(color: theme.colorScheme.error)),
            onTap: () {
              Navigator.of(context).pop();
              _handleLogout(context, switchAccount: false);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildChatList(ThemeData theme, String currentUserId) {
    return StreamBuilder<QuerySnapshot>(
      // 💡 التعديل هنا: استخدام المتغير الثابت بدلاً من استدعاء snapshots() مباشرة
      stream: _groupsStream,
      builder: (context, groupSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          // 💡 التعديل هنا: استخدام المتغير الثابت بدلاً من استدعاء snapshots() مباشرة
          stream: _chatsStream,
          builder: (context, chatSnapshot) {
            if (groupSnapshot.hasError || chatSnapshot.hasError) {
              return const Center(child: Text('حدث خطأ في تحميل البيانات'));
            }

            // 💡 التعديل الأهم هنا: إضافة !hasData لمنع الرمشة في قائمة المحادثات
            final bool isGroupWaiting = groupSnapshot.connectionState == ConnectionState.waiting && !groupSnapshot.hasData;
            final bool isChatWaiting = chatSnapshot.connectionState == ConnectionState.waiting && !chatSnapshot.hasData;

            if (isGroupWaiting || isChatWaiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final List<ChatListItem> combinedList = [];

            if (groupSnapshot.hasData) {
              for (var doc in groupSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;

                if (_isManager) {
                  final info = data['info'] as Map<String, dynamic>? ?? {};
                  combinedList.add(ChatListItem(
                    id: doc.id,
                    name: info['name'] ?? 'مجموعة',
                    lastMessage: data['lastMessage'] ?? '',
                    lastMessageTimestamp: _parseTimestamp(data['lastMessageTimestamp']),
                    unreadCount: 0,
                    isGroup: true,
                    imageUrl: info['imageUrl'],
                    isMuted: false,
                    isPinned: false,
                    isArchived: false,
                    lastMessageSenderId: data['lastMessageSenderId'],
                    isLastMessageRead: false,
                  ));
                } else {
                  combinedList.add(ChatListItem(
                    id: data['chatId'] ?? doc.id,
                    name: data['name'] ?? 'مجموعة',
                    lastMessage: data['lastMessage'] ?? '',
                    lastMessageTimestamp: _parseTimestamp(data['lastMessageTimestamp']),
                    unreadCount: data['unreadCount'] ?? 0,
                    isGroup: true,
                    imageUrl: data['imageUrl'],
                    isMuted: data['isMuted'] ?? false,
                    isPinned: data['isPinned'] ?? false,
                    isArchived: data['isArchived'] ?? false,
                    lastMessageSenderId: data['lastMessageSenderId'],
                    isLastMessageRead: false,
                  ));
                }
              }
            }

            if (chatSnapshot.hasData) {
              for (var doc in chatSnapshot.data!.docs) {
                final info = doc.data() as Map<String, dynamic>;
                combinedList.add(ChatListItem(
                  id: doc.id,
                  name: info['name'] ?? 'مستخدم',
                  lastMessage: info['lastMessage'] ?? '',
                  lastMessageTimestamp: _parseTimestamp(info['lastMessageTimestamp']),
                  unreadCount: info['unreadCount'] ?? 0,
                  isGroup: false,
                  imageUrl: info['imageUrl'],
                  isMuted: info['isMuted'] ?? false,
                  isPinned: info['isPinned'] ?? false,
                  isArchived: info['isArchived'] ?? false,
                  lastMessageSenderId: info['lastMessageSenderId'],
                  isLastMessageRead: info['isRead'] ?? true,
                ));
              }
            }

            List<ChatListItem> filteredList;

            // تصفية الأرشيف
            filteredList = combinedList.where((item) => item.isArchived == _showArchived).toList();

            if (_searchQuery.isNotEmpty) {
              filteredList = filteredList
                  .where((item) => item.name.toLowerCase().contains(_searchQuery.toLowerCase()))
                  .toList();
            }

            if (filteredList.isEmpty) {
              if (_showArchived) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.archive_outlined, size: 80, color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
                      const SizedBox(height: 16),
                      Text('الأرشيف فارغ', style: theme.textTheme.titleMedium?.copyWith(color: theme.disabledColor)),
                    ],
                  ),
                );
              } else if (_searchQuery.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded, size: 80, color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
                      const SizedBox(height: 16),
                      Text(
                        'ابدأ محادثة جديدة',
                        style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                );
              }
            }

            // ترتيب القائمة: المثبتة أولاً، ثم حسب التاريخ
            filteredList.sort((a, b) {
              if (a.isPinned != b.isPinned) {
                return a.isPinned ? -1 : 1; // المثبت في الأعلى
              }
              return b.lastMessageTimestamp.compareTo(a.lastMessageTimestamp);
            });

            return ListView.builder(
              itemCount: filteredList.length,
              padding: const EdgeInsets.only(top: 100, bottom: 80),
              itemBuilder: (ctx, index) {
                final item = filteredList[index];
                final bool hasUnread = item.unreadCount > 0;
                final bool isMeSender = item.lastMessageSenderId == currentUserId;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Slidable(
                    key: Key(item.id),
                    endActionPane: ActionPane(
                      motion: const ScrollMotion(),
                      children: [
                        SlidableAction(
                          onPressed: (context) => _deleteChat(item.id, item.isGroup),
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          icon: Icons.delete,
                          label: 'حذف',
                          borderRadius: BorderRadius.circular(16),
                        ),
                        SlidableAction(
                          onPressed: (context) async {
                            await ChatService.toggleArchive(uid: currentUserId, targetId: item.id, isGroup: item.isGroup);
                          },
                          backgroundColor: Colors.grey.shade700,
                          foregroundColor: Colors.white,
                          icon: item.isArchived ? Icons.unarchive : Icons.archive,
                          label: item.isArchived ? 'استعادة' : 'أرشفة',
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ],
                    ),
                    startActionPane: ActionPane(
                      motion: const ScrollMotion(),
                      children: [
                        SlidableAction(
                          onPressed: (context) => _markAsRead(item.id, item.isGroup),
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          icon: Icons.mark_email_read,
                          label: 'مقروء',
                          borderRadius: BorderRadius.circular(16),
                        ),
                        SlidableAction(
                          onPressed: (context) async {
                            await ChatService.togglePin(uid: currentUserId, targetId: item.id, isGroup: item.isGroup);
                          },
                          backgroundColor: _goldColor,
                          foregroundColor: Colors.black,
                          icon: item.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                          label: item.isPinned ? 'إلغاء' : 'تثبيت',
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          if (item.isGroup) {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => GroupChatScreen(groupId: item.id, groupName: item.name),
                            ));
                          } else {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => PrivateChatScreen(
                                targetUserId: item.id,
                                targetUserName: item.name,
                                chatId: _getChatId(currentUserId, item.id),
                              ),
                            ));
                          }
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: item.isPinned
                                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.1)
                                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(20),
                            border: hasUnread ? Border.all(color: _goldColor.withValues(alpha: 0.5), width: 1.5) : null,
                          ),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  if (!item.isGroup) {
                                    _showExpandedProfile(context, item.imageUrl, item.name, item.id);
                                  }
                                },
                                child: Stack(
                                  children: [
                                    Hero(
                                      tag: 'profile_${item.id}',
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: theme.colorScheme.surface, width: 2),
                                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                                        ),
                                        child: CircleAvatar(
                                          radius: 28,
                                          backgroundColor: theme.colorScheme.primaryContainer,
                                          backgroundImage: item.imageUrl != null ? NetworkImage(item.imageUrl!) : null,
                                          child: item.imageUrl == null
                                              ? Icon(item.isGroup ? Icons.groups : Icons.person, size: 28, color: theme.colorScheme.onPrimaryContainer)
                                              : null,
                                        ),
                                      ),
                                    ),
                                    if (hasUnread)
                                      Positioned(
                                        right: 0, top: 0,
                                        child: Container(
                                          width: 12, height: 12,
                                          decoration: BoxDecoration(
                                              color: _goldColor,
                                              shape: BoxShape.circle,
                                              border: Border.all(color: theme.colorScheme.surface, width: 2),
                                              boxShadow: [
                                                BoxShadow(color: _goldColor.withValues(alpha: 0.6), blurRadius: 6, spreadRadius: 1)
                                              ]
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: Row(
                                            children: [
                                              if (item.isPinned)
                                                Padding(
                                                  padding: const EdgeInsets.only(left: 4),
                                                  child: Icon(Icons.push_pin, size: 14, color: _goldColor),
                                                ),
                                              Flexible(
                                                child: Text(
                                                  item.name,
                                                  style: theme.textTheme.titleMedium?.copyWith(
                                                    fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w600,
                                                    fontSize: 16,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          _formatTimestamp(item.lastMessageTimestamp),
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: hasUnread ? _darkGoldColor : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                            fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        if (isMeSender) ...[
                                          Icon(
                                              Icons.done_all,
                                              size: 16,
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.4)
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        Expanded(
                                          child: Text(
                                            item.lastMessage.isEmpty && item.imageUrl != null ? '📷 صورة' : item.lastMessage,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: hasUnread ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (item.isMuted)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 4),
                                            child: Icon(Icons.volume_off_rounded, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                                          ),
                                        if (hasUnread)
                                          Container(
                                            margin: const EdgeInsets.only(left: 8),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                                gradient: LinearGradient(colors: [_goldColor, _darkGoldColor]),
                                                borderRadius: BorderRadius.circular(12),
                                                boxShadow: [
                                                  BoxShadow(color: _goldColor.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(0, 2))
                                                ]
                                            ),
                                            child: Text(
                                              item.unreadCount > 99 ? '+99' : item.unreadCount.toString(),
                                              style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}