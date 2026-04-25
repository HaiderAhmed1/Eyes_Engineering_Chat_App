import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;

class ChatService {
  static final _firestore = FirebaseFirestore.instance;
  static final _usersCollection = _firestore.collection('users');
  static final _storage = FirebaseStorage.instance.ref();

  // ========================================================================
  // --- 1. إدارة المحادثات (Chats Management) ---
  // ========================================================================

  // كتم/إلغاء كتم الإشعارات
  static Future<void> toggleMute({
    required String uid,
    required String targetId,
    required bool isGroup,
  }) async {
    try {
      final collectionName = isGroup ? 'my_groups' : 'my_chats';
      final chatDoc = _usersCollection.doc(uid).collection(collectionName).doc(targetId);
      final snapshot = await chatDoc.get();
      if (snapshot.exists) {
        final currentMute = snapshot.data()?['isMuted'] ?? false;
        await chatDoc.update({'isMuted': !currentMute});
      }
    } catch (e) {
      // Ignore
    }
  }

  // تثبيت/إلغاء تثبيت المحادثة
  static Future<void> togglePin({
    required String uid,
    required String targetId,
    required bool isGroup,
  }) async {
    try {
      final collectionName = isGroup ? 'my_groups' : 'my_chats';
      final chatDoc = _usersCollection.doc(uid).collection(collectionName).doc(targetId);
      final snapshot = await chatDoc.get();
      if (snapshot.exists) {
        final currentPin = snapshot.data()?['isPinned'] ?? false;
        await chatDoc.update({'isPinned': !currentPin});
      }
    } catch (e) {
      // Ignore
    }
  }

  // أرشفة/إلغاء أرشفة المحادثة
  static Future<void> toggleArchive({
    required String uid,
    required String targetId,
    required bool isGroup,
  }) async {
    try {
      final collectionName = isGroup ? 'my_groups' : 'my_chats';
      final chatDoc = _usersCollection.doc(uid).collection(collectionName).doc(targetId);
      final snapshot = await chatDoc.get();
      if (snapshot.exists) {
        final currentArchive = snapshot.data()?['isArchived'] ?? false;
        await chatDoc.update({'isArchived': !currentArchive});
      }
    } catch (e) {
      // Ignore
    }
  }

  // حظر مستخدم
  static Future<void> blockUser(String myId, String targetId) async {
    try {
      final myUserDoc = _usersCollection.doc(myId);
      await myUserDoc.update({
        'blockedUsers': FieldValue.arrayUnion([targetId])
      });
      // حذف المحادثة من قائمة المحادثات النشطة (اختياري)
      // await myUserDoc.collection('my_chats').doc(targetId).delete();
    } catch (e) {
      rethrow;
    }
  }

  // إلغاء حظر مستخدم
  static Future<void> unblockUser(String myId, String targetId) async {
    try {
      final myUserDoc = _usersCollection.doc(myId);
      await myUserDoc.update({
        'blockedUsers': FieldValue.arrayRemove([targetId])
      });
    } catch (e) {
      rethrow;
    }
  }

  // ========================================================================
  // --- 2. إدارة الرسائل (Message Actions) ---
  // ========================================================================

  // إضافة/حذف تفاعل (Reaction)
  static Future<void> updateMessageReaction({
    required DocumentReference messageDocRef,
    required String currentUserId,
    required String reactionEmoji,
  }) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(messageDocRef);
        if (!snapshot.exists) return;

        final data = snapshot.data() as Map<String, dynamic>? ?? {};
        final Map<String, dynamic> reactions = Map<String, dynamic>.from(data['reactions'] ?? {});

        if (reactions.containsKey(currentUserId) && reactions[currentUserId] == reactionEmoji) {
          reactions.remove(currentUserId); // إزالة التفاعل إذا تكرر النقر
        } else {
          reactions[currentUserId] = reactionEmoji; // تحديث أو إضافة التفاعل
        }

        transaction.update(messageDocRef, {'reactions': reactions});
      });
    } catch (e) {
      // Ignore
    }
  }

  // تعديل نص الرسالة
  static Future<void> editMessage({
    required DocumentReference messageDocRef,
    required String newText,
  }) async {
    try {
      await messageDocRef.update({
        'text': newText,
        'isEdited': true,
      });
    } catch (e) {
      // Ignore
    }
  }

  // حذف رسالة خاصة
  static Future<void> deletePrivateMessage({
    required DocumentReference messageDocRef,
    required CollectionReference messagesCollection,
    required DocumentReference myChatListDoc,
    required DocumentReference recipientChatListDoc,
  }) async {
    try {
      await messageDocRef.delete();
      await _updateLastMessageAfterDeletion(
        messagesCollection,
        [myChatListDoc, recipientChatListDoc],
      );
    } catch (e) {
      // Ignore
    }
  }

  // حذف رسالة مجموعة
  static Future<void> deleteGroupMessage({
    required DocumentReference messageDocRef,
    required CollectionReference messagesCollection,
    required DocumentReference groupDocRef,
  }) async {
    try {
      await messageDocRef.delete();

      // تحديث آخر رسالة في المجموعة
      await _updateLastMessageAfterDeletion(
        messagesCollection,
        [groupDocRef], // نحدث وثيقة المجموعة أولاً
      );

      // ثم نوزع التحديث على الأعضاء
      await _syncGroupLastMessageToMembers(groupDocRef);

    } catch (e) {
      // Ignore
    }
  }

  // دالة مساعدة لتحديث "آخر رسالة" بعد الحذف
  static Future<void> _updateLastMessageAfterDeletion(
      CollectionReference messagesCollection,
      List<DocumentReference> docsToUpdate,
      ) async {
    final snapshot = await messagesCollection
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    String lastMessageText = 'تم حذف رسالة';
    int? lastMessageTimestamp = DateTime.now().millisecondsSinceEpoch;
    String lastMessageType = 'text';
    String lastMessageSenderId = '';

    if (snapshot.docs.isNotEmpty) {
      final lastMessage = snapshot.docs.first.data() as Map<String, dynamic>;
      lastMessageText = _getLastMessageText(
          lastMessage['type'], lastMessage['text'], lastMessage['fileName']);
      
      if (lastMessage['isForwarded'] ?? false) {
        lastMessageText = '↪ $lastMessageText';
      }

      final timestamp = lastMessage['timestamp'] as Timestamp?;
      lastMessageTimestamp = timestamp?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
      lastMessageType = lastMessage['type'] ?? 'text';
      lastMessageSenderId = lastMessage['senderId'] ?? '';
    } else {
      lastMessageText = ''; // لا يوجد رسائل
    }

    final updateData = {
      'lastMessage': lastMessageText,
      'lastMessageTimestamp': lastMessageTimestamp,
      'lastMessageType': lastMessageType,
      'lastMessageSenderId': lastMessageSenderId,
    };

    final batch = _firestore.batch();
    for (var doc in docsToUpdate) {
      batch.set(doc, updateData, SetOptions(merge: true));
    }
    await batch.commit();
  }

  // ========================================================================
  // --- 3. الإرسال (Sending Messages) ---
  // ========================================================================
  // * ملاحظة: تم نقل منطق الإرسال المتقدم إلى ChatSender، ولكن نبقي هذه الدوال
  //   للتوافق مع الأكواد القديمة أو كواجهة مبسطة.

  static Future<void> sendPrivateDatabaseMessage({
    required CollectionReference messagesCollection,
    required DocumentReference myChatListDoc,
    required DocumentReference recipientChatListDoc,
    required String currentUserId,
    required String text,
    required String type,
    required String? fileUrl,
    required String? fileName,
    required Map<String, dynamic>? replyData,
    bool isForwarded = false,
  }) async {
    // التحقق من الحظر
    try {
      // No, recipientChatListDoc is users/TARGET/my_chats/ME. So parent.parent is target user doc.
      final recipientDocRef = recipientChatListDoc.parent.parent!;
      final recipientDoc = await recipientDocRef.get();
      
      final List<dynamic> recipientBlockedList = (recipientDoc.data()?['blockedUsers'] as List<dynamic>?) ?? [];
      if (recipientBlockedList.contains(currentUserId)) return;

      final myDoc = await _usersCollection.doc(currentUserId).get();
      final List<dynamic> myBlockedList = (myDoc.data()?['blockedUsers'] as List<dynamic>?) ?? [];
      if (myBlockedList.contains(recipientDocRef.id)) return;

      final now = DateTime.now();
      final timestamp = FieldValue.serverTimestamp();

      final newMessageRef = messagesCollection.doc();
      final batch = _firestore.batch();

      batch.set(newMessageRef, {
        'text': text,
        'fileUrl': fileUrl,
        'fileName': fileName,
        'type': type,
        'senderId': currentUserId,
        'timestamp': timestamp,
        'isRead': false,
        'status': 'sent',
        'replyTo': replyData,
        'isEdited': false,
        'reactions': {},
        'isForwarded': isForwarded,
      });

      String lastMessageText = _getLastMessageText(type, text, fileName);
      if (isForwarded) lastMessageText = '↪ $lastMessageText';

      final lastMessageData = {
        'lastMessage': lastMessageText,
        'lastMessageTimestamp': now.millisecondsSinceEpoch, // تقريبي حتى يتم التحديث الفعلي من السيرفر
        'lastMessageType': type,
        'lastMessageSenderId': currentUserId,
      };

      batch.set(myChatListDoc, lastMessageData, SetOptions(merge: true));
      batch.set(recipientChatListDoc, {
        ...lastMessageData,
        'unreadCount': FieldValue.increment(1)
      }, SetOptions(merge: true));

      await batch.commit();
    } catch (e) {
      // Ignore
    }
  }

  static Future<void> sendGroupDatabaseMessage({
    required CollectionReference messagesCollection,
    required DocumentReference groupDocRef,
    required String currentUserId,
    required String text,
    required String type,
    required String? fileUrl,
    required String? fileName,
    required Map<String, dynamic>? replyData,
    bool isForwarded = false,
    Map<String, dynamic>? extraFields,
  }) async {
    try {
      final now = DateTime.now();
      final timestamp = FieldValue.serverTimestamp();
      final newMessageRef = messagesCollection.doc();
      final batch = _firestore.batch();

      final Map<String, dynamic> messageData = {
        'text': text,
        'fileUrl': fileUrl,
        'fileName': fileName,
        'type': type,
        'senderId': currentUserId,
        'timestamp': timestamp,
        'replyTo': replyData,
        'isEdited': false,
        'reactions': {},
        'isForwarded': isForwarded,
      };
      if (extraFields != null) messageData.addAll(extraFields);

      batch.set(newMessageRef, messageData);

      String lastMessageText = _getLastMessageText(type, text, fileName);
      if (isForwarded) lastMessageText = '↪ $lastMessageText';

      final lastMessageData = {
        'lastMessage': lastMessageText,
        'lastMessageTimestamp': now.millisecondsSinceEpoch,
        'lastMessageType': type,
        'lastMessageSenderId': currentUserId,
      };

      batch.update(groupDocRef, lastMessageData);
      await batch.commit();

      // توزيع التحديث للأعضاء (خارج الـ batch لتجنب حدوده إذا المجموعة كبيرة)
      await _syncGroupLastMessageToMembers(groupDocRef, specificData: lastMessageData);

    } catch (e) {
      // Ignore
    }
  }

  // ========================================================================
  // --- 4. إدارة المجموعات (Group Info) ---
  // ========================================================================

  static Future<void> updateGroupImage({
    required String groupId,
    required File imageFile,
    required DocumentReference groupDocRef,
  }) async {
    try {
      final String storagePath = 'group_images/$groupId';
      final fileUrl = await uploadFile(imageFile, storagePath);

      await groupDocRef.update({'info.imageUrl': fileUrl});
      await _syncGroupInfoToMembers(groupDocRef, {'imageUrl': fileUrl});
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> updateGroupName({
    required String groupId,
    required String newName,
    required DocumentReference groupDocRef,
  }) async {
    try {
      await groupDocRef.update({'info.name': newName});
      await _syncGroupInfoToMembers(groupDocRef, {'name': newName});
    } catch (e) {
      rethrow;
    }
  }

  // إضافة عضو للمجموعة
  static Future<void> addGroupMembers(String groupId, List<String> newMemberIds) async {
    final groupRef = _firestore.collection('groups').doc(groupId);
    
    // 1. تحديث قائمة الأعضاء في وثيقة المجموعة
    final batch = _firestore.batch();
    
    // نفترض هيكل members: {uid: role}
    final Map<String, String> newMembersMap = {};
    for (var uid in newMemberIds) {
      newMembersMap[uid] = 'member';
    }
    
    // نستخدم merge لإضافة الأعضاء الجدد دون حذف القدامى
    batch.set(groupRef, {'members': newMembersMap}, SetOptions(merge: true));

    // 2. إضافة المجموعة لقوائم 'my_groups' للأعضاء الجدد
    final groupSnapshot = await groupRef.get();
    final groupInfo = groupSnapshot.data()?['info'] as Map<String, dynamic>? ?? {};
    
    final groupDataForUser = {
      'chatId': groupId,
      'name': groupInfo['name'] ?? 'مجموعة',
      'imageUrl': groupInfo['imageUrl'],
      'isGroup': true,
      'joinedAt': FieldValue.serverTimestamp(),
    };

    for (var uid in newMemberIds) {
      final userGroupRef = _usersCollection.doc(uid).collection('my_groups').doc(groupId);
      batch.set(userGroupRef, groupDataForUser, SetOptions(merge: true));
    }

    await batch.commit();
  }

  // إزالة عضو من المجموعة
  static Future<void> removeGroupMember(String groupId, String memberId) async {
    final groupRef = _firestore.collection('groups').doc(groupId);
    final userGroupRef = _usersCollection.doc(memberId).collection('my_groups').doc(groupId);

    final batch = _firestore.batch();

    // حذف من وثيقة المجموعة (باستخدام dot notation للحذف من Map إذا أمكن، أو قراءة-تعديل-كتابة)
    // Firestore لا يدعم حذف مفتاح من Map مباشرة بسهولة إلا بإعادة كتابة الحقل أو استخدام FieldValue.delete() على حقل كامل.
    // لذلك سنستخدم update لحذف المفتاح تحديداً باستخدام FieldValue.delete() إذا كان الحقل منفصلاً، 
    // لكن هنا members هو Map واحد. الحل: قراءة وتحديث.
    
    // لتبسيط الأمر وتجنب Race Conditions، يفضل استخدام Transaction للحذف من Map.
    // هنا سنقوم بتحديث الحقل 'members.$memberId' للحذف (Delete Field)
    batch.update(groupRef, {'members.$memberId': FieldValue.delete()});

    // حذف من قائمة المستخدم
    batch.delete(userGroupRef);

    await batch.commit();
  }

  // ========================================================================
  // --- 5. أدوات مساعدة (Helpers & Sync) ---
  // ========================================================================

  static Future<String> uploadFile(File file, String storagePath) async {
    final storageRef = _storage.child(storagePath).child(p.basename(file.path));
    await storageRef.putFile(file);
    return await storageRef.getDownloadURL();
  }

  static String _getLastMessageText(String type, String text, String? fileName) {
    switch (type) {
      case 'image': return '📷 صورة';
      case 'video': return '📹 فيديو';
      case 'audio': return '🎤 رسالة صوتية';
      case 'file': return '📎 ${fileName ?? 'ملف'}';
      case 'location': return '📍 موقع';
      case 'contact': return '👤 جهة اتصال';
      default: return text;
    }
  }

  // مزامنة معلومات المجموعة (الاسم، الصورة) للأعضاء
  static Future<void> _syncGroupInfoToMembers(DocumentReference groupDocRef, Map<String, dynamic> dataToSync) async {
    final groupSnapshot = await groupDocRef.get();
    final groupData = groupSnapshot.data() as Map<String, dynamic>?;
    final members = (groupData?['members'] as Map<dynamic, dynamic>?) ?? {};

    final batch = _firestore.batch();
    for (var memberId in members.keys) {
      final memberGroupDoc = _usersCollection.doc(memberId).collection('my_groups').doc(groupDocRef.id);
      batch.set(memberGroupDoc, dataToSync, SetOptions(merge: true));
    }
    await batch.commit();
  }

  // مزامنة "آخر رسالة" للأعضاء (من وثيقة المجموعة إلى قوائمهم)
  static Future<void> _syncGroupLastMessageToMembers(DocumentReference groupDocRef, {Map<String, dynamic>? specificData}) async {
    final groupSnapshot = await groupDocRef.get();
    final groupData = groupSnapshot.data() as Map<String, dynamic>?;
    
    Map<String, dynamic> dataToSync = specificData ?? {};
    
    if (specificData == null) {
      // إذا لم نمرر بيانات محددة، نأخذها من وثيقة المجموعة
      dataToSync = {
        'lastMessage': groupData?['lastMessage'],
        'lastMessageTimestamp': groupData?['lastMessageTimestamp'],
        'lastMessageType': groupData?['lastMessageType'],
        'lastMessageSenderId': groupData?['lastMessageSenderId'],
      };
    }

    final members = (groupData?['members'] as Map<dynamic, dynamic>?) ?? {};
    final batch = _firestore.batch();
    
    for (var memberId in members.keys) {
      final memberGroupDoc = _usersCollection.doc(memberId).collection('my_groups').doc(groupDocRef.id);
      batch.set(memberGroupDoc, dataToSync, SetOptions(merge: true));
    }
    await batch.commit();
  }

  // ========================================================================
  // --- 6. حالات الكتابة والقراءة (Status) ---
  // ========================================================================

  static Future<void> markPrivateMessagesAsRead({
    required CollectionReference messagesCollection,
    required DocumentReference myChatListDoc,
    required String currentUserId,
  }) async {
    try {
      // 1. تصفير العداد فوراً وبشكل غير مشروط عند دخول المحادثة
      // لضمان اختفاء العلامة حتى لو كانت هناك مشكلة في تزامن الرسائل
      await myChatListDoc.update({'unreadCount': 0, 'isRead': true});

      // 2. تحديث حالة الرسائل الفردية (اختياري لتوحيد الحالة)
      final querySnapshot = await messagesCollection
          .where('isRead', isEqualTo: false)
          .where('senderId', isNotEqualTo: currentUserId)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (var doc in querySnapshot.docs) {
          batch.update(doc.reference, {'isRead': true});
        }
        await batch.commit();
      }
    } catch (e) {
      // Ignore
    }
  }

  static Future<void> setPrivateTypingStatus({
    required DocumentReference recipientChatListDoc,
    required bool isTyping,
  }) async {
    try {
      await recipientChatListDoc.update({'isTyping': isTyping});
    } catch (e) {
      // Ignore
    }
  }

  static Future<void> setGroupTypingStatus({
    required DocumentReference groupDocRef,
    required String currentUserId,
    required bool isTyping,
  }) async {
    try {
      if (isTyping) {
        await groupDocRef.update({
          'typingUsers': FieldValue.arrayUnion([currentUserId])
        });
      } else {
        await groupDocRef.update({
          'typingUsers': FieldValue.arrayRemove([currentUserId])
        });
      }
    } catch (e) {
      // Ignore
    }
  }
  
  // البحث في الرسائل (ميزة متقدمة: تتطلب فهرسة أو بحث بسيط حالياً)
  static Stream<QuerySnapshot> searchMessages(CollectionReference messagesRef, String query) {
    // Firestore لا يدعم البحث النصي الكامل (Full-text search) بشكل مباشر وقوي.
    // هذا بحث بسيط يطابق البداية، أو يمكن الاعتماد على التصفية في العميل (Client-side) للنتائج القليلة.
    return messagesRef
        .where('text', isGreaterThanOrEqualTo: query)
        .where('text', isLessThan: '$query\uf8ff')
        .snapshots();
  }
}
