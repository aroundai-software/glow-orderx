import 'package:flutter/material.dart';
import 'package:Orderx/services/email_auth_service.dart';
import 'package:Orderx/services/email_otp_service.dart';
import 'package:Orderx/core/theme/app_theme.dart';

class EmailOtpVerificationScreen extends StatefulWidget {
  final String email;
  final String userId;
  final String verificationType; // 'registration' or 'password_reset'

  const EmailOtpVerificationScreen({
    super.key,
    required this.email,
    required this.userId,
    required this.verificationType,
  });

  @override
  State<EmailOtpVerificationScreen> createState() =>
      _EmailOtpVerificationScreenState();
}

class _EmailOtpVerificationScreenState
    extends State<EmailOtpVerificationScreen> {
  final _otpController = TextEditingController();
  final _otpService = EmailOtpService();
  final _emailAuthService = EmailAuthService();

  bool _isLoading = false;
  bool _isResending = false;
  int _resendCountdown = 0;
  final int _maxResendAttempts = 3;
  int _resendAttempts = 0;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the OTP'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      late Map<String, dynamic> verifyResult;

      if (widget.verificationType == 'registration') {
        verifyResult =
            await _otpService.verifyRegistrationOtp(widget.email, _otpController.text);
      } else {
        verifyResult =
            await _otpService.verifyPasswordResetOtp(widget.email, _otpController.text);
      }

      if (!mounted) return;

      if (!verifyResult['success']) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(verifyResult['message'] ?? 'OTP verification failed'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }

      // Handle based on verification type
      if (widget.verificationType == 'registration') {
        // Complete registration
        final completeResult =
            await _emailAuthService.completeEmailRegistration(
          widget.userId,
          widget.email,
        );

        if (!mounted) return;

        if (completeResult['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email verified successfully! You can now login.'),
              backgroundColor: AppTheme.success,
            ),
          );

          // Navigate to login screen
          Navigator.of(context).pushReplacementNamed('/email-login');
        } else {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  completeResult['message'] ?? 'Failed to complete registration'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      } else {
        // Password reset - navigate to reset password screen
        // Use the userId returned from verification, as the initial one might be empty/incorrect
        final userId = verifyResult['user_id'] as String? ?? widget.userId;

        Navigator.of(context).pushReplacementNamed(
          '/reset-password',
          arguments: {
            'userId': userId,
            'email': widget.email,
          },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _resendOtp() async {
    if (_resendAttempts >= _maxResendAttempts) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum resend attempts exceeded. Please try again later.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isResending = true);

    try {
      final result = await _otpService.resendOtp(widget.email);

      if (!mounted) return;

      if (result['success']) {
        setState(() {
          _isResending = false;
          _resendAttempts++;
          _resendCountdown = 30;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OTP resent to your email'),
            backgroundColor: AppTheme.success,
          ),
        );

        // Start countdown timer
        _startResendCountdown();
      } else {
        setState(() => _isResending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to resend OTP'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isResending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _startResendCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _resendCountdown > 0) {
        setState(() => _resendCountdown--);
        _startResendCountdown();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            // Icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mail_outline,
                size: 40,
                color: AppTheme.primaryBlue,
              ),
            ),
            const SizedBox(height: 24),
            // Title
            Text(
              'Verify Your Email',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // Description
            Text(
              'We sent an 8-digit code to\n${widget.email}',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // OTP Input
            TextField(
              controller: _otpController,
              decoration: InputDecoration(
                labelText: 'Enter OTP',
                hintText: '00000000',
                prefixIcon: const Icon(Icons.security),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              keyboardType: TextInputType.number,
              // Updated to 8 to accommodate Supabase token defaults
              maxLength: 8,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            // Verify Button
            ElevatedButton(
              onPressed: _isLoading ? null : _verifyOtp,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppTheme.primaryBlue,
                disabledBackgroundColor: Colors.grey[400],
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Verify OTP',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            // Resend OTP
            Column(
              children: [
                const Text(
                  "Didn't receive the code?",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                if (_resendCountdown > 0)
                  Text(
                    'Resend in ${_resendCountdown}s',
                    style: const TextStyle(
                      color: AppTheme.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else
                  GestureDetector(
                    onTap: _isResending ? null : _resendOtp,
                    child: Text(
                      'Resend OTP (${_maxResendAttempts - _resendAttempts} attempts left)',
                      style: TextStyle(
                        color: _isResending ? Colors.grey : AppTheme.primaryBlue,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            // Info Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'The OTP is valid for 10 minutes. Please check your spam folder if you don\'t see the email.',
                style: TextStyle(fontSize: 12, color: Colors.blue),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
