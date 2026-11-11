import 'package:http/http.dart' as http;
import 'dart:convert';

class DirectEmailService {
  // Using Resend.com API (free tier available, no CORS issues)
  // Sign up at https://resend.com and get your API key
  static const String RESEND_API_KEY = 'YOUR_RESEND_API_KEY_HERE';
  static const String RESEND_API_URL = 'https://api.resend.com/emails';

  /// Send OTP email using Resend API
  static Future<bool> sendOtpEmail({
    required String recipientEmail,
    required String otp,
    required String emailType,
  }) async {
    try {
      print('📧 Sending OTP via Resend API to: $recipientEmail');

      final emailContent = _getEmailContent(otp, emailType);

      final response = await http.post(
        Uri.parse(RESEND_API_URL),
        headers: {
          'Authorization': 'Bearer $RESEND_API_KEY',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'from': 'Orderx <onboarding@resend.dev>',
          'to': recipientEmail,
          'subject': emailContent['subject'],
          'html': emailContent['html'],
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Email sent successfully via Resend');
        return true;
      } else {
        print('❌ Failed to send email: ${response.statusCode}');
        print('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Error sending email: $e');
      return false;
    }
  }

  /// Get email content based on type
  static Map<String, String> _getEmailContent(String otp, String emailType) {
    if (emailType == 'registration') {
      return {
        'subject': 'Verify Your Email - Orderx',
        'html': '''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #1976D2 0%, #0D47A1 100%); color: white; padding: 20px; border-radius: 8px; }
    .content { padding: 20px; background: #f5f5f5; border-radius: 8px; margin: 20px 0; }
    .otp-box { background: white; padding: 20px; border-radius: 8px; text-align: center; margin: 20px 0; }
    .otp-code { font-size: 32px; font-weight: bold; color: #1976D2; letter-spacing: 5px; }
    .footer { text-align: center; color: #666; font-size: 12px; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Welcome to Orderx</h1>
      <p>Verify Your Email Address</p>
    </div>
    
    <div class="content">
      <p>Thank you for registering with Orderx. Please verify your email address using the code below:</p>
      
      <div class="otp-box">
        <p>Your Verification Code:</p>
        <div class="otp-code">$otp</div>
      </div>
      
      <p>This code will expire in 10 minutes.</p>
      <p>If you didn't request this code, please ignore this email.</p>
    </div>
    
    <div class="footer">
      <p>© 2025 Orderx. All rights reserved.</p>
    </div>
  </div>
</body>
</html>
        '''
      };
    } else if (emailType == 'password_reset') {
      return {
        'subject': 'Reset Your Password - Orderx',
        'html': '''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #1976D2 0%, #0D47A1 100%); color: white; padding: 20px; border-radius: 8px; }
    .content { padding: 20px; background: #f5f5f5; border-radius: 8px; margin: 20px 0; }
    .otp-box { background: white; padding: 20px; border-radius: 8px; text-align: center; margin: 20px 0; }
    .otp-code { font-size: 32px; font-weight: bold; color: #1976D2; letter-spacing: 5px; }
    .footer { text-align: center; color: #666; font-size: 12px; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Password Reset Request</h1>
      <p>Orderx</p>
    </div>
    
    <div class="content">
      <p>We received a request to reset your password. Use the code below to proceed:</p>
      
      <div class="otp-box">
        <p>Your Reset Code:</p>
        <div class="otp-code">$otp</div>
      </div>
      
      <p>This code will expire in 10 minutes.</p>
      <p>If you didn't request this, please ignore this email and your password will remain unchanged.</p>
    </div>
    
    <div class="footer">
      <p>© 2025 Orderx. All rights reserved.</p>
    </div>
  </div>
</body>
</html>
        '''
      };
    }

    return {
      'subject': 'Orderx Verification Code',
      'html': '''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .otp-box { background: linear-gradient(135deg, #1976D2 0%, #0D47A1 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; }
    .otp-code { font-size: 32px; font-weight: bold; letter-spacing: 5px; margin: 20px 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="otp-box">
      <p>Your Verification Code:</p>
      <div class="otp-code">$otp</div>
      <p>This code will expire in 10 minutes.</p>
    </div>
  </div>
</body>
</html>
        '''
    };
  }
}
