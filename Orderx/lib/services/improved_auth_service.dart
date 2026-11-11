import 'package:Orderx/models/user_model.dart';
import 'package:Orderx/services/password_service.dart';
import 'package:Orderx/services/session_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ImprovedAuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SessionService _sessionService = SessionService();

  /// Login with strict single device enforcement
  Future<UserModel?> login(String mobileNumber, String password) async {
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
        throw Exception('ACCOUNT_INACTIVE:Your account is pending admin approval. Please contact your administrator.');
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

      // STRICT: Session creation must succeed for login to proceed
      try {
        final sessionId = await _sessionService.createSession(userId);
        print('✅ Session created successfully: $sessionId - other devices logged out');
        
        // Get updated user data with new session
        final updatedResponse = await _supabase
            .from('users')
            .select()
            .eq('id', userId)
            .single();

        return UserModel.fromJson(updatedResponse);
      } catch (sessionError) {
        print('❌ Session creation failed: $sessionError');
        
        // Only allow login without session in development mode
        // In production, this should throw an error
        if (_isDevelopmentMode()) {
          print('⚠️ Development mode: allowing login without session');
          return UserModel.fromJson(response);
        } else {
          throw Exception('Login failed: Unable to create secure session. Please try again.');
        }
      }
    } catch (e) {
      print('Login error: $e');
      rethrow;
    }
  }

  /// Get user by ID with strict session validation
  Future<UserModel?> getUserById(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .single();

      final user = UserModel.fromJson(response);

      // STRICT: If user has a session, it must be valid
      if (user.currentSessionId != null) {
        final isValidSession = await _sessionService.validateSession(
          userId,
          user.currentSessionId!,
        );

        if (!isValidSession) {
          print('❌ Invalid session detected for user: $userId - forcing logout');
          // Clear invalid session and force re-login
          await _clearUserSession(userId);
          return null; // This will force user to login screen
        }
      }

      return user;
    } catch (e) {
      print('Get user error: $e');
      return null;
    }
  }

  /// Validate current session before making API calls
  Future<bool> validateCurrentSession(String userId, String? sessionId) async {
    if (sessionId == null) {
      print('⚠️ No session ID found');
      return false;
    }

    try {
      final isValid = await _sessionService.validateSession(userId, sessionId);
      if (!isValid) {
        print('❌ Session validation failed - user will be logged out');
        await _clearUserSession(userId);
      }
      return isValid;
    } catch (e) {
      print('❌ Session validation error: $e');
      return false;
    }
  }

  /// Force logout user and clear all sessions
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
        }
      }

      // Clear session from user record
      await _clearUserSession(userId);
      print('✅ User logged out successfully');
    } catch (e) {
      print('⚠️ Logout error: $e');
    }
  }

  /// Clear user session data
  Future<void> _clearUserSession(String userId) async {
    try {
      await _supabase.from('users').update({
        'current_session_id': null,
      }).eq('id', userId);
    } catch (e) {
      print('⚠️ Error clearing user session: $e');
    }
  }

  /// Check if running in development mode
  bool _isDevelopmentMode() {
    // You can customize this based on your build configuration
    return const bool.fromEnvironment('dart.vm.product') == false;
  }

  /// Check for active sessions on other devices (for monitoring)
  Future<List<Map<String, dynamic>>> getActiveSessionsForUser(String userId) async {
    try {
      return await _sessionService.getUserSessions(userId);
    } catch (e) {
      print('Error getting user sessions: $e');
      return [];
    }
  }

  /// Force logout all other devices for a user
  Future<void> logoutAllOtherDevices(String userId, String currentSessionId) async {
    try {
      // Invalidate all sessions except current one
      await _supabase.from('user_sessions').update({
        'is_active': false,
        'ended_at': DateTime.now().toIso8601String(),
      }).eq('user_id', userId)
        .eq('is_active', true)
        .neq('id', currentSessionId);

      print('✅ Logged out all other devices for user: $userId');
    } catch (e) {
      print('⚠️ Error logging out other devices: $e');
    }
  }

  // ... other existing methods (register, updateProfile, etc.) remain the same
}
