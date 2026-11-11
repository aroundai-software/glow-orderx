import 'package:supabase_flutter/supabase_flutter.dart';

class EmailOtpService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Send OTP for email verification (registration)
  /// Uses Supabase Native Auth 'signInWithOtp' to deliver the code.
  Future<Map<String, dynamic>> sendRegistrationOtp(String email) async {
    try {
      print('📧 Sending registration OTP to: $email via Supabase Native Auth');

      // Use verifyOtp type logic or just signInWithOtp.
      // signInWithOtp handles both sign-up and sign-in.
      // We ensure the user exists in Supabase Auth so they can receive the email.
      await _supabase.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true, // Create Auth user if doesn't exist
      );

      print('✅ OTP sent to email: $email');

      return {
        'success': true,
        'message': 'OTP sent to email',
      };
    } catch (e) {
      print('❌ Error sending registration OTP: $e');
      
      String message = 'Failed to send OTP';
      if (e is AuthException) {
        message = e.message; // localized message from Supabase
        if (message.contains("rate limit")) {
           message = "Too many attempts. Please try again later.";
        }
      }
      
      return {
        'success': false,
        'message': message,
        'error': e.toString()
      };
    }
  }

  /// Verify OTP for registration
  Future<Map<String, dynamic>> verifyRegistrationOtp(
      String email, String otp) async {
    try {
      print('🔐 Verifying registration OTP for: $email');

      // Verify the OTP against Supabase Auth
      final response = await _supabase.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.email, // Standard email OTP
      );

      if (response.user != null) {
        print('✅ OTP verified successfully');
        return {
          'success': true,
          'message': 'OTP verified',
          'email': email,
          // We don't use the Supabase Auth Session for the app login, 
          // we just use it to prove email ownership.
        };
      } else {
         return {
          'success': false,
          'message': 'Invalid OTP',
          'error': 'INVALID_OTP'
        };
      }
    } catch (e) {
      print('❌ Error verifying OTP: $e');
      
      String message = 'Failed to verify OTP';
      if (e is AuthException) {
         message = e.message;
      }
      
      return {
        'success': false,
        'message': message,
        'error': e.toString()
      };
    }
  }

  /// Send OTP for password reset
  /// We reuse signInWithOtp because if the custom user exists but Auth user doesn't,
  /// resetPasswordForEmail would fail. signInWithOtp ensures delivery.
  Future<Map<String, dynamic>> sendPasswordResetOtp(String email) async {
    try {
      print('📧 Sending password reset OTP to: $email');

      // Check if user exists in our CUSTOM table first
      final user = await _supabase
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (user == null) {
        return {
          'success': false,
          'message': 'Email not found',
          'error': 'EMAIL_NOT_FOUND'
        };
      }

      // Send OTP via Supabase Auth
      await _supabase.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true, // Ensure we can send the code even if Auth record missing
      );

      print('✅ Password reset OTP sent to email: $email');

      return {
        'success': true,
        'message': 'OTP sent to email',
      };
    } catch (e) {
      print('❌ Error sending password reset OTP: $e');
      return {
        'success': false,
        'message': e is AuthException ? e.message : 'Failed to send OTP',
        'error': e.toString()
      };
    }
  }

  /// Verify OTP for password reset
  Future<Map<String, dynamic>> verifyPasswordResetOtp(
      String email, String otp) async {
    try {
      print('🔐 Verifying password reset OTP for: $email');

      final response = await _supabase.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.email, // magic link / signin otp
      );

       if (response.user != null) {
        print('✅ Password reset OTP verified');
        
        // Fetch the custom user ID to return
        final user = await _supabase
          .from('users')
          .select('id')
          .eq('email', email)
          .single();

        return {
          'success': true,
          'message': 'OTP verified',
          'email': email,
          'user_id': user['id'],
        };
      } else {
        return {
          'success': false,
          'message': 'Invalid OTP',
          'error': 'INVALID_OTP'
        };
      }
    } catch (e) {
      print('❌ Error verifying password reset OTP: $e');
      return {
        'success': false,
        'message': e is AuthException ? e.message : 'Failed to verify OTP',
        'error': e.toString()
      };
    }
  }

  /// Resend OTP
  Future<Map<String, dynamic>> resendOtp(String email) async {
    return sendRegistrationOtp(email);
  }
}
