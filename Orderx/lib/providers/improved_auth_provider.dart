import 'package:Orderx/models/user_model.dart';
import 'package:Orderx/services/improved_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class ImprovedAuthProvider with ChangeNotifier {
  final ImprovedAuthService _authService = ImprovedAuthService();
  UserModel? _currentUser;
  String? _selectedCompanyId;
  bool _isLoading = false;
  Timer? _sessionCheckTimer;

  UserModel? get currentUser => _currentUser;
  String? get selectedCompanyId => _selectedCompanyId;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;

  ImprovedAuthProvider() {
    _loadUser();
    _loadSelectedCompany();
    _startSessionMonitoring();
  }

  @override
  void dispose() {
    _sessionCheckTimer?.cancel();
    super.dispose();
  }

  /// Start periodic session validation (every 5 minutes)
  void _startSessionMonitoring() {
    _sessionCheckTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_currentUser != null && _currentUser!.currentSessionId != null) {
        _validateCurrentSession();
      }
    });
  }

  /// Validate current session periodically
  Future<void> _validateCurrentSession() async {
    if (_currentUser == null || _currentUser!.currentSessionId == null) {
      return;
    }

    try {
      final isValid = await _authService.validateCurrentSession(
        _currentUser!.id,
        _currentUser!.currentSessionId,
      );

      if (!isValid) {
        print('🚨 Session invalid - forcing logout');
        await _forceLogout();
      }
    } catch (e) {
      print('⚠️ Session validation error: $e');
      // Don't force logout on network errors, but log the issue
    }
  }

  /// Load user with strict session validation
  Future<void> _loadUser() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');

      if (userId != null) {
        // This will return null if session is invalid, forcing re-login
        _currentUser = await _authService.getUserById(userId);
        
        if (_currentUser == null) {
          // Session was invalid, clear stored user ID
          await prefs.remove('user_id');
          print('🚨 Invalid session detected - user must re-login');
        }
      }
    } catch (e) {
      print('Load user error: $e');
      // Clear stored data on error
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_id');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Login with strict session enforcement
  Future<String?> login(String mobileNumber, String password, {String? companyId}) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (!_isValidMobileNumber(mobileNumber)) {
        return 'Please enter a valid 10-digit mobile number';
      }

      _currentUser = await _authService.login(mobileNumber, password);

      if (_currentUser != null) {
        await _saveUserId(_currentUser!.id);
        
        // Save selected company if provided
        if (companyId != null) {
          print('🔐 Login successful, saving company: $companyId');
          await setSelectedCompany(companyId);
        }
        
        // Start session monitoring for this user
        _startSessionMonitoring();
        
        return null; // Success
      }

      return 'Login failed';
    } catch (e) {
      return e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Logout with proper session cleanup
  Future<void> logout() async {
    if (_currentUser != null) {
      // End the user's session in the backend
      await _authService.logout(_currentUser!.id);
    }
    
    await _forceLogout();
  }

  /// Force logout (used when session becomes invalid)
  Future<void> _forceLogout() async {
    _sessionCheckTimer?.cancel();
    _currentUser = null;
    await _clearUserData();
    notifyListeners();
  }

  /// Validate session before making API calls
  Future<bool> ensureValidSession() async {
    if (_currentUser == null || _currentUser!.currentSessionId == null) {
      return false;
    }

    final isValid = await _authService.validateCurrentSession(
      _currentUser!.id,
      _currentUser!.currentSessionId,
    );

    if (!isValid) {
      await _forceLogout();
      return false;
    }

    return true;
  }

  /// Get active sessions for current user (for admin/monitoring)
  Future<List<Map<String, dynamic>>> getActiveSessions() async {
    if (_currentUser == null) return [];
    
    return await _authService.getActiveSessionsForUser(_currentUser!.id);
  }

  /// Logout all other devices
  Future<void> logoutAllOtherDevices() async {
    if (_currentUser == null || _currentUser!.currentSessionId == null) {
      return;
    }

    await _authService.logoutAllOtherDevices(
      _currentUser!.id,
      _currentUser!.currentSessionId!,
    );
  }

  // ... existing helper methods remain the same
  
  Future<void> _saveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', userId);
  }

  Future<void> _clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    await prefs.remove('selected_company_id');
  }

  Future<void> setSelectedCompany(String companyId) async {
    print('💾 Saving selected company: $companyId');
    _selectedCompanyId = companyId;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_company_id', companyId);
      print('✅ Company saved to SharedPreferences: $companyId');
    } catch (e) {
      print('⚠️ SharedPreferences save failed (web?): $e');
    }
    
    notifyListeners();
  }

  Future<void> _loadSelectedCompany() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loaded = prefs.getString('selected_company_id');
      if (loaded != null) {
        _selectedCompanyId = loaded;
        print('✅ Loaded selected company from SharedPreferences: $_selectedCompanyId');
      } else {
        print('⚠️ No company found in SharedPreferences, setting Bengaluru as default');
        _selectedCompanyId = '1bb4eff8-2464-4e7e-bca8-076135783af9';
        await prefs.setString('selected_company_id', _selectedCompanyId!);
      }
      notifyListeners();
    } catch (e) {
      print('⚠️ Load company error: $e');
      _selectedCompanyId = '1bb4eff8-2464-4e7e-bca8-076135783af9';
      notifyListeners();
    }
  }

  bool _isValidMobileNumber(String mobile) {
    final cleaned = mobile.replaceAll(RegExp(r'[^\d]'), '');
    return cleaned.length == 10 && cleaned.startsWith(RegExp(r'[6-9]'));
  }
}
