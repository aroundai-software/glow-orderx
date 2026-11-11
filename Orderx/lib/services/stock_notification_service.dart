import 'package:Orderx/models/stock_notification_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StockNotificationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Send a stock notification to admin
  Future<void> sendStockNotification({
    required String productId,
    required String productName,
    required int stockLevel,
    required String notificationType,
    required String salesmanId,
    required String salesmanName,
    String? companyId,
  }) async {
    try {
      print('📤 Sending stock notification...');
      print('   Product: $productName');
      print('   Stock Level: $stockLevel');
      print('   Type: $notificationType');
      print('   Company ID: $companyId');

      // Check if a similar notification already exists (within last 24 hours)
      final existingNotifications = await _supabase
          .from('notifications')
          .select()
          .eq('product_id', productId)
          .eq('salesman_id', salesmanId)
          .eq('type', notificationType)
          .gte('created_at', DateTime.now().toUtc().subtract(const Duration(hours: 24)).toIso8601String())
          .order('created_at', ascending: false)
          .limit(1);

      if (existingNotifications.isNotEmpty) {
        print('   ⚠️ Similar notification already sent within 24 hours');
        throw Exception('You have already sent a notification for this product in the last 24 hours');
      }

      // Create title and message based on type
      final title = notificationType == 'out_of_stock' ? 'Out of Stock Alert' : 'Low Stock Alert';
      final message = notificationType == 'out_of_stock'
          ? '$productName is out of stock'
          : '$productName is running low (Stock: $stockLevel)';

      // Insert new notification
      await _supabase.from('notifications').insert({
        'type': notificationType,
        'title': title,
        'message': message,
        'product_id': productId,
        'product_name': productName,
        'current_stock': stockLevel,
        'salesman_id': salesmanId,
        'salesman_name': salesmanName,
        'company_id': companyId,
        'is_read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      print('   ✅ Stock notification sent successfully');
    } catch (e) {
      print('   ❌ Error sending stock notification: $e');
      rethrow;
    }
  }

  /// Get all stock notifications (for admin)
  Future<List<StockNotificationModel>> getAllNotifications({
    bool? isRead,
    String? notificationType,
    String? companyId,
  }) async {
    try {
      print('📥 Fetching stock notifications...');

      var query = _supabase
          .from('notifications')
          .select();

      if (isRead != null) {
        query = query.eq('is_read', isRead);
      }

      if (notificationType != null) {
        query = query.eq('type', notificationType);
      }

      if (companyId != null) {
        query = query.eq('company_id', companyId);
      }

      final response = await query.order('created_at', ascending: false);
      
      final notifications = (response as List)
          .map((json) => StockNotificationModel.fromJson(json))
          .toList();

      print('   ✅ Fetched ${notifications.length} notifications');
      return notifications;
    } catch (e) {
      print('   ❌ Error fetching notifications: $e');
      rethrow;
    }
  }

  /// Get unread notification count
  Future<int> getUnreadCount({String? companyId}) async {
    try {
      var query = _supabase
          .from('notifications')
          .select()
          .eq('is_read', false);

      // Filter by company_id if provided
      if (companyId != null) {
        query = query.eq('company_id', companyId);
      }

      final response = await query;

      return (response as List).length;
    } catch (e) {
      print('   ❌ Error getting unread count: $e');
      return 0;
    }
  }

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      await _supabase
          .from('notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', notificationId);

      print('   ✅ Notification marked as read');
    } catch (e) {
      print('   ❌ Error marking notification as read: $e');
      rethrow;
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    try {
      await _supabase
          .from('notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('is_read', false);

      print('   ✅ All notifications marked as read');
    } catch (e) {
      print('   ❌ Error marking all notifications as read: $e');
      rethrow;
    }
  }

  /// Delete a notification
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _supabase
          .from('notifications')
          .delete()
          .eq('id', notificationId);

      print('   ✅ Notification deleted');
    } catch (e) {
      print('   ❌ Error deleting notification: $e');
      rethrow;
    }
  }

  /// Get notifications by salesman
  Future<List<StockNotificationModel>> getNotificationsBySalesman(String salesmanId) async {
    try {
      final response = await _supabase
          .from('notifications')
          .select()
          .eq('salesman_id', salesmanId)
          .order('created_at', ascending: false);

      final notifications = (response as List)
          .map((json) => StockNotificationModel.fromJson(json))
          .toList();

      return notifications;
    } catch (e) {
      print('   ❌ Error fetching salesman notifications: $e');
      rethrow;
    }
  }
}
