import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/outstanding_model.dart';
import 'package:Orderx/services/outstanding_followup_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CompletedCustomerHistoryScreen extends StatelessWidget {
  final String customerName;
  final List<OutstandingModel> invoices;
  final Map<String, OutstandingFollowUpMeta> followUps;

  const CompletedCustomerHistoryScreen({
    super.key,
    required this.customerName,
    required this.invoices,
    required this.followUps,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final dateFormat = DateFormat('dd MMM yyyy');
    final dateTimeFormat = DateFormat('dd MMM yyyy, hh:mm a');

    final sortedInvoices = [...invoices]..sort((a, b) => b.date.compareTo(a.date));

    int totalFollowUps = 0;
    DateTime? lastPaymentAt;

    for (final inv in sortedInvoices) {
      final meta = followUps[inv.id];
      totalFollowUps += meta?.followUpCount ?? 0;
      final paidAt = meta?.paymentReceivedAt;
      if (paidAt != null) {
        if (lastPaymentAt == null || paidAt.isAfter(lastPaymentAt)) {
          lastPaymentAt = paidAt;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(customerName),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _summaryItem(
                      label: 'Invoices',
                      value: '${sortedInvoices.length}',
                      color: AppTheme.primaryBlue,
                    ),
                    _summaryItem(
                      label: 'Follow-ups',
                      value: '$totalFollowUps',
                      color: AppTheme.warning,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (lastPaymentAt != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.verified, color: AppTheme.success),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Last paid',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(dateTimeFormat.format(lastPaymentAt.toLocal())),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Invoices History',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            ...sortedInvoices.map((inv) {
              final meta = followUps[inv.id];
              final hasBalance = inv.closingBalance > 0;
              final isPaid = meta?.paymentReceived == true;
              final isCleared = inv.closingBalance <= 0;

              final statusText = isCleared
                  ? 'Cleared'
                  : (isPaid ? 'Paid' : (hasBalance ? 'Pending' : 'Cleared'));

              final statusColor = isCleared
                  ? AppTheme.success
                  : (isPaid
                      ? AppTheme.success
                      : (hasBalance ? AppTheme.warning : AppTheme.success));

              final followUpCount = meta?.followUpCount ?? 0;
              final paidAt = meta?.paymentReceivedAt;
              final lastFollowed = meta?.lastFollowedUpAt;
              final followUpLog = meta?.followUpLog ?? const <DateTime>[];
              final remark = (meta?.remark ?? '').trim();
              final createdByName = (meta?.createdByName ?? '').trim();
              final lastCompletedByName = (meta?.lastFollowedUpByName ?? '').trim();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Invoice: ${inv.invoiceNumber}',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text('Date: ${dateFormat.format(inv.date)}'),
                                if (inv.dueDate != null)
                                  Text('Due: ${dateFormat.format(inv.dueDate!)}'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                currencyFormat.format(inv.closingBalance),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _miniInfo(
                            label: 'Follow-ups',
                            value: '$followUpCount',
                          ),
                          const SizedBox(width: 12),
                          if (paidAt != null)
                            _miniInfo(
                              label: 'Paid at',
                              value: dateTimeFormat.format(paidAt.toLocal()),
                            ),
                        ],
                      ),
                      if (remark.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.primaryBlue.withOpacity(0.12),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color:
                                        AppTheme.primaryBlue.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.sticky_note_2_outlined,
                                    color: AppTheme.primaryBlue,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    remark,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (createdByName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Created by: $createdByName',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (lastCompletedByName.isNotEmpty && lastFollowed != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Last completed by: $lastCompletedByName • ${dateTimeFormat.format(lastFollowed.toLocal())}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (isPaid)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Paid after $followUpCount follow-ups',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.success,
                            ),
                          ),
                        ),
                      if (lastFollowed != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Last follow-up: ${dateTimeFormat.format(lastFollowed.toLocal())}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.grey),
                          ),
                        ),
                      if (followUpLog.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                showDragHandle: true,
                                builder: (context) {
                                  final logs = [...followUpLog]
                                    ..sort((a, b) => b.compareTo(a));
                                  return SafeArea(
                                    child: ListView.separated(
                                      padding: const EdgeInsets.all(16),
                                      itemCount: logs.length,
                                      separatorBuilder: (_, __) => const Divider(height: 16),
                                      itemBuilder: (context, i) {
                                        final d = logs[i];
                                        return Row(
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryBlue.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: const Icon(Icons.call, color: AppTheme.primaryBlue),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(dateTimeFormat.format(d.toLocal())),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  );
                                },
                              );
                            },
                            icon: const Icon(Icons.history),
                            label: Text('View follow-ups (${followUpLog.length})'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.grey),
        ),
      ],
    );
  }

  Widget _miniInfo({required String label, required String value}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppTheme.grey),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
