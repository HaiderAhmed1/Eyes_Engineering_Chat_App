import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:chat_app/screens/auth_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedTone = 'default';
  bool _notificationsEnabled = true;

  final Map<String, String> _tones = {
    'default': 'الافتراضي',
    'chirp': 'تغريد',
    'galaxy': 'مجرة',
    'orbit': 'مدار',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedTone = prefs.getString('notification_tone') ?? 'default';
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
    });
  }

  Future<void> _saveTone(String tone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notification_tone', tone);
    setState(() {
      _selectedTone = tone;
    });
    // هنا يمكن تشغيل صوت النغمة للمعاينة لاحقاً
  }

  Future<void> _toggleNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', value);
    setState(() {
      _notificationsEnabled = value;
    });
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('تفعيل الإشعارات'),
            value: _notificationsEnabled,
            onChanged: _toggleNotifications,
            secondary: Icon(
              _notificationsEnabled ? Icons.notifications_active : Icons.notifications_off,
              color: theme.colorScheme.primary,
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('نغمة الإشعار'),
            subtitle: Text(_tones[_selectedTone] ?? _selectedTone),
            leading: Icon(Icons.music_note, color: theme.colorScheme.primary),
            enabled: _notificationsEnabled,
            onTap: _notificationsEnabled ? () => _showToneSelector(context) : null,
          ),
          const Divider(),
          ListTile(
            title: const Text('تسجيل الخروج', style: TextStyle(color: Colors.red)),
            leading: const Icon(Icons.logout, color: Colors.red),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  void _showToneSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('اختر نغمة', style: Theme.of(context).textTheme.titleLarge),
            ),
            ..._tones.entries.map((entry) => RadioListTile<String>(
              title: Text(entry.value),
              value: entry.key,
              groupValue: _selectedTone,
              onChanged: (val) {
                if (val != null) {
                  _saveTone(val);
                  Navigator.pop(ctx);
                }
              },
            )),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}
