import 'package:Orderx/models/user_model.dart';
import 'package:Orderx/services/email_otp_service.dart';
import 'package:Orderx/services/password_reset_service.dart';
import 'package:Orderx/services/session_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';

class EmailAuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SessionService _sessionService = SessionService();
  final EmailOtpService _otpService = EmailOtpService();
  final PasswordResetService _passwordResetService = PasswordResetService();

  /// Hash password using SHA256
  String _hashPassword(String password) {
    return sha256.convert(password.codeUnits).toString();
  }

  /// Register new user with email (admin or salesman)
  /// For admin: requires company email verification
  /// For salesman: standard email verification
  Future<Map<String, dynamic>> registerWithEmail({
    required String email,
    required String name,
    required String userType, // 'admin' or 'salesman'
    required String password,
    String? companyId,
    String? companyEmailFromSettings, // Required for admin registration
  }) async {
    try {
      print('📧 Registering user with email: $email, type: $userType');

      // Validate password strength
      final passwordValidation =
          _passwordResetService.validatePassword(password);
      if (!passwordValidation['isValid']) {
        return {
          'success': false,
          'message': 'Password does not meet requirements',
          'errors': passwordValidation['errors'],
          'error': 'WEAK_PASSWORD'
        };
      }

      // For admin registration, verify company email
      if (userType == 'admin') {
        if (companyEmailFromSettings == null || companyEmailFromSettings.isEmpty) {
          return {
            'success': false,
            'message':
                'Admin registration requires company email verification',
            'error': 'COMPANY_EMAIL_REQUIRED'
          };
        }

        // Verify that the provided email matches company settings email
        if (email != companyEmailFromSettings) {
          return {
            'success': false,
            'message':
                'Email must match the company email from company settings',
            'error': 'EMAIL_MISMATCH'
          };
        }
      }

      // Check if email already exists
      final existingUser = await _supabase
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (existingUser != null) {
        return {
          'success': false,
          'message': 'Email already registered',
          'error': 'EMAIL_EXISTS'
        };
      }

      // Hash password
      final passwordHash = _hashPassword(password);

      // Generate a placeholder mobile number for email-based users
      // Use first 14 chars of email hash to ensure uniqueness and fit 15 char limit
      final emailHash = sha256.convert(email.codeUnits).toString().substring(0, 14);
      final placeholderMobile = emailHash;

      // Create user with email_verified = false (will be set to true after OTP verification)
      // Salesmen are registered as inactive (is_active = false) until admin approval
      final response = await _supabase.from('users').insert({
        'email': email,
        'name': name,
        'user_type': userType,
        'password_hash': passwordHash,
        'email_verified': false,
        'is_active': userType == 'admin', // Admins active by default, salesmen need approval
        'company_id': companyId,
        'mobile_number': placeholderMobile,
      }).select().single();

      final userId = response['id'] as String;

      print('✅ User created: $userId');

      return {
        'success': true,
        'message': 'User registered successfully. Please verify your email.',
        'user_id': userId,
        'email': email,
      };
    } catch (e) {
      print('❌ Registration error: $e');
      return {
        'success': false,
        'message': 'Registration failed',
        'error': e.toString()
      };
    }
  }

  /// Complete email registration after OTP verification
  Future<Map<String, dynamic>> completeEmailRegistration(
      String userId, String email) async {
    try {
      print('✅ Completing email registration for: $email');

      // Mark email as verified
      await _supabase.from('users').update({
        'email_verified': true,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      // Get updated user data
      final userResponse = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .single();

      print('✅ Email verified successfully');

      return {
        'success': true,
        'message': 'Email verified successfully',
        'user': UserModel.fromJson(userResponse),
      };
    } catch (e) {
      print('❌ Error completing registration: $e');
      return {
        'success': false,
        'message': 'Failed to complete registration',
        'error': e.toString()
      };
    }
  }

  /// Login with email and password
  Future<Map<String, dynamic>> loginWithEmail(
      String email, String password) async {
    try {
      print('🔐 Logging in with email: $email');

      // Find user by email (don't filter by is_active yet to provide better feedback)
      final response = await _supabase
          .from('users')
          .select()
          .eq('email', email)
          .maybeSingle();

      if (response == null) {
        return {
          'success': false,
          'message': 'Email not found',
          'error': 'USER_NOT_FOUND'
        };
      }

      // Check if user is active (admin approval check)
      if (response['is_active'] != true) {
        return {
          'success': false,
          'message': 'Your account is pending admin approval. Please contact your administrator.',
          'error': 'ACCOUNT_INACTIVE'
        };
      }

      // Check if email is verified
      if (response['email_verified'] != true) {
        return {
          'success': false,
          'message': 'Please verify your email first',
          'error': 'EMAIL_NOT_VERIFIED',
          'email': email,
        };
      }

      // Verify password
      final storedPasswordHash = response['password_hash'] as String?;
      if (storedPasswordHash == null) {
        return {
          'success': false,
          'message': 'Password not set for this user',
          'error': 'PASSWORD_NOT_SET'
        };
      }

      final passwordHash = _hashPassword(password);
      if (passwordHash != storedPasswordHash) {
        return {
          'success': false,
          'message': 'Invalid password',
          'error': 'INVALID_PASSWORD'
        };
      }

      final userId = response['id'] as String;

      // Create session
      try {
        await _sessionService.createSession(userId);
        print('✅ Session created successfully');

        // Get updated user data
        final updatedResponse = await _supabase
            .from('users')
            .select()
            .eq('id', userId)
            .single();

        return {
          'success': true,
          'message': 'Login successful',
          'user': UserModel.fromJson(updatedResponse),
        };
      } catch (sessionError) {
        print('❌ Session creation failed: $sessionError');
        return {
          'success': false,
          'message': 'Failed to create session',
          'error': sessionError.toString()
        };
      }
    } catch (e) {
      print('❌ Login error: $e');
      return {
        'success': false,
        'message': 'Login failed',
        'error': e.toString()
      };
    }
  }

  /// Initiate password reset with OTP
  Future<Map<String, dynamic>> initiatePasswordReset(String email) async {
    try {
      print('🔑 Initiating password reset for: $email');

      // Send OTP
      final otpResult = await _otpService.sendPasswordResetOtp(email);

      if (!otpResult['success']) {
        return otpResult;
      }

      return {
        'success': true,
        'message': 'OTP sent to email',
        'email': email,
      };
    } catch (e) {
      print('❌ Error initiating password reset: $e');
      return {
        'success': false,
        'message': 'Failed to initiate password reset',
        'error': e.toString()
      };
    }
  }

  /// Complete password reset after OTP verification
  Future<Map<String, dynamic>> completePasswordReset(
      String userId, String newPassword) async {
    try {
      print('🔑 Completing password reset for user: $userId');

      // Validate password strength
      final passwordValidation =
          _passwordResetService.validatePassword(newPassword);
      if (!passwordValidation['isValid']) {
        return {
          'success': false,
          'message': 'Password does not meet requirements',
          'errors': passwordValidation['errors'],
          'error': 'WEAK_PASSWORD'
        };
      }

      // Reset password
      final result = await _passwordResetService.resetPassword(userId, newPassword);

      return result;
    } catch (e) {
      print('❌ Error completing password reset: $e');
      return {
        'success': false,
        'message': 'Failed to reset password',
        'error': e.toString()
      };
    }
  }

  /// Get user by ID
  Future<UserModel?> getUserById(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .single();

      return UserModel.fromJson(response);
    } catch (e) {
      print('❌ Error getting user: $e');
      return null;
    }
  }

  /// Logout user
  Future<void> logout(String userId) async {
    try {
      // Get user's current session
      final userResponse = await _supabase
          .from('users')
          .select('current_session_id')
          .eq('id', userId)
          .maybeSingle();

      if (userResponse != null) {
        final sessionId = userResponse['current_session_id'] as String?;

        if (sessionId != null) {
          await _sessionService.endSession(sessionId);
          print('✅ Session ended successfully');
        }

        // Clear session from user record
        await _supabase.from('users').update({
          'current_session_id': null,
        }).eq('id', userId);
      }

      // End all active sessions
      try {
        await _supabase.from('user_sessions').update({
          'is_active': false,
          'ended_at': DateTime.now().toIso8601String(),
        }).eq('user_id', userId).eq('is_active', true);
        print('✅ All active sessions ended');
      } catch (e) {
        print('⚠️ Error ending all sessions: $e');
      }

      print('✅ User logged out: $userId');
    } catch (e) {
      print('❌ Logout error: $e');
    }
  }
}
