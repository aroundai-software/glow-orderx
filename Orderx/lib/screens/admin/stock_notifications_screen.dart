import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/stock_notification_model.dart';
import 'package:Orderx/services/stock_notification_service.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/widgets/app_bar_actions.dart';

class StockNotificationsScreen extends StatefulWidget {
  const StockNotificationsScreen({super.key});

  @override
  State<StockNotificationsScreen> createState() => _StockNotificationsScreenState();
}

class _StockNotificationsScreenState extends State<StockNotificationsScreen> {
  final StockNotificationService _notificationService = StockNotificationService();
  
  List<StockNotificationModel> _notifications = [];
  bool _isLoading = true;
  bool _showUnreadOnly = false;
  String? _filterType;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      final effectiveCompanyId = (companyId == 'ALL') ? null : companyId;
      print('📊 StockNotificationsScreen - Loading notifications for company: $effectiveCompanyId');

      final notifications = await _notificationService.getAllNotifications(
        isRead: _showUnreadOnly ? false : null,
        notificationType: _filterType,
        companyId: effectiveCompanyId,
      );
      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading notifications: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _markAsRead(StockNotificationModel notification) async {
    try {
      await _notificationService.markAsRead(notification.id);
      _loadNotifications();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error marking as read: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      await _notificationService.markAllAsRead();
      _loadNotifications();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications marked as read'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await _notificationService.deleteNotification(notificationId);
      _loadNotifications();
      if (mounted) {
        // ScaffoldMessenger.of(context).showSnackBar(
        //   const SnackBar(
        //     content: Text('Notification deleted'),
        //     backgroundColor: AppTheme.success,
        //   ),
        // );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Color _getNotificationColor(String type) {
    return type == 'out_of_stock' ? AppTheme.error : AppTheme.warning;
  }

  IconData _getNotificationIcon(String type) {
    return type == 'out_of_stock' ? Icons.error_outline : Icons.warning_amber;
  }

  String _getNotificationTitle(String type) {
    return type == 'out_of_stock' ? 'Out of Stock' : 'Low Stock';
  }

  Widget _buildNotificationCard(StockNotificationModel notification) {
    final color = _getNotificationColor(notification.type);
    final icon = _getNotificationIcon(notification.type);
    final title = _getNotificationTitle(notification.type);
    final dateFormatter = DateFormat('MMM dd, yyyy • hh:mm a');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: notification.isRead ? 0 : 2,
      color: notification.isRead ? Colors.grey.withOpacity(0.05) : Colors.white,
      child: InkWell(
        onTap: notification.isRead ? null : () => _markAsRead(notification),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Notification Icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  
                  // Notification Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                notification.productName ?? 'Unknown Product',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: notification.isRead ? Colors.grey : Colors.black,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!notification.isRead)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppTheme.primaryBlue,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        
                        // Message
                        Text(
                          notification.message,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  
                  // Delete Button
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: Colors.grey,
                    onPressed: () => _deleteNotification(notification.id),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Status Badge and Stock Level
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color, width: 1),
                    ),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Stock: ${notification.currentStock ?? 0}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              
              // Salesman Info and Date
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        notification.salesmanName,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    dateFormatter.format(notification.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !n.isRead).length;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Notifications'),
        actions: [
          GlobalCompanySwitcher(onCompanyChanged: _loadNotifications),
          if (unreadCount > 0)
            TextButton.icon(
              onPressed: _markAllAsRead,
              icon: const Icon(Icons.done_all, color: Colors.white),
              label: const Text('Mark All Read', style: TextStyle(color: Colors.white)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotifications,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Options
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Unread Filter
                FilterChip(
                  label: Text('Unread ($unreadCount)'),
                  selected: _showUnreadOnly,
                  onSelected: (selected) {
                    setState(() {
                      _showUnreadOnly = selected;
                    });
                    _loadNotifications();
                  },
                  selectedColor: AppTheme.primaryBlue.withOpacity(0.2),
                  checkmarkColor: AppTheme.primaryBlue,
                ),
                const SizedBox(width: 8),
                
                // Type Filter
                Container(
                  constraints: const BoxConstraints(minWidth: 155),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primaryBlue.withOpacity(0.25),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _filterType,
                      dropdownColor: Colors.white,
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.primaryBlue,
                      ),
                      hint: const Text(
                        'All Types',
                        style: TextStyle(
                          color: AppTheme.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryBlue,
                      ),
                      items: const [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            'All Types',
                            style: TextStyle(color: AppTheme.grey),
                          ),
                        ),
                        DropdownMenuItem<String?>(
                          value: 'low_stock',
                          child: Text('Low Stock'),
                        ),
                        DropdownMenuItem<String?>(
                          value: 'out_of_stock',
                          child: Text('Out of Stock'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _filterType = value;
                        });
                        _loadNotifications();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Notifications List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_none,
                              size: 64,
                              color: Colors.grey.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No notifications',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadNotifications,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _notifications.length,
                          itemBuilder: (context, index) {
                            return _buildNotificationCard(_notifications[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
