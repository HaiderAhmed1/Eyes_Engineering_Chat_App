/*
 * (محدث بالكامل لـ Firestore v2)
 * وظيفته: مراقبة الرسائل الجديدة في Firestore وإرسال إشعار للمستلم.
 * (جديد) إضافة تحديث حالة الرسالة إلى "delivered".
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({ region: "us-central1" });

function createNotificationBody(messageData) {
  const { type, text, fileName } = messageData;
  if (type === "image") {
    return "📷 صورة";
  } else if (type === "video") {
    return "📹 فيديو";
  } else if (type === "audio") {
    return "🎤 رسالة صوتية";
  } else if (type === "file") {
    return `📎 ${fileName || "ملف"}`;
  }
  return text;
}

// دالة إشعارات المحادثات الخاصة
exports.onNewChatMessage = onDocumentCreated(
  "/chats/{chatId}/messages/{messageId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }
    const messageData = snapshot.data();
    const senderId = messageData.senderId;
    const chatId = event.params.chatId;

    const recipientId = chatId.replace(senderId, "").replace("_", "");
    if (!recipientId) {
      console.log("Recipient not found in private chat:", chatId, senderId);
      return null;
    }

    const userDoc = await db.collection("users").doc(recipientId).get();
    const userData = userDoc.data();
    if (!userDoc.exists || !userData.fcmToken) {
      console.log("Recipient has no FCM Token:", recipientId);
      return null;
    }
    const token = userData.fcmToken;

    const senderDoc = await db.collection("users").doc(senderId).get();
    const senderName = senderDoc.data()?.name || "مستخدم";

    const notificationBody = createNotificationBody(messageData);
    const payload = {
      notification: {
        title: senderName,
        body:
          notificationBody.length > 100
            ? `${notificationBody.substring(0, 97)}...`
            : notificationBody,
        sound: "default",
      },
      data: {
        type: "private_chat",
        chatId: chatId,
        senderId: senderId,
      },
      token: token,
      apns: {
        headers: { "apns-priority": "10" },
        payload: { aps: { "content-available": 1 } },
      },
      android: { priority: "high" },
    };

    try {
      await admin.messaging().send(payload);
      console.log("Notification sent successfully to:", recipientId);

      // --- (هذا هو الإصلاح) ---
      // 6. تحديث حالة الرسالة في قاعدة البيانات إلى "delivered"
      await snapshot.ref.update({ "status": "delivered" });
      // -------------------------

    } catch (error) {
      console.error("Failed to send notification for private chat:", error);
    }
    return null;
  }
);

// دالة إشعارات المجموعات
exports.onNewGroupChatMessage = onDocumentCreated(
  "/groups/{groupId}/messages/{messageId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }
    const messageData = snapshot.data();
    const senderId = messageData.senderId;
    const groupId = event.params.groupId;

    const groupDoc = await db.collection("groups").doc(groupId).get();
    if (!groupDoc.exists) {
      console.log("Group not found:", groupId);
      return null;
    }

    const groupData = groupDoc.data() || {};
    const membersMap = groupData.members || {};
    const memberIds = Object.keys(membersMap);
    const groupName = groupData.info?.name || "مجموعة";

    const senderDoc = await db.collection("users").doc(senderId).get();
    const senderName = senderDoc.data()?.name || "مستخدم";

    const recipientIds = memberIds.filter((id) => id !== senderId);
    if (recipientIds.length === 0) {
      console.log("No recipients in group:", groupId);
      return null;
    }

    const tokenPromises = recipientIds.map((id) =>
      db.collection("users").doc(id).get()
    );
    const userSnapshots = await Promise.all(tokenPromises);

    const tokens = userSnapshots
      .map((snap) => snap.data()?.fcmToken)
      .filter((token) => token != null);

    if (tokens.length === 0) {
      console.log("No recipients in group have FCM tokens.", groupId);
      return null;
    }

    const notificationBody = createNotificationBody(messageData);
    const payload = {
      notification: {
        title: groupName,
        body: `${senderName}: ${
          notificationBody.length > 100
            ? `${notificationBody.substring(0, 97)}...`
            : notificationBody
        }`,
        sound: "default",
      },
      data: {
        type: "group_chat",
        chatId: groupId,
      },
      apns: {
        headers: { "apns-priority": "10" },
        payload: { aps: { "content-available": 1 } },
      },
      android: { priority: "high" },
    };

    try {
      await admin.messaging().sendToDevice(tokens, payload);
      console.log(`Group notification sent to ${tokens.length} members.`);

      // --- (هذا هو الإصلاح) ---
      // 6. تحديث حالة الرسالة
      await snapshot.ref.update({ "status": "delivered" });
      // -------------------------

    } catch (error) {
      console.error("Failed to send group notification:", error);
    }

    return null;
  }
);