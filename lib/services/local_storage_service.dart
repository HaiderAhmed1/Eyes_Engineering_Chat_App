import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const String _hiddenMessagesKey = 'hidden_messages';

  // دالة لجلب كل IDs الرسائل المخفية
  static Future<Set<String>> loadHiddenMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> idList = prefs.getStringList(_hiddenMessagesKey) ?? [];
    return idList.toSet(); // (استخدام Set لسرعة البحث)
  }

  // دالة لإخفاء رسالة جديدة (إضافتها للقائمة)
  static Future<void> hideMessage(String messageId) async {
    final prefs = await SharedPreferences.getInstance();
    final Set<String> hiddenMessages = await loadHiddenMessages();

    hiddenMessages.add(messageId);

    await prefs.setStringList(_hiddenMessagesKey, hiddenMessages.toList());
  }
}