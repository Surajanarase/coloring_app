// COMPLETE READY-TO-USE login_screen.dart
// Replace your entire lib/auth/login_screen.dart file with this code

import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../pages/dashboard_page.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DbService();

  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _fullnameCtrl = TextEditingController();
  final TextEditingController _ageCtrl = TextEditingController();

  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _isRegisterMode = false;
  bool _loading = false;
  bool _obscure = true;
  String? _gender;
  final List<String> _genderOptions = ['Male', 'Female'];

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _fullnameCtrl.dispose();
    _ageCtrl.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    setState(() => _loading = true);

    try {
      if (_isRegisterMode) {
        final fullname = _fullnameCtrl.text.trim();
        final ageText = _ageCtrl.text.trim();
        final age = ageText.isEmpty ? null : int.tryParse(ageText);

        final result = await _db.createUser(username, password,
            fullname: fullname, age: age, gender: _gender);

        if (!mounted) return;
        setState(() => _loading = false);

        if (result == 'exists') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Username already exists. Pick another.')),
          );
          return;
        } else if (result != 'ok') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('⚠️ Error creating account: $result')),
          );
          return;
        }

        _db.setCurrentUser(username);

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DashboardPage(username: username)),
        );
      } else {
        final valid = await _db.authenticateUser(username, password);

        if (!mounted) return;
        setState(() => _loading = false);

        if (!valid) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Invalid username or password')),
          );
          return;
        }

        _db.setCurrentUser(username);

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DashboardPage(username: username)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
    }
  }

  void _toggleMode() {
    _formKey.currentState?.reset();
    _usernameCtrl.clear();
    _passwordCtrl.clear();
    _fullnameCtrl.clear();
    _ageCtrl.clear();
    _gender = null;
    FocusScope.of(context).unfocus();
    
    setState(() {
      _isRegisterMode = !_isRegisterMode;
    });
  }

  Future<void> _deleteAccount() async {
    if (!mounted) return;

    // Show dialog to re-enter credentials
    final credentials = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DeleteAccountDialog(),
    );

    if (credentials == null || !mounted) return;

    final username = credentials['username']!;
    final password = credentials['password']!;

    setState(() => _loading = true);

    try {
      final valid = await _db.authenticateUser(username, password);

      if (!mounted) return;

      if (!valid) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Invalid username or password'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final finalConfirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('⚠️ Final Confirmation'),
          content: Text(
            'Delete account "$username"?\n\nThis will permanently delete:\n• Your account\n• All your coloring progress\n• All saved images\n\nThis action CANNOT be undone!',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('DELETE FOREVER'),
            ),
          ],
        ),
      );

      if (finalConfirm != true || !mounted) {
        setState(() => _loading = false);
        return;
      }

      await _db.deleteUser(username);

      if (!mounted) return;
      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Account deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );

      _usernameCtrl.clear();
      _passwordCtrl.clear();
      _fullnameCtrl.clear();
      _ageCtrl.clear();
      setState(() {
        _gender = null;
        _isRegisterMode = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting account: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildLogo() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final logoSize = MediaQuery.of(context).size.width * 0.4;
        final clampedLogoSize = logoSize.clamp(120.0, 180.0);
        
        return Column(
          children: [
            Image.asset(
              'assets/logo.png',
              width: clampedLogoSize,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite, color: Colors.red, size: clampedLogoSize * 0.25),
                  SizedBox(width: clampedLogoSize * 0.04),
                  Flexible(
                    child: Text(
                      "COLOURS TO SAVE HEARTS",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                        fontSize: clampedLogoSize * 0.08,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.02),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final safePadding = mediaQuery.padding;
    
    final horizontalPadding = screenWidth * 0.05;
    final verticalPadding = screenHeight * 0.02;
    
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF9ABAFF),
                  Color(0xFFECE17E),
                  Color(0xFF8EDF79),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.48, 1.0],
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding.clamp(16.0, 40.0),
                  vertical: verticalPadding.clamp(10.0, 20.0),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 600,
                    minHeight: screenHeight - safePadding.top - safePadding.bottom,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLogo(),
                      Container(
                        padding: EdgeInsets.all(screenWidth * 0.05),
                        margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.02),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color.fromRGBO(255, 255, 255, 0.95),
                              Color.fromRGBO(255, 255, 255, 0.85),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 12,
                              offset: Offset(0, 6),
                            )
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _isRegisterMode ? 'Create account' : 'Welcome back',
                                style: TextStyle(
                                  fontSize: (screenWidth * 0.05).clamp(18.0, 24.0),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: screenHeight * 0.01),
                              Text(
                                _isRegisterMode
                                    ? 'Fill in your details to create account'
                                    : 'Use username and password to sign in',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: (screenWidth * 0.035).clamp(12.0, 16.0),
                                ),
                              ),
                              SizedBox(height: screenHeight * 0.02),

                              if (_isRegisterMode) ...[
                                TextFormField(
                                  controller: _fullnameCtrl,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: 'Full name',
                                    filled: true,
                                    fillColor: const Color.fromRGBO(255, 255, 255, 0.9),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    prefixIcon: const Icon(Icons.person),
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: screenHeight * 0.02,
                                      horizontal: screenWidth * 0.04,
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Enter full name';
                                    }
                                    if (v.trim().length < 3) {
                                      return 'At least 3 characters';
                                    }
                                    return null;
                                  },
                                  onFieldSubmitted: (_) => _usernameFocus.requestFocus(),
                                ),
                                SizedBox(height: screenHeight * 0.015),
                                TextFormField(
                                  controller: _ageCtrl,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: 'Age',
                                    filled: true,
                                    fillColor: const Color.fromRGBO(255, 255, 255, 0.9),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    prefixIcon: const Icon(Icons.cake),
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: screenHeight * 0.02,
                                      horizontal: screenWidth * 0.04,
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Enter age';
                                    }
                                    final n = int.tryParse(v.trim());
                                    if (n == null || n <= 0) return 'Enter a valid age';
                                    return null;
                                  },
                                  onFieldSubmitted: (_) => _usernameFocus.requestFocus(),
                                ),
                                SizedBox(height: screenHeight * 0.015),
                                DropdownButtonFormField<String>(
                                  decoration: InputDecoration(
                                    labelText: 'Gender',
                                    filled: true,
                                    fillColor: const Color.fromRGBO(255, 255, 255, 0.9),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    prefixIcon: const Icon(Icons.transgender),
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: screenHeight * 0.02,
                                      horizontal: screenWidth * 0.04,
                                    ),
                                  ),
                                  hint: const Text('Select Gender'),
                                  isExpanded: true,
                                  items: _genderOptions
                                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) setState(() => _gender = v);
                                  },
                                  validator: (v) {
                                    if (v == null) return 'Please select gender';
                                    return null;
                                  },
                                  menuMaxHeight: screenHeight * 0.3,
                                ),
                                SizedBox(height: screenHeight * 0.015),
                              ],

                              TextFormField(
                                controller: _usernameCtrl,
                                focusNode: _usernameFocus,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username],
                                decoration: InputDecoration(
                                  labelText: 'Username',
                                  filled: true,
                                  fillColor: const Color.fromRGBO(255, 255, 255, 0.9),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  prefixIcon: const Icon(Icons.person_outline),
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: screenHeight * 0.02,
                                    horizontal: screenWidth * 0.04,
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Enter username';
                                  }
                                  if (v.trim().length < 3) {
                                    return 'At least 3 characters';
                                  }
                                  return null;
                                },
                                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                              ),
                              SizedBox(height: screenHeight * 0.015),

                              TextFormField(
                                controller: _passwordCtrl,
                                focusNode: _passwordFocus,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  filled: true,
                                  fillColor: const Color.fromRGBO(255, 255, 255, 0.9),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _obscure ? 'Show password' : 'Hide password',
                                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: screenHeight * 0.02,
                                    horizontal: screenWidth * 0.04,
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Enter password';
                                  }
                                  if (v.length < 4) {
                                    return 'At least 4 characters';
                                  }
                                  return null;
                                },
                                onFieldSubmitted: (_) {
                                  if (!_loading) _submit();
                                },
                              ),

                              SizedBox(height: screenHeight * 0.025),

                              SizedBox(
                                width: double.infinity,
                                height: (screenHeight * 0.06).clamp(44.0, 56.0),
                                child: ElevatedButton(
                                  onPressed: _loading ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: const Color.fromRGBO(33, 150, 243, 0.3),
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 4,
                                  ),
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color.fromRGBO(33, 150, 243, 0.8),
                                          Color.fromRGBO(63, 81, 181, 0.8),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Container(
                                      alignment: Alignment.center,
                                      child: _loading
                                          ? SizedBox(
                                              width: (screenHeight * 0.03).clamp(20.0, 24.0),
                                              height: (screenHeight * 0.03).clamp(20.0, 24.0),
                                              child: const CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.2,
                                              ),
                                            )
                                          : Text(
                                              _isRegisterMode ? 'Create account' : 'Sign in',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: (screenWidth * 0.04).clamp(14.0, 18.0),
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),

                              SizedBox(height: screenHeight * 0.015),

                              TextButton(
                                onPressed: _loading ? null : _toggleMode,
                                child: Text(
                                  _isRegisterMode
                                      ? 'Already have an account? Sign in'
                                      : 'Don\'t have an account? Register',
                                  style: TextStyle(
                                    fontSize: (screenWidth * 0.035).clamp(12.0, 16.0),
                                  ),
                                ),
                              ),

                              if (!_isRegisterMode) ...[
                                SizedBox(height: screenHeight * 0.008),
                                TextButton(
                                  onPressed: _loading ? null : _deleteAccount,
                                  child: Text(
                                    'Delete my account',
                                    style: TextStyle(
                                      fontSize: (screenWidth * 0.035).clamp(12.0, 16.0),
                                      color: Colors.red,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],

                              SizedBox(height: screenHeight * 0.008),
                              Text(
                                "This app helps children learn colours and spread awareness ❤️",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: (screenWidth * 0.03).clamp(10.0, 14.0),
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.02),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Delete Account Dialog Widget
class _DeleteAccountDialog extends StatefulWidget {
  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
          SizedBox(width: 8),
          Text('Delete Account'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your credentials to confirm account deletion:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Username',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Enter your username';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              validator: (v) {
                if (v == null || v.isEmpty) {
                  return 'Enter your password';
                }
                return null;
              },
              onFieldSubmitted: (_) {
                if (_formKey.currentState!.validate()) {
                  Navigator.pop(context, {
                    'username': _usernameController.text.trim(),
                    'password': _passwordController.text,
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This will permanently delete all your data!',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'username': _usernameController.text.trim(),
                'password': _passwordController.text,
              });
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}