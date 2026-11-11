import 'package:flutter/material.dart';

class ErrorHandler {
  static String getFriendlyErrorMessage(dynamic error) {
    if (error == null) return 'An unknown error occurred.';
    
    final errorString = error.toString().toLowerCase();

    // Network Errors
    if (errorString.contains('socketexception') ||
        errorString.contains('connection refused') ||
        errorString.contains('network is unreachable') ||
        errorString.contains('failed host lookup') ||
        errorString.contains('connection timeout') ||
        errorString.contains('handshake error')) {
      return 'Network Error: Unable to connect to the server. Please check your internet connection.';
    }

    // Supabase / Database Errors
    if (errorString.contains('postgrest') || 
        errorString.contains('timeout') ||
        errorString.contains('500') ||
        errorString.contains('502') ||
        errorString.contains('503')) {
      return 'Server Error: We couldn\'t reach our database. Please try again in a moment.';
    }

    // Permission / Auth Errors
    if (errorString.contains('permission denied') ||
        errorString.contains('jwt') ||
        errorString.contains('unauthorized')) {
      return 'Access Denied: You do not have permission to perform this action.';
    }

    // Fallback: If it's a generic Exception with a message, strip the "Exception:" part
    if (error.toString().startsWith('Exception: ')) {
      return error.toString().replaceFirst('Exception: ', '');
    }

    return 'Oops! Something went wrong. Please try again.';
  }
}
