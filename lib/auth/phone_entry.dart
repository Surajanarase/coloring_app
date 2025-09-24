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
    _cardElevation = Tween<double>(begin: 0, end: 10).animate(
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

    // simulate network delay
    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;
    setState(() => _sending = false);

    // show demo OTP (like the HTML "alert('Demo OTP: 123456')")
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Demo OTP'),
        content: const Text('Your demo OTP is: 123456'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );

    if (!mounted) return;
    // navigate to OTP screen (preserve same behavior as before)
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => OtpScreen(phoneNumber: phone)));
  }

  String? _phoneValidator(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter phone number';
    final cleaned = value.replaceAll(RegExp(r'\s+'), '');
    // allow international plus sign and 6-15 digits (very permissive)
    if (!RegExp(r'^\+\d{6,15}$').hasMatch(cleaned)) {
      return 'Use international format, e.g. +919876543210';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardWidth = (760.0.clamp(320.0, MediaQuery.of(context).size.width * 0.92)).toDouble();

    return Scaffold(
      // Use a gradient background similar to your HTML screenshot
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF9ABAFF), // soft blue
              Color(0xFFECE17E), // pale yellow/green
              Color(0xFF8EDF79), // soft green
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.48, 1.0],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: AnimatedBuilder(
              animation: _animController,
              builder: (_, __) => Material(
                elevation: _cardElevation.value,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: cardWidth,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // circular logo
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 6))
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

                      // the white card area for inputs (rounded)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFFFF),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(color: Color(0x11000000), blurRadius: 6, offset: Offset(0, 4))
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Phone Number', style: TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _phoneCtrl,
                                keyboardType: TextInputType.phone,
                                decoration: InputDecoration(
                                  hintText: 'Enter phone number',
                                  prefixIcon: const Icon(Icons.phone_iphone_rounded),
                                  filled: true,
                                  fillColor: const Color(0xFFF8F6FB),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                                ),
                                validator: _phoneValidator,
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _sending ? null : _sendOtp,
                                  style: ElevatedButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: 0,
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(colors: [Color(0xFF667EEA), Color(0xFF764BA2)]),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Container(
                                      alignment: Alignment.center,
                                      child: _sending
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                                            )
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
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Demo OTP = 123456',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),
                      // small helper text or footer if you want
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
