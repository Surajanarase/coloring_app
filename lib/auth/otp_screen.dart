// lib/auth/otp_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../pages/dashboard_page.dart';

class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  const OtpScreen({super.key, required this.phoneNumber});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _otpCtrl = TextEditingController();
  bool _verifying = false;

  static const int _resendDelay = 30;
  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _startResendCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _startResendCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendDelay);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;

    final otp = _otpCtrl.text.trim();
    setState(() => _verifying = true);

    // simulate verification delay
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _verifying = false);

    if (otp == '1234') {
      // Navigate to Dashboard (replace current route so user can't press back to OTP)
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DashboardPage()),
        (route) => false,
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid code — demo OTP is 1234')),
      );
    }
  }

  void _resendOtp() {
    if (_secondsLeft > 0) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('OTP resent (demo)')));
    _startResendCountdown();
  }

  String? _otpValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter OTP';
    if (!RegExp(r'^\d{4,6}$').hasMatch(v.trim())) return 'Enter a 4-6 digit code';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFFBF6FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        title: Text('Verify ${widget.phoneNumber}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _verifying ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            width: (760.0
                    .clamp(320.0, MediaQuery.of(context).size.width * 0.95))
                .toDouble(),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x11000000),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter the code',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'We sent a code to your phone. It may take a minute.',
                  textAlign: TextAlign.center,
                  style:
                      theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                ),
                const SizedBox(height: 16),
                Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(letterSpacing: 8, fontSize: 18),
                    decoration: InputDecoration(
                      hintText: '----',
                      filled: true,
                      fillColor: const Color(0xFFF8F6FB),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    validator: _otpValidator,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: 180,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _verifying ? null : _verify,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      backgroundColor: Colors.deepPurple,
                    ),
                    child: _verifying
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.2),
                          )
                        : const Text(
                            'Verify',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              letterSpacing: 0.5,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _secondsLeft == 0 ? _resendOtp : null,
                      child: Text(
                        _secondsLeft == 0
                            ? 'Resend code'
                            : 'Resend in $_secondsLeft s',
                        style: TextStyle(
                            color: _secondsLeft == 0
                                ? Colors.deepPurple
                                : Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () {
                        if (!_verifying) Navigator.of(context).pop();
                      },
                      child: const Text('Edit number',
                          style: TextStyle(color: Colors.black87)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
