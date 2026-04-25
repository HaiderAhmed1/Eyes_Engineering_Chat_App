import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chat_app/screens/user_data_check.dart';
import 'dart:convert';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _isLogin = true;
  bool _isLoading = false;

  bool _isLoadingAccounts = true;
  Map<String, String> _savedAccounts = {};
  bool _showLoginForm = false;

  String _userEmail = '';
  String _userPassword = '';
  String _userPhone = '';

  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _isLogin = true;
    _isLoading = false;

    if (_auth.currentUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (ctx) => UserDataCheck(key: ValueKey(_auth.currentUser!.uid))),
        );
      });
    } else {
      _loadSavedAccounts();
    }
  }

  void _loadSavedAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accountsJson = prefs.getString('saved_accounts');
      if (accountsJson != null) {
        _savedAccounts = Map<String, String>.from(json.decode(accountsJson));
      } else {
        _savedAccounts = {};
      }

      final showList = prefs.getBool('show_account_list') ?? true;

      if (_savedAccounts.isEmpty) {
        _showLoginForm = true;
      } else if (showList == false) {
        _showLoginForm = true;
      } else {
        _showLoginForm = false;
      }

      if (mounted) {
        setState(() {
          _isLoadingAccounts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _showLoginForm = true;
          _isLoadingAccounts = false;
        });
      }
    }
  }

  Future<void> _saveAccount(String email, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _savedAccounts[email] = password;
      await prefs.setString('saved_accounts', json.encode(_savedAccounts));
      if (mounted) setState(() {});
    } catch (e) {
      // ignore
    }
  }

  void _switchAccount(String email, String password) async {
    setState(() { _isLoading = true; });
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'فشل تسجيل الدخول');
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  void _submitForm() async {
    final isValid = _formKey.currentState?.validate();
    if (isValid == null || !isValid) return;

    _formKey.currentState!.save();
    setState(() { _isLoading = true; });

    UserCredential userCredential;

    try {
      if (_isLogin) {
        userCredential = await _auth.signInWithEmailAndPassword(
          email: _userEmail,
          password: _userPassword,
        );
      } else {
        // 1. إنشاء الحساب في Authentication
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: _userEmail,
          password: _userPassword,
        );

        final user = userCredential.user;
        if (user != null) {
          try {
            // 2. محاولة الحفظ في Firestore
            final duplicateCheck = await FirebaseFirestore.instance
                .collection('users')
                .where('phoneNumber', isEqualTo: _userPhone)
                .get();

            if (duplicateCheck.docs.isNotEmpty) {
              await user.delete(); // تراجع
              if (mounted) {
                _showError('رقم الهاتف هذا مسجل مسبقاً، يرجى استخدام رقم آخر أو تسجيل الدخول.');
                setState(() { _isLoading = false; });
              }
              return;
            }

            final userDocRef = _firestore.collection('users').doc(user.uid);

            await userDocRef.set({
              'uid': user.uid,
              'email': _userEmail,
              'phoneNumber': _userPhone,
              'createdAt': DateTime.now().toIso8601String(),
              'name': null,
              'displayName': null,
              'bio': null,
              'imageUrl': null,
              'isOnline': true,
              'lastSeen': DateTime.now().toIso8601String(),
              'blockedUsers': [],
            });

          } catch (firestoreError) {
            // 🚨 أهم تعديل: التراجع! إذا فشل الفايرستور، احذف الحساب من الـ Auth فوراً
            await user.delete();
            throw Exception('تعذر تهيئة قاعدة البيانات للحساب الجديد، يرجى المحاولة مرة أخرى.');
          }
        }
      }

      await _saveAccount(_userEmail, _userPassword);

    } on FirebaseAuthException catch (e) {
      String message = 'حدث خطأ ما.';
      if (e.code == 'email-already-in-use') {
        message = 'البريد الإلكتروني هذا مسجل مسبقاً، حاول تسجيل الدخول.';
      } else if (e.code == 'invalid-credential' || e.code == 'wrong-password') {
        message = 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
      } else if (e.message != null) {
        message = e.message!;
      }
      _showError(message);
      if (mounted) setState(() { _isLoading = false; });
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Widget _buildLoginForm(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('email'),
            keyboardType: TextInputType.emailAddress,
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(
              labelText: 'البريد الإلكتروني',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (value) {
              if (value == null || !value.contains('@')) {
                return 'الرجاء إدخال بريد إلكتروني صالح.';
              }
              return null;
            },
            onSaved: (value) { _userEmail = value?.trim() ?? ''; },
          ),
          const SizedBox(height: 20),

          if (!_isLogin) ...[
            TextFormField(
              key: const ValueKey('phone'),
              keyboardType: TextInputType.phone,
              style: theme.textTheme.bodyLarge,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف',
                hintText: '07xxxxxxxxx',
                prefixIcon: Icon(Icons.phone_iphone),
              ),
              validator: (value) {
                if (value == null || value.trim().length < 10) {
                  return 'الرجاء إدخال رقم هاتف صحيح.';
                }
                return null;
              },
              onSaved: (value) { _userPhone = value?.trim() ?? ''; },
            ),
            const SizedBox(height: 20),
          ],

          TextFormField(
            key: const ValueKey('password'),
            obscureText: _obscurePassword,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              labelText: 'كلمة المرور',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().length < 6) {
                return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل.';
              }
              return null;
            },
            onSaved: (value) { _userPassword = value?.trim() ?? ''; },
          ),
          const SizedBox(height: 30),

          ElevatedButton(
            onPressed: _isLoading ? null : _submitForm,
            child: _isLoading
                ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            )
                : Text(_isLogin ? 'تسجيل الدخول' : 'إنشاء حساب'),
          ),
          const SizedBox(height: 16),

          TextButton(
            onPressed: _isLoading
                ? null
                : () => setState(() { _isLogin = !_isLogin; }),
            child: Text(_isLogin
                ? 'ليس لديك حساب؟ إنشاء حساب جديد'
                : 'لديك حساب بالفعل؟ تسجيل الدخول'),
          ),

          if (_savedAccounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: TextButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('العودة للحسابات المحفوظة'),
                onPressed: _isLoading
                    ? null
                    : () => setState(() {
                  _showLoginForm = false;
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAccountList(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._savedAccounts.entries.map((entry) {
          final email = entry.key;
          final password = entry.value;
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: CircleAvatar(
                radius: 25,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(Icons.person, color: theme.colorScheme.onPrimaryContainer),
              ),
              title: Text(email, style: theme.textTheme.titleMedium),
              subtitle: const Text('اضغط لتسجيل الدخول'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _isLoading ? null : () => _switchAccount(email, password),
            ),
          );
        }),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('تسجيل الدخول بحساب آخر'),
          onPressed: () {
            setState(() {
              _showLoginForm = true;
              _isLogin = true;
            });
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.2),
                        blurRadius: 30,
                        spreadRadius: 10,
                      )
                    ],
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 60,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 32),

                Text(
                  'عيون الهندسة',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: theme.colorScheme.onBackground,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _showLoginForm
                      ? (_isLogin ? 'مرحباً بعودتك' : 'انضم إلينا اليوم')
                      : 'اختر حساباً للمتابعة',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onBackground.withOpacity(0.7),
                  ),
                ),

                const SizedBox(height: 48),

                if (_isLoadingAccounts)
                  const Center(child: CircularProgressIndicator())
                else if (_showLoginForm)
                  _buildLoginForm(theme)
                else
                  _buildAccountList(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }
}