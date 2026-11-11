import 'dart:convert';

import 'package:Orderx/models/tally_company_model.dart';
import 'package:Orderx/models/user_model.dart';
import 'package:Orderx/services/auth_service.dart';
import 'package:Orderx/services/email_auth_service.dart';
import 'package:Orderx/services/tally_company_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  final EmailAuthService _emailAuthService = EmailAuthService();
  UserModel? _currentUser;
  String? _selectedCompanyId;
  bool _isLoading = true; // ✅ Default to true to show loader while initializing
  bool _isOfflineMode = false;
  DateTime? _lastCacheSyncAt;

  UserModel? get currentUser => _currentUser;
  String? get selectedCompanyId => _selectedCompanyId;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;
  bool get isOfflineMode => _isOfflineMode;
  DateTime? get lastCacheSyncAt => _lastCacheSyncAt;

  AuthProvider() {
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    _isLoading = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      // --- STAGE 1: IDENTIFIERS ---
      final savedUserId = prefs.getString('user_id');
      await _loadSelectedCompany();
      _loadLastSync(prefs);

      debugPrint(
          '🔐 [BOOT 1/3]: ID=$savedUserId, Co=$_selectedCompanyId, LastSync=$_lastCacheSyncAt');

      // --- STAGE 2: PROFILE LOADING ---
      if (savedUserId != null && savedUserId.isNotEmpty) {
        try {
          debugPrint('🌐 [BOOT 2/3]: Online fetch for $savedUserId...');
          _currentUser = await _authService
              .getUserById(savedUserId)
              .timeout(const Duration(seconds: 4));

          if (_currentUser != null) {
            debugPrint('✅ [BOOT 2/3]: Online profile loaded.');
            await _saveCachedUser(_currentUser!);
            _isOfflineMode = false;
          } else {
            debugPrint(
                '⚠️ [BOOT 2/3]: Online returned null. Checking cache...');
            _currentUser = _loadCachedUser(prefs);
            _isOfflineMode = (_currentUser != null);
          }
        } catch (e) {
          debugPrint('📡 [BOOT 2/3]: Online failed/timeout ($e). Using cache.');
          _currentUser = _loadCachedUser(prefs);
          _isOfflineMode = (_currentUser != null);
        }
      } else {
        debugPrint('❓ [BOOT 2/3]: No user_id. User logged out.');
        _currentUser = null;
        _isOfflineMode = false;
        // Clear any stale cached user data
        await _clearCachedUser();
      }

      // --- STAGE 3: CONTEXT RECOVERY ---
      if (_currentUser != null) {
        await _lockToUserCompany();
      } else {
        debugPrint('🚪 [BOOT 3/3]: No user found. Routing to Login.');
      }
    } catch (e) {
      debugPrint('❌ [BOOT FATAL ERROR]: $e');
    } finally {
      _isLoading = false;
      debugPrint(
          '🏁 [BOOT FINISHED]: User=${_currentUser?.name}, Co=$_selectedCompanyId, Off=$_isOfflineMode');
      notifyListeners();
    }
  }

  UserModel? _loadCachedUser(SharedPreferences prefs) {
    final cachedJson = prefs.getString('cached_user');
    if (cachedJson == null) {
      debugPrint('📦 Auth Cache: No user found in SharedPreferences');
      return null;
    }
    try {
      final map = jsonDecode(cachedJson) as Map<String, dynamic>;
      return UserModel.fromJson(map);
    } catch (e) {
      debugPrint('📦 Auth Cache: Failed to decode cached user: $e');
      return null;
    }
  }

  Future<void> _saveCachedUser(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_user', jsonEncode(user.toJson()));
      debugPrint('📦 Auth Cache: Saved user ${user.name} to local storage');
    } catch (e) {
      debugPrint('📦 Auth Cache: Error saving user: $e');
    }
  }

  Future<void> _clearCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_user');
  }

  String _companyCacheKey(String companyId) => 'cached_company_$companyId';

  Future<void> cacheCompany(TallyCompanyModel company) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _companyCacheKey(company.id),
      jsonEncode(company.toJson()),
    );
  }

  Future<TallyCompanyModel?> getCachedCompany(String companyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _companyCacheKey(companyId);
      final cachedJson = prefs.getString(key);
      if (cachedJson == null) {
        debugPrint(
            '🏢 Company Cache: No data found for ID $companyId using key $key');
        return null;
      }
      final map = jsonDecode(cachedJson) as Map<String, dynamic>;
      return TallyCompanyModel.fromJson(map);
    } catch (e) {
      debugPrint(
          '🏢 Company Cache: Error loading/decoding company $companyId: $e');
      return null;
    }
  }

  Future<void> clearCachedCompany(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_companyCacheKey(companyId));
  }

  void _loadLastSync(SharedPreferences prefs) {
    final raw = prefs.getString('offline_cache_synced_at');
    if (raw == null) {
      _lastCacheSyncAt = null;
      return;
    }
    _lastCacheSyncAt = DateTime.tryParse(raw);
  }

  Future<void> updateLastSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString('offline_cache_synced_at', now.toIso8601String());
    _lastCacheSyncAt = now;
    notifyListeners();
  }

  Future<void> _saveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', userId);
  }

  Future<void> _clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    // Keep selected_company_id so logout redirects to login page, not company key page
    // await prefs.remove('selected_company_id');
    // _selectedCompanyId = null;
    // Note: Not clearing cached company to allow faster re-login
  }

  Future<void> setSelectedCompany(String companyId) async {
    final safeId = companyId.trim();
    debugPrint('💾 [AUTH]: Saving selected company: "$safeId"');
    _selectedCompanyId = safeId;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_company_id', safeId);
    } catch (e) {
      debugPrint('❌ [AUTH]: SharedPreferences save failed: $e');
    }

    notifyListeners();
  }

  /// Resolve the logged-in user's Tally company by id or Guid and lock the
  /// session to that row only. Returns the matched company, or null.
  Future<TallyCompanyModel?> _lockToUserCompany({String? preferredId}) async {
    final service = TallyCompanyService();
    TallyCompanyModel? company;

    if (_currentUser?.companyId != null &&
        _currentUser!.companyId!.trim().isNotEmpty) {
      company = await service.resolveCompany(_currentUser!.companyId);
    }

    if (company == null && preferredId != null && preferredId.trim().isNotEmpty) {
      company = await service.resolveCompany(preferredId);
    }

    if (company == null &&
        _selectedCompanyId != null &&
        _selectedCompanyId!.trim().isNotEmpty &&
        _selectedCompanyId != 'ALL') {
      company = await service.resolveCompany(_selectedCompanyId);
    }

    if (company != null) {
      debugPrint(
          '🛠 [AUTH]: Locked to company ${company.companyName} id=${company.id} Guid=${company.Guid}');
      await setSelectedCompany(company.id);
      await cacheCompany(company);
    } else {
      debugPrint('🔴 [AUTH]: Could not resolve a Tally company for this user.');
    }
    return company;
  }

  Future<void> _loadSelectedCompany() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loaded = prefs.getString('selected_company_id');
      if (loaded != null && loaded.trim().isNotEmpty) {
        _selectedCompanyId = loaded.trim();
        debugPrint('📂 [AUTH]: Loaded selected company: "$_selectedCompanyId"');
      } else {
        _selectedCompanyId = null;
        debugPrint('📂 [AUTH]: No selected company found in storage.');
      }
    } catch (e) {
      debugPrint('❌ [AUTH]: Load company error: $e');
      _selectedCompanyId = null;
    }
    // No notifyListeners here as it's usually called during provider init
  }

  Future<void> clearSelectedCompany() async {
    final previousCompanyId = _selectedCompanyId;
    _selectedCompanyId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('selected_company_id');
      if (previousCompanyId != null) {
        await prefs.remove(_companyCacheKey(previousCompanyId));
      }
    } catch (e) {
      print('SharedPreferences clear company failed: $e');
    }
    notifyListeners();
  }

  Future<String?> register({
    required String mobileNumber,
    required String name,
    required String userType,
    required String password,
    String? email,
    String? companyId,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (!_isValidMobileNumber(mobileNumber)) {
        return 'Please enter a valid 10-digit mobile number';
      }

      final effectiveCompanyId = companyId ?? _selectedCompanyId;
      if (effectiveCompanyId == null) {
        return 'Company context missing. Please enter the company key again.';
      }

      _currentUser = await _authService.register(
        mobileNumber: mobileNumber,
        name: name,
        userType: userType,
        password: password,
        email: email,
        companyId: effectiveCompanyId,
      );

      if (_currentUser != null) {
        await _saveUserId(_currentUser!.id);
        await _saveCachedUser(_currentUser!);
        return null;
      }

      return 'Registration failed';
    } catch (e) {
      return e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> login(String mobileNumber, String password,
      {String? companyId, bool forceLogin = false}) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (!_isValidMobileNumber(mobileNumber)) {
        return 'Please enter a valid 10-digit mobile number';
      }

      final result = await _authService.login(mobileNumber, password,
          forceLogin: forceLogin);
      _currentUser = result;

      if (_currentUser != null) {
        await _saveUserId(_currentUser!.id);
        await _saveCachedUser(_currentUser!);
        _isOfflineMode = false;

        final company = await _lockToUserCompany(preferredId: companyId);
        if (company == null) {
          return 'No company is linked to this account.';
        }

        return null;
      }

      return 'Login failed';
    } catch (e) {
      return e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> emailLogin(String email, String password,
      {String? companyId}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _emailAuthService.loginWithEmail(email, password);

      if (!result['success']) {
        return result['message'] ?? 'Login failed';
      }

      _currentUser = result['user'];
      if (_currentUser != null) {
        await _saveUserId(_currentUser!.id);
        await _saveCachedUser(_currentUser!);
        _isOfflineMode = false;

        final company = await _lockToUserCompany(preferredId: companyId);
        if (company == null) {
          return 'No company is linked to this account.';
        }

        return null;
      }

      return 'Login failed';
    } catch (e) {
      return e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    if (_currentUser != null) {
      await _emailAuthService.logout(_currentUser!.id);
    }

    _currentUser = null;
    _isOfflineMode = false;
    await _clearUserData();
    await _clearCachedUser();
    notifyListeners();
  }

  bool _isValidMobileNumber(String mobile) {
    final cleaned = mobile.replaceAll(RegExp(r'[^\d]'), '');
    return cleaned.length == 10 && cleaned.startsWith(RegExp(r'[6-9]'));
  }

  Future<bool> checkMobileExists(String mobileNumber) async {
    return await _authService.mobileNumberExists(mobileNumber);
  }

  Future<String?> updatePassword({
    required String mobileNumber,
    required String oldPassword,
    required String newPassword,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (!_isValidMobileNumber(mobileNumber)) {
        return 'Please enter a valid 10-digit mobile number';
      }

      await _authService.updatePassword(
        mobileNumber: mobileNumber,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );

      return null;
    } catch (e) {
      return e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void markOfflineMode(bool value) {
    if (_isOfflineMode == value) return;
    _isOfflineMode = value;
    notifyListeners();
  }
}
