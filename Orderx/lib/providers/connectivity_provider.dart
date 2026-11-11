import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'package:Orderx/services/offline_order_queue_service.dart';

class ConnectivityProvider with ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  final OfflineOrderQueueService _offlineOrderQueueService =
      OfflineOrderQueueService();

  StreamSubscription<dynamic>? _subscription;
  bool _isOnline = true;

  bool get isOnline => _isOnline;

  ConnectivityProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    final initialStatus = await _connectivity.checkConnectivity();
    _updateStatus(_extractStatus(initialStatus));

    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      _updateStatus(_extractStatus(result));
    });
  }

  ConnectivityResult _extractStatus(dynamic result) {
    if (result is ConnectivityResult) {
      return result;
    }
    if (result is List<ConnectivityResult>) {
      return result.firstWhere(
        (status) => status != ConnectivityResult.none,
        orElse: () => result.isNotEmpty
            ? result.first
            : ConnectivityResult.none,
      );
    }
    return ConnectivityResult.none;
  }

  void _updateStatus(ConnectivityResult status) {
    final bool newIsOnline = status != ConnectivityResult.none;
    if (newIsOnline == _isOnline) return;

    _isOnline = newIsOnline;
    notifyListeners();

    if (_isOnline) {
      _offlineOrderQueueService.syncPendingOrders();
    }
  }

  Future<void> refreshStatus() async {
    final status = await _connectivity.checkConnectivity();
    _updateStatus(_extractStatus(status));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
