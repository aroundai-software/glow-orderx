import 'package:Orderx/providers/improved_auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// API Interceptor to validate sessions before making API calls
class ApiInterceptor {
  
  /// Validate session before making any API call
  static Future<bool> validateSessionBeforeApiCall(BuildContext context) async {
    try {
      final authProvider = context.read<ImprovedAuthProvider>();
      
      // Check if user is authenticated
      if (!authProvider.isAuthenticated) {
        print('⚠️ User not authenticated - redirecting to login');
        return false;
      }

      // Validate current session
      final isValidSession = await authProvider.ensureValidSession();
      
      if (!isValidSession) {
        print('🚨 Session invalid - user logged out');
        // Show session expired message
        _showSessionExpiredDialog(context);
        return false;
      }

      return true;
    } catch (e) {
      print('❌ Session validation error: $e');
      return false;
    }
  }

  /// Show session expired dialog
  static void _showSessionExpiredDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Session Expired'),
          content: const Text(
            'Your session has expired or another device has logged in with your account. Please login again.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // The AuthWrapper will automatically redirect to login screen
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Wrapper for API calls with automatic session validation
  static Future<T?> secureApiCall<T>(
    BuildContext context,
    Future<T> Function() apiCall,
  ) async {
    // Validate session first
    final isValid = await validateSessionBeforeApiCall(context);
    if (!isValid) {
      return null;
    }

    try {
      // Make the API call
      return await apiCall();
    } catch (e) {
      // Check if error is related to authentication
      if (e.toString().toLowerCase().contains('unauthorized') ||
          e.toString().toLowerCase().contains('session') ||
          e.toString().toLowerCase().contains('auth')) {
        
        print('🚨 API call failed with auth error: $e');
        
        // Force logout on auth errors
        final authProvider = context.read<ImprovedAuthProvider>();
        await authProvider.logout();
        
        _showSessionExpiredDialog(context);
        return null;
      }
      
      // Re-throw non-auth errors
      rethrow;
    }
  }
}

/// Extension to make API calls easier
extension SecureApiCall on BuildContext {
  Future<T?> secureApiCall<T>(Future<T> Function() apiCall) {
    return ApiInterceptor.secureApiCall<T>(this, apiCall);
  }
}

/// Mixin for services that need session validation
mixin SessionValidationMixin {
  Future<bool> validateSession(BuildContext context) {
    return ApiInterceptor.validateSessionBeforeApiCall(context);
  }
}
