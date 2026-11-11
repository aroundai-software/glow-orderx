import 'package:flutter/material.dart';

class OfflineStatusProvider with ChangeNotifier {
  bool _hasOfflineData = false;
  bool _isSyncing = false;

  bool get hasOfflineData => _hasOfflineData;
  bool get isSyncing => _isSyncing;

  void setHasOfflineData(bool value) {
    if (_hasOfflineData == value) return;
    _hasOfflineData = value;
    notifyListeners();
  }

  void setSyncing(bool value) {
    if (_isSyncing == value) return;
    _isSyncing = value;
    notifyListeners();
  }
}
