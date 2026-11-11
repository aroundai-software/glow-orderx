import 'dart:io' show Platform;
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Generate a unique session ID
  String _generateSessionId() {
    final random = Random();
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(32, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// Get device information for session tracking
  Future<Map<String, String>> _getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();

    try {
      // Check for web first - Platform class throws on web
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        return {
          'device_type': 'Web',
          'device_model': webInfo.browserName.name,
          'device_id': 'web_${DateTime.now().millisecondsSinceEpoch}',
          'os_version': webInfo.platform ?? 'Unknown',
        };
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return {
          'device_type': 'Android',
          'device_model': androidInfo.model,
          'device_id': androidInfo.id,
          'os_version': androidInfo.version.release,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return {
          'device_type': 'iOS',
          'device_model': iosInfo.model,
          'device_id': iosInfo.identifierForVendor ?? 'unknown',
          'os_version': iosInfo.systemVersion,
        };
      } else {
        return {
          'device_type': 'Unknown',
          'device_model': 'Unknown',
          'device_id': 'other_${DateTime.now().millisecondsSinceEpoch}',
          'os_version': 'Unknown',
        };
      }
    } catch (e) {
      print('Error getting device info: $e');
      return {
        'device_type': 'Unknown',
        'device_model': 'Unknown',
        'device_id': 'fallback_${DateTime.now().millisecondsSinceEpoch}',
        'os_version': 'Unknown',
      };
    }
  }

  /// Create a new session for user login (only if no active session exists)
  Future<String> createSession(String userId) async {
    final sessionId = _generateSessionId();
    final deviceInfo = await _getDeviceInfo();
    final now = DateTime.now().toUtc().toIso8601String();

    try {
      // Create new session - the unique constraint will prevent duplicates
      await _supabase.from('user_sessions').insert({
        'id': sessionId,
        'user_id': userId,
        'device_type': deviceInfo['device_type'],
        'device_model': deviceInfo['device_model'],
        'device_id': deviceInfo['device_id'],
        'os_version': deviceInfo['os_version'],
        'created_at': now,
        'last_activity': now,
        'is_active': true,
      });

      // Update user's current session ID
      await _supabase.from('users').update({
        'current_session_id': sessionId,
        'last_login_at': now,
      }).eq('id', userId);

      print('✅ Session created: $sessionId for user: $userId');
      return sessionId;
    } catch (e) {
      print('❌ Error creating session: $e');

      // If unique constraint violation, it means another session already exists
      if (e.toString().toLowerCase().contains('unique') ||
          e.toString().toLowerCase().contains('duplicate') ||
          e.toString().toLowerCase().contains('constraint')) {
        print('🚨 Session conflict - another device is already logged in');
        throw Exception(
            'Another device is already logged in with this account.');
      }

      rethrow;
    }
  }

  /// Validate if a session is still active
  Future<bool> validateSession(String userId, String sessionId) async {
    try {
      final response = await _supabase
          .from('user_sessions')
          .select('id, is_active, created_at')
          .eq('id', sessionId)
          .eq('user_id', userId)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) {
        print('❌ Session not found or inactive: $sessionId');
        return false;
      }

      // Update last activity
      await _supabase.from('user_sessions').update({
        'last_activity': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', sessionId);

      print('✅ Session validated: $sessionId');
      return true;
    } catch (e) {
      print('❌ Error validating session: $e');
      rethrow; // Rethrow so caller can handle network error vs invalid session
    }
  }

  /// End a session (logout)
  Future<void> endSession(String sessionId) async {
    try {
      await _supabase.from('user_sessions').update({
        'is_active': false,
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', sessionId);

      print('🔚 Session ended: $sessionId');
    } catch (e) {
      print('⚠️ Error ending session: $e');
    }
  }

  /// Clean up old inactive sessions (can be called periodically)
  Future<void> cleanupOldSessions() async {
    try {
      final cutoffDate = DateTime.now().toUtc().subtract(const Duration(days: 30));

      await _supabase
          .from('user_sessions')
          .delete()
          .eq('is_active', false)
          .lt('ended_at', cutoffDate.toIso8601String());

      print('🧹 Cleaned up old sessions');
    } catch (e) {
      print('⚠️ Error cleaning up sessions: $e');
    }
  }

  /// Get active sessions for a user (for admin purposes)
  Future<List<Map<String, dynamic>>> getUserSessions(String userId) async {
    try {
      final response = await _supabase
          .from('user_sessions')
          .select('*')
          .eq('user_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error getting user sessions: $e');
      return [];
    }
  }

  /// Force end ALL active sessions for a user (used for force login)
  Future<void> forceEndAllSessions(String userId) async {
    try {
      print('🔄 Force ending all sessions for user: $userId');

      await _supabase
          .from('user_sessions')
          .update({
            'is_active': false,
            'ended_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('user_id', userId)
          .eq('is_active', true);

      // Also clear user's current_session_id
      await _supabase.from('users').update({
        'current_session_id': null,
      }).eq('id', userId);

      print('✅ All sessions force ended for user: $userId');
    } catch (e) {
      print('⚠️ Error force ending sessions: $e');
    }
  }
}
