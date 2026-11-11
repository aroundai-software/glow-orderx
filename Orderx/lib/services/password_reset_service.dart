import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';

class PasswordResetService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Hash password using bcrypt-like approach (use crypto package)
  String _hashPassword(String password) {
    return sha256.convert(password.codeUnits).toString();
  }

  /// Reset password after OTP verification
  Future<Map<String, dynamic>> resetPassword(
      String userId, String newPassword) async {
    try {
      print('🔐 Resetting password for user: $userId');

      if (newPassword.length < 8) {
        return {
          'success': false,
          'message': 'Password must be at least 8 characters',
          'error': 'WEAK_PASSWORD'
        };
      }

      final passwordHash = _hashPassword(newPassword);

      // Update user password
      await _supabase.from('users').update({
        'password_hash': passwordHash,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);

      print('✅ Password reset successfully');

      return {
        'success': true,
        'message': 'Password reset successfully',
      };
    } catch (e) {
      print('❌ Error resetting password: $e');
      return {
        'success': false,
        'message': 'Failed to reset password',
        'error': e.toString()
      };
    }
  }

  /// Validate password strength
  Map<String, dynamic> validatePassword(String password) {
    final errors = <String>[];

    if (password.length < 8) {
      errors.add('At least 8 characters');
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      errors.add('At least one uppercase letter');
    }
    if (!password.contains(RegExp(r'[a-z]'))) {
      errors.add('At least one lowercase letter');
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      errors.add('At least one number');
    }
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      errors.add('At least one special character');
    }

    return {
      'isValid': errors.isEmpty,
      'errors': errors,
    };
  }

  /// Generate secure password reset token
  String _generateResetToken() {
    return sha256
        .convert((DateTime.now().millisecondsSinceEpoch.toString() +
                DateTime.now().microsecond.toString())
            .codeUnits)
        .toString();
  }

  /// Create password reset token
  Future<Map<String, dynamic>> createPasswordResetToken(String userId) async {
    try {
      print('🔑 Creating password reset token for user: $userId');

      final token = _generateResetToken();
      final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 1));

      await _supabase.from('password_reset_tokens').insert({
        'user_id': userId,
        'token_hash': token,
        'expires_at': expiresAt.toIso8601String(),
        'is_used': false,
      });

      print('✅ Password reset token created');

      return {
        'success': true,
        'token': token,
      };
    } catch (e) {
      print('❌ Error creating reset token: $e');
      return {
        'success': false,
        'error': e.toString()
      };
    }
  }

  /// Verify password reset token
  Future<Map<String, dynamic>> verifyResetToken(
      String userId, String token) async {
    try {
      print('🔐 Verifying reset token for user: $userId');

      final resetToken = await _supabase
          .from('password_reset_tokens')
          .select()
          .eq('user_id', userId)
          .eq('token_hash', token)
          .eq('is_used', false)
          .maybeSingle();

      if (resetToken == null) {
        return {
          'success': false,
          'message': 'Invalid reset token',
          'error': 'INVALID_TOKEN'
        };
      }

      final expiresAt = DateTime.parse(resetToken['expires_at'] as String);
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        return {
          'success': false,
          'message': 'Reset token expired',
          'error': 'TOKEN_EXPIRED'
        };
      }

      print('✅ Reset token verified');

      return {
        'success': true,
        'message': 'Token verified',
      };
    } catch (e) {
      print('❌ Error verifying reset token: $e');
      return {
        'success': false,
        'message': 'Failed to verify token',
        'error': e.toString()
      };
    }
  }

  /// Clean up expired reset tokens
  Future<void> cleanupExpiredTokens() async {
    try {
      print('🧹 Cleaning up expired reset tokens');

      await _supabase
          .from('password_reset_tokens')
          .delete()
          .lt('expires_at', DateTime.now().toUtc().toIso8601String());

      print('✅ Expired tokens cleaned up');
    } catch (e) {
      print('❌ Error cleaning up tokens: $e');
    }
  }
}
