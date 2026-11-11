import 'package:Orderx/models/user_model.dart';
import 'package:Orderx/services/password_service.dart';
import 'package:Orderx/services/session_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SessionService _sessionService = SessionService();

  Future<UserModel?> register({
    required String mobileNumber,
    required String name,
    required String userType,
    required String password,
    String? email,
    String? companyId,
  }) async {
    try {
      final existing = await _supabase
          .from('users')
          .select()
          .eq('mobile_number', mobileNumber)
          .maybeSingle();

      if (existing != null) {
        throw Exception('Mobile number already registered');
      }

      // Hash the password before storing
      final hashedPassword = PasswordService.hashPassword(password);

      final response = await _supabase
          .from('users')
          .insert({
            'mobile_number': mobileNumber,
            'name': name,
            'user_type': userType,
            'password': hashedPassword,
            'is_active': userType ==
                'admin', // Admins active by default, salesmen need approval
            'company_id': companyId,
          })
          .select()
          .single();

      return UserModel.fromJson(response);
    } catch (e) {
      print('Registration error: $e');
      rethrow;
    }
  }

  Future<UserModel?> login(String mobileNumber, String password,
      {bool forceLogin = false}) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('mobile_number', mobileNumber)
          .maybeSingle();

      if (response == null) {
        throw Exception('User not found');
      }

      // Check if user is active (admin approval check)
      if (response['is_active'] != true) {
        throw Exception(
            'ACCOUNT_INACTIVE:Your account is pending admin approval. Please contact your administrator.');
      }

      // Verify password
      final storedPassword = response['password'] as String?;
      if (storedPassword == null) {
        throw Exception('Password not set for this user');
      }

      if (!PasswordService.verifyPassword(password, storedPassword)) {
        throw Exception('Invalid password');
      }

      final userId = response['id'] as String;

      // CHECK: If user already has an active session on another device
      try {
        final existingSessions = await _supabase
            .from('user_sessions')
            .select('id, device_type, device_model, created_at')
            .eq('user_id', userId)
            .eq('is_active', true);

        print('🔍 Checking existing sessions for user: $userId');
        print('📊 Found ${existingSessions.length} active sessions');
        print('📊 Sessions data: $existingSessions');

        if (existingSessions.isNotEmpty) {
          if (forceLogin) {
            // Force login - end all existing sessions first
            print('🔄 Force login requested - ending all existing sessions');
            await _sessionService.forceEndAllSessions(userId);
          } else {
            final session = existingSessions.first;
            final deviceInfo = session['device_type'] ?? 'Unknown Device';
            final deviceModel = session['device_model'] ?? '';

            print(
                '🚫 Blocking login - session already exists on: $deviceInfo $deviceModel');
            throw Exception(
                'SESSION_CONFLICT:Already logged in on another device ($deviceInfo). Logout from that device first.');
          }
        }
      } catch (e) {
        if (e.toString().contains('SESSION_CONFLICT')) {
          rethrow;
        }
        print('⚠️ Error checking sessions: $e');
        // Continue with login if session check fails
      }

      // Create new session since no active session exists (or we force-ended them)
      await _sessionService.createSession(userId);
      print('✅ Session created successfully');

      // Get updated user data
      final updatedResponse =
          await _supabase.from('users').select().eq('id', userId).single();

      return UserModel.fromJson(updatedResponse);
    } catch (e) {
      print('Login error: $e');
      rethrow;
    }
  }

  Future<UserModel?> getUserById(String userId) async {
    try {
      final response =
          await _supabase.from('users').select().eq('id', userId).single();

      final user = UserModel.fromJson(response);

      // STRICT: Validate current session if user has one
      if (user.currentSessionId != null) {
        final isValidSession = await _sessionService.validateSession(
          userId,
          user.currentSessionId!,
        );

        if (!isValidSession) {
          print(
              '❌ Invalid session detected for user: $userId - forcing logout');
          // Clear invalid session and force re-login
          await _supabase.from('users').update({
            'current_session_id': null,
          }).eq('id', userId);
          return null; // Force re-login
        }
      }

      return user;
    } catch (e) {
      print('Get user error: $e');
      rethrow; // Rethrow so AuthProvider can catch it and try cache
    }
  }

  Future<bool> updateProfile({
    required String userId,
    required String name,
  }) async {
    try {
      await _supabase.from('users').update({
        'name': name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);

      return true;
    } catch (e) {
      print('Update profile error: $e');
      return false;
    }
  }

  Future<bool> mobileNumberExists(String mobileNumber) async {
    try {
      final response = await _supabase
          .from('users')
          .select('id')
          .eq('mobile_number', mobileNumber)
          .maybeSingle();

      return response != null;
    } catch (e) {
      print('Check mobile error: $e');
      return false;
    }
  }

  Future<bool> updatePassword({
    required String mobileNumber,
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      // First verify the user exists and old password is correct
      final response = await _supabase
          .from('users')
          .select('id, password')
          .eq('mobile_number', mobileNumber)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) {
        throw Exception('User not found or inactive');
      }

      // Verify old password
      final storedPassword = response['password'] as String?;
      if (storedPassword == null) {
        throw Exception('Password not set for this user');
      }

      if (!PasswordService.verifyPassword(oldPassword, storedPassword)) {
        throw Exception('Current password is incorrect');
      }

      // Hash the new password
      final hashedNewPassword = PasswordService.hashPassword(newPassword);

      // Update the password
      await _supabase.from('users').update({
        'password': hashedNewPassword,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('mobile_number', mobileNumber);

      return true;
    } catch (e) {
      print('Update password error: $e');
      rethrow;
    }
  }

  /// Logout user and end their session
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
          // End the session
          await _sessionService.endSession(sessionId);
          print('✅ Session ended successfully');
        }

        // Clear session from user record
        await _supabase.from('users').update({
          'current_session_id': null,
        }).eq('id', userId);
      }

      // ✅ IMPORTANT: Also end ALL active sessions for this user to prevent orphaned sessions
      try {
        await _supabase
            .from('user_sessions')
            .update({
              'is_active': false,
              'ended_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('user_id', userId)
            .eq('is_active', true);
        print('✅ All active sessions ended for user');
      } catch (e) {
        print('⚠️ Error ending all sessions: $e');
      }

      print('✅ User logged out: $userId');
    } catch (e) {
      print('❌ Logout error: $e');
      // Don't rethrow - logout should always succeed locally
    }
  }
}
