import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum OrdersMapFilter {
  today,
  last7Days,
  last30Days,
}

class OrdersMapScreen extends StatefulWidget {
  const OrdersMapScreen({super.key});

  @override
  State<OrdersMapScreen> createState() => _OrdersMapScreenState();
}

class _OrdersMapScreenState extends State<OrdersMapScreen> {
  GoogleMapController? _mapController;
  bool _isLoading = true;
  String? _error;
  // Orders currently displayed on the map (after filters)
  List<OrderModel> _orders = [];
  // All orders for the selected company/time range (before salesman filter)
  List<OrderModel> _allOrders = [];
  Set<Marker> _markers = {};
  OrdersMapFilter _selectedFilter = OrdersMapFilter.today;
  BitmapDescriptor? _orderMarkerIcon;
  String? _selectedSalesmanId; // null = all salesmen
  Map<String, String> _salesmanNameById = {};

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId ?? '';

      if (companyId.isEmpty) {
        print('📍 OrdersMapScreen: No company selected, returning empty list');
        setState(() {
          _orders = [];
          _markers = {};
          _isLoading = false;
        });
        return;
      }

      final now = DateTime.now();
      DateTime startDate;
      switch (_selectedFilter) {
        case OrdersMapFilter.today:
          startDate = DateTime(now.year, now.month, now.day);
          break;
        case OrdersMapFilter.last7Days:
          startDate = now.subtract(const Duration(days: 7));
          break;
        case OrdersMapFilter.last30Days:
          startDate = now.subtract(const Duration(days: 30));
          break;
      }

      print(
          '📍 Loading orders for map: companyId=$companyId, from=${startDate.toIso8601String()}');

      final response = await Supabase.instance.client
          .from('sales_orders')
          .select()
          .eq('company_id', companyId)
          .gte('order_date', startDate.toIso8601String())
          .order('order_date', ascending: false);

      final List data = response as List;
      final orders = data
          .map((json) => OrderModel.fromJson(json as Map<String, dynamic>))
          .where((order) =>
              order.orderLatitude != null && order.orderLongitude != null)
          .toList();

      print('📍 Orders with location: ${orders.length}');

      // Load salesman names for filter dropdown (best-effort only)
      final Map<String, String> salesmanNames = {};
      try {
        final salesmanIds = orders.map((o) => o.salesmanId).toSet();
        if (salesmanIds.isNotEmpty) {
          final usersResponse = await Supabase.instance.client
              .from('users')
              .select('id, name')
              .inFilter('id', salesmanIds.toList());

          for (final user in usersResponse as List) {
            final id = user['id']?.toString();
            final name = user['name']?.toString();
            if (id != null && name != null && name.trim().isNotEmpty) {
              salesmanNames[id] = name.trim();
            }
          }
        }
      } catch (e) {
        print('⚠️ Error loading salesman names for OrdersMap: $e');
      }

      if (!mounted) return;
      await _setOrdersAndApplySalesmanFilter(orders, salesmanNames);
    } catch (e) {
      print('❌ Error loading orders for map: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _orders = [];
        _markers = {};
      });
    }
  }

  Future<void> _setOrdersAndApplySalesmanFilter(
    List<OrderModel> orders,
    Map<String, String> salesmanNames,
  ) async {
    _allOrders = orders;
    _salesmanNameById = salesmanNames;

    final filteredOrders = _selectedSalesmanId == null
        ? orders
        : orders
            .where((o) => o.salesmanId == _selectedSalesmanId)
            .toList(growable: false);

    await _createMarkers(filteredOrders);

    if (!mounted) return;
    setState(() {
      _orders = filteredOrders;
      _isLoading = false;
    });
  }

  Future<BitmapDescriptor> _getOrderMarkerIcon() async {
    if (_orderMarkerIcon != null) return _orderMarkerIcon!;

    // Use a modest size so the marker looks similar to default pins
    const double size = 72; // logical pixels
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    const double radius = size / 2;
    const Offset center = Offset(radius, radius);

    // Draw green circle background
    final Paint paint = Paint()..color = Colors.green.shade600;
    canvas.drawCircle(center, radius, paint);

    // Draw white shopping cart icon using Material Icons font
    const IconData iconData = Icons.shopping_cart;
    const double iconSize = radius * 0.7; // leave some green border
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: iconSize,
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          color: Colors.white,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final Offset iconOffset =
        Offset(center.dx - tp.width / 2, center.dy - tp.height / 2);
    tp.paint(canvas, iconOffset);

    final ui.Image img = await recorder.endRecording().toImage(
          size.toInt(),
          size.toInt(),
        );
    final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
    _orderMarkerIcon = BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
    return _orderMarkerIcon!;
  }

  Future<void> _createMarkers(List<OrderModel> orders) async {
    final markers = <Marker>{};
    final dateFormat = DateFormat('MMM dd, hh:mm a');

    // Build (and cache) custom cart icon once
    final cartIcon = await _getOrderMarkerIcon();

    for (final order in orders) {
      final lat = order.orderLatitude;
      final lng = order.orderLongitude;
      if (lat == null || lng == null) continue;

      final title =
          order.customerName != null && order.customerName!.trim().isNotEmpty
              ? order.customerName!
              : order.orderNumber;

      final snippetBuffer = StringBuffer();
      snippetBuffer.write('Order: ${order.orderNumber}');
      snippetBuffer.write('\nAmount: ₹${order.netAmount.toStringAsFixed(2)}');
      snippetBuffer.write('\nTime: ${dateFormat.format(order.orderDate)}');

      if (order.orderAddress != null && order.orderAddress!.trim().isNotEmpty) {
        snippetBuffer.write('\nAddress: ${order.orderAddress}');
      }

      if (order.distanceFromCustomer != null) {
        snippetBuffer.write(
            '\nDistance from customer: ${order.distanceFromCustomer!.toStringAsFixed(2)} km');
      }

      snippetBuffer.write(
          '\nLat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)}');

      final marker = Marker(
        markerId: MarkerId(order.id),
        position: LatLng(lat, lng),
        infoWindow: InfoWindow(
          title: title,
          snippet: snippetBuffer.toString(),
        ),
        icon: cartIcon,
      );

      markers.add(marker);
    }

    if (mounted) {
      setState(() {
        _markers = markers;
      });

      // Try to fit the map to current orders, but do not surface
      // camera/GoogleMapController issues as load errors
      if (_mapController != null && orders.isNotEmpty) {
        try {
          _fitMapToOrders(orders);
        } catch (e) {
          print('⚠️ Error fitting map to orders: $e');
        }
      }
    }
  }

  void _fitMapToOrders(List<OrderModel> orders) {
    if (orders.isEmpty || _mapController == null) return;

    final withLocation = orders
        .where((o) => o.orderLatitude != null && o.orderLongitude != null)
        .toList();
    if (withLocation.isEmpty) return;

    if (withLocation.length == 1) {
      final o = withLocation.first;
      final lat = o.orderLatitude!;
      final lng = o.orderLongitude!;
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15),
      );
      return;
    }

    double minLat = withLocation.first.orderLatitude!;
    double maxLat = withLocation.first.orderLatitude!;
    double minLng = withLocation.first.orderLongitude!;
    double maxLng = withLocation.first.orderLongitude!;

    for (final o in withLocation) {
      final lat = o.orderLatitude!;
      final lng = o.orderLongitude!;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 50),
    );
  }

  void _onFilterChanged(OrdersMapFilter filter) {
    if (_selectedFilter == filter) return;
    setState(() {
      _selectedFilter = filter;
    });
    _loadOrders();
  }

  Future<void> _reapplySalesmanFilter() async {
    if (_allOrders.isEmpty) {
      if (mounted) {
        setState(() {
          _orders = [];
          _markers = {};
          _isLoading = false;
        });
      }
      return;
    }

    await _setOrdersAndApplySalesmanFilter(_allOrders, _salesmanNameById);
  }

  @override
  void dispose() {
    // On web, google_maps_flutter_web manages controller lifecycle and
    // disposing explicitly can trigger an assertion. Guard this.
    if (!kIsWeb) {
      try {
        _mapController?.dispose();
      } catch (e) {
        print('⚠️ Error disposing OrdersMap GoogleMapController: $e');
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filterChips = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('Today'),
          selected: _selectedFilter == OrdersMapFilter.today,
          onSelected: (_) => _onFilterChanged(OrdersMapFilter.today),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Last 7 days'),
          selected: _selectedFilter == OrdersMapFilter.last7Days,
          onSelected: (_) => _onFilterChanged(OrdersMapFilter.last7Days),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Last 30 days'),
          selected: _selectedFilter == OrdersMapFilter.last30Days,
          onSelected: (_) => _onFilterChanged(OrdersMapFilter.last30Days),
        ),
      ],
    );

    String appBarTitle = 'Orders Map';
    if (_selectedSalesmanId != null) {
      final name = _salesmanNameById[_selectedSalesmanId!];
      if (name != null && name.trim().isNotEmpty) {
        appBarTitle = 'Orders Map - $name';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrders,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadOrders,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    const SizedBox(height: 8),
                    filterChips,
                    const SizedBox(height: 8),
                    if (_salesmanNameById.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.grey.shade300,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.person_pin_circle,
                                size: 20,
                                color: Colors.blueAccent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String?>(
                                    isExpanded: true,
                                    value: _selectedSalesmanId,
                                    hint: const Text('All salesmen'),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('All salesmen'),
                                      ),
                                      ...(_salesmanNameById.entries.toList()
                                            ..sort((a, b) => a.value
                                                .toLowerCase()
                                                .compareTo(
                                                    b.value.toLowerCase())))
                                          .map(
                                        (e) => DropdownMenuItem<String?>(
                                          value: e.key,
                                          child: Text(e.value),
                                        ),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedSalesmanId = value;
                                        _isLoading = true;
                                      });
                                      _reapplySalesmanFilter();
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _orders.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.location_off, size: 48),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No geotagged orders for ${_selectedFilter == OrdersMapFilter.today ? "today" : _selectedFilter == OrdersMapFilter.last7Days ? "last 7 days" : "last 30 days"}',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Orders created after location tracking is enabled will appear here.',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : GoogleMap(
                              onMapCreated: (controller) {
                                _mapController = controller;
                                if (_orders.isNotEmpty) {
                                  Future.delayed(
                                    const Duration(milliseconds: 500),
                                    () {
                                      if (!mounted) return;
                                      _fitMapToOrders(_orders);
                                    },
                                  );
                                }
                              },
                              initialCameraPosition: const CameraPosition(
                                target: LatLng(12.9716, 77.5946),
                                zoom: 12,
                              ),
                              markers: _markers,
                              myLocationButtonEnabled: true,
                              myLocationEnabled: false,
                              zoomControlsEnabled: true,
                              mapToolbarEnabled: true,
                            ),
                    ),
                  ],
                ),
    );
  }
}
