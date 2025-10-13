// lib/auth/login_screen.dart

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

  // New controllers for registration fields
  final TextEditingController _fullnameCtrl = TextEditingController();
  final TextEditingController _ageCtrl = TextEditingController();

  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _isRegisterMode = false;
  bool _loading = false;
  bool _obscure = true;

  // gender state - FIXED: Made nullable
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
        // Collect register-only fields
        final fullname = _fullnameCtrl.text.trim();
        final ageText = _ageCtrl.text.trim();
        final age = ageText.isEmpty ? null : int.tryParse(ageText);

        // Create new user (db.createUser updated to accept these)
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

        // Set current user (important for per-user DB)
        _db.setCurrentUser(username);

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DashboardPage(username: username)),
        );
      } else {
        // Login existing user
        final valid = await _db.authenticateUser(username, password);

        if (!mounted) return;
        setState(() => _loading = false);

        if (!valid) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Invalid username or password')),
          );
          return;
        }

        // Set current user (important for per-user DB)
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
    setState(() {
      _isRegisterMode = !_isRegisterMode;
    });
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Image.asset(
          'assets/logo.png',
          width: 180,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite, color: Colors.red, size: 46),
              SizedBox(width: 8),
              Text(
                "COLOURS TO SAVE HEARTS",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              )
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Top gradient colors in original file:
    // Color(0xFF9ABAFF), Color(0xFFECE17E), Color(0xFF8EDF79)
    // They were previously used with withOpacity(1.0) — that's equivalent to the base colors.
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: Container(
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLogo(),
                  Container(
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      // Replace Colors.white.withOpacity(0.95) etc with Color.fromRGBO
                      gradient: LinearGradient(
                        colors: const [
                          // white @ 95%
                          Color.fromRGBO(255, 255, 255, 0.95),
                          // white @ 85%
                          Color.fromRGBO(255, 255, 255, 0.85),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 6))
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isRegisterMode ? 'Create account' : 'Welcome back',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Use username and password to sign in',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),

                          // If registering, show Full name, Age, Gender first (new)
                          if (_isRegisterMode) ...[
                            TextFormField(
                              controller: _fullnameCtrl,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Full name',
                                filled: true,
                                fillColor: Color.fromRGBO(255, 255, 255, 0.9),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                prefixIcon: const Icon(Icons.person),
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
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _ageCtrl,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Age',
                                filled: true,
                                fillColor: Color.fromRGBO(255, 255, 255, 0.9),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                prefixIcon: const Icon(Icons.cake),
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
                            const SizedBox(height: 12),
                            // Gender dropdown - FIXED
                            DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                labelText: 'Gender',
                                filled: true,
                                fillColor: Color.fromRGBO(255, 255, 255, 0.9),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                prefixIcon: const Icon(Icons.transgender),
                              ),
                              hint: const Text('Select Gender'),
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
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Username
                          TextFormField(
                            controller: _usernameCtrl,
                            focusNode: _usernameFocus,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            decoration: InputDecoration(
                              labelText: 'Username',
                              filled: true,
                              fillColor: Color.fromRGBO(255, 255, 255, 0.9),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.person_outline),
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
                            onFieldSubmitted: (_) {
                              _passwordFocus.requestFocus();
                            },
                          ),
                          const SizedBox(height: 12),

                          // Password
                          TextFormField(
                            controller: _passwordCtrl,
                            focusNode: _passwordFocus,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: 'Password',
                              filled: true,
                              fillColor: Color.fromRGBO(255, 255, 255, 0.9),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscure ? 'Show password' : 'Hide password',
                                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _obscure = !_obscure),
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

                          const SizedBox(height: 18),

                          // Submit Button
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                // Replace shadow color with explicit RGBO to avoid withOpacity
                                shadowColor: Color.fromRGBO(33, 150, 243, 0.3),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 4,
                              ),
                              child: Ink(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: const [
                                      // Colors.blue.withOpacity(0.8) -> Color.fromRGBO(33,150,243,0.8)
                                      Color.fromRGBO(33, 150, 243, 0.8),
                                      // Colors.indigo.withOpacity(0.8) -> Color.fromRGBO(63,81,181,0.8)
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
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.2,
                                          ),
                                        )
                                      : Text(
                                          _isRegisterMode ? 'Create account' : 'Sign in',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Toggle Register/Login
                          TextButton(
                            onPressed: _loading ? null : _toggleMode,
                            child: Text(
                              _isRegisterMode ? 'Already have an account? Sign in' : 'Don\'t have an account? Register',
                            ),
                          ),

                          const SizedBox(height: 6),
                          const Text(
                            "This app helps children learn colours and spread awareness ❤️",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}