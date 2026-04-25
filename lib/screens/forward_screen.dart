import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chat_app/screens/chat_screen.dart'; // لاستخدام ChatListItem
import 'package:chat_app/services/chat_service.dart';

class ForwardedMessage {
  final String text;
  final String type;
  final String? fileUrl;
  final String? fileName;

  ForwardedMessage({
    required this.text,
    required this.type,
    this.fileUrl,
    this.fileName,
  });
}

class ForwardScreen extends StatefulWidget {
  final ForwardedMessage messageToForward;

  const ForwardScreen({
    super.key,
    required this.messageToForward,
  });

  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  late String _currentUserId;
  late DocumentReference<Map<String, dynamic>> _myUserDocRef;

  List<ChatListItem> _allChats = [];
  List<ChatListItem> _filteredChats = [];
  bool _isLoading = true;
  bool _isSending = false;
  final Set<ChatListItem> _selectedChats = {};
  final TextEditingController _searchController = TextEditingController();
  
  // اللون الذهبي
  final Color _goldColor = const Color(0xFFFFD700);

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user == null) {
      // Handle logged out state if necessary, usually pop
      Navigator.pop(context); 
      return;
    }
    _currentUserId = user.uid;
    _myUserDocRef = _firestore.collection('users').doc(_currentUserId);
    
    _loadChatList();
    
    _searchController.addListener(_onSearchChanged);
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredChats = List.from(_allChats);
      } else {
        _filteredChats = _allChats.where((chat) {
          return chat.name.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadChatList() async {
    final groupsStream = _myUserDocRef.collection('my_groups').get();
    final chatsStream = _myUserDocRef.collection('my_chats').get();

    final List<ChatListItem> combinedList = [];

    try {
      // جلب المجموعات
      final groupSnapshot = await groupsStream;
      for (var doc in groupSnapshot.docs) {
        final info = doc.data();
        combinedList.add(ChatListItem(
          id: info['chatId'] ?? doc.id,
          name: info['name'] ?? 'مجموعة',
          lastMessage: '',
          lastMessageTimestamp: 0, // يمكن استخدام info['lastMessageTimestamp'] للترتيب إذا توفر
          unreadCount: 0,
          isGroup: true,
          imageUrl: info['imageUrl'],
        ));
      }

      // جلب المحادثات الخاصة
      final chatSnapshot = await chatsStream;
      for (var doc in chatSnapshot.docs) {
        final info = doc.data();
        combinedList.add(ChatListItem(
          id: doc.id,
          name: info['name'] ?? 'مستخدم',
          lastMessage: '',
          lastMessageTimestamp: 0,
          unreadCount: 0,
          isGroup: false,
          imageUrl: info['imageUrl'],
        ));
      }
    } catch (e) {
      debugPrint("Error loading chat list: $e");
    }

    // ترتيب القائمة أبجدياً (أو حسب الأحدث إذا توفرت البيانات)
    combinedList.sort((a, b) => a.name.compareTo(b.name));

    if (mounted) {
      setState(() {
        _allChats = combinedList;
        _filteredChats = combinedList;
        _isLoading = false;
      });
    }
  }

  void _toggleSelection(ChatListItem item) {
    setState(() {
      if (_selectedChats.contains(item)) {
        _selectedChats.remove(item);
      } else {
        _selectedChats.add(item);
      }
    });
  }

  Future<void> _sendForwardedMessages() async {
    if (_selectedChats.isEmpty) return;

    final msg = widget.messageToForward;
    final navigator = Navigator.of(context);

    setState(() { _isSending = true; });

    try {
      // استخدام Future.wait للإرسال المتوازي الأسرع
      final List<Future> sendTasks = [];

      for (final chat in _selectedChats) {
        if (chat.isGroup) {
          final groupDocRef = _firestore.collection('groups').doc(chat.id);
          final messagesCollection = groupDocRef.collection('messages');

          sendTasks.add(ChatService.sendGroupDatabaseMessage(
            messagesCollection: messagesCollection,
            groupDocRef: groupDocRef,
            currentUserId: _currentUserId,
            text: msg.text,
            type: msg.type,
            fileUrl: msg.fileUrl,
            fileName: msg.fileName,
            replyData: null,
            isForwarded: true,
          ));
        } else {
          final chatId = _getChatId(_currentUserId, chat.id);
          final chatDocRef = _firestore.collection('chats').doc(chatId);
          final messagesCollection = chatDocRef.collection('messages');

          final myChatListDoc = _myUserDocRef.collection('my_chats').doc(chat.id);
          final recipientChatListDoc = _firestore
              .collection('users')
              .doc(chat.id)
              .collection('my_chats')
              .doc(_currentUserId);

          sendTasks.add(ChatService.sendPrivateDatabaseMessage(
            messagesCollection: messagesCollection,
            myChatListDoc: myChatListDoc,
            recipientChatListDoc: recipientChatListDoc,
            currentUserId: _currentUserId,
            text: msg.text,
            type: msg.type,
            fileUrl: msg.fileUrl,
            fileName: msg.fileName,
            replyData: null,
            isForwarded: true,
          ));
        }
      }

      await Future.wait(sendTasks);

      navigator.pop(); // إغلاق الشاشة بنجاح
      // عرض رسالة نجاح في الشاشة السابقة (اختياري)

    } catch (e) {
      _showErrorSnackBar('حدث خطأ أثناء الإرسال: $e');
      setState(() { _isSending = false; });
    }
  }

  String _getChatId(String uid1, String uid2) {
    return uid1.compareTo(uid2) < 0 ? '${uid1}_$uid2' : '${uid2}_$uid1';
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
        title: const Text('إعادة توجيه'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'بحث...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredChats.isEmpty
              ? _buildEmptyState(theme)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _filteredChats.length,
                  itemBuilder: (ctx, index) {
                    final item = _filteredChats[index];
                    final isSelected = _selectedChats.contains(item);

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      color: isSelected 
                          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                          : Colors.transparent,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Stack(
                          children: [
                            Hero(
                              tag: 'forward_${item.id}',
                              child: CircleAvatar(
                                radius: 26,
                                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                backgroundImage: item.imageUrl != null 
                                    ? NetworkImage(item.imageUrl!) 
                                    : null,
                                child: item.imageUrl == null
                                    ? Icon(item.isGroup ? Icons.groups : Icons.person, color: theme.colorScheme.onSurfaceVariant)
                                    : null,
                              ),
                            ),
                            if (isSelected)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _goldColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                                  ),
                                  child: const Icon(Icons.check, size: 14, color: Colors.black),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          item.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(item.isGroup ? 'مجموعة' : 'شخصي'),
                        onTap: () => _toggleSelection(item),
                        trailing: isSelected 
                            ? Icon(Icons.check_circle, color: _goldColor)
                            : const Icon(Icons.circle_outlined, color: Colors.grey),
                      ),
                    );
                  },
                ),
      floatingActionButton: _selectedChats.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _isSending ? null : _sendForwardedMessages,
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              icon: _isSending 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_isSending ? 'جاري الإرسال...' : 'إرسال (${_selectedChats.length})'),
            ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: theme.disabledColor),
          const SizedBox(height: 16),
          Text(
            _searchController.text.isEmpty ? 'لا توجد محادثات' : 'لا توجد نتائج',
            style: theme.textTheme.titleMedium?.copyWith(color: theme.disabledColor),
          ),
        ],
      ),
    );
  }
}
