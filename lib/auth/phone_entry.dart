// lib/auth/phone_entry.dart
import 'package:flutter/material.dart';
import 'otp_screen.dart';

class PhoneEntryScreen extends StatefulWidget {
  const PhoneEntryScreen({super.key});
  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneCtrl = TextEditingController(text: '+91');
  bool _sending = false;

  late final AnimationController _animController;
  late final Animation<double> _cardElevation;

  @override
  void initState() {
    super.initState();
    _animController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _cardElevation = Tween<double>(begin: 0, end: 6).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    final phone = _phoneCtrl.text.trim();
    setState(() => _sending = true);

    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;
    setState(() => _sending = false);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OtpScreen(phoneNumber: phone)),
    );
  }

  String? _phoneValidator(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter phone number';
    final cleaned = value.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^\+\d{6,15}$').hasMatch(cleaned)) {
      return 'Use international format, e.g. +919876543210';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: AnimatedBuilder(
              animation: _animController,
              builder: (_, __) => Material(
                elevation: _cardElevation.value,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: (760.0
                          .clamp(320.0, MediaQuery.of(context).size.width * 0.95))
                      .toDouble(),
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: Color(0x22000000), blurRadius: 12)
                          ],
                        ),
                        child: const Center(child: Text('🎨', style: TextStyle(fontSize: 40))),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'ColorFun',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Creative coloring for kids',
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 18),
                      Form(
                        key: _formKey,
                        child: TextFormField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: '+919876543210',
                            labelText: 'Phone number',
                            prefixIcon: const Icon(Icons.phone_iphone_rounded),
                            filled: true,
                            fillColor: const Color(0xFFF8F6FB),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 18, horizontal: 14),
                          ),
                          validator: _phoneValidator,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _sending ? null : _sendOtp,
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                            backgroundColor: const Color(0xFF667EEA),
                          ),
                          child: _sending
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.2,
                                  ))
                              : const Text(
                                  'Send OTP',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Demo OTP = 1234.',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 6),
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
