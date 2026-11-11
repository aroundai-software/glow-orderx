import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/outstanding_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/customer_service.dart';
import 'package:Orderx/services/outstanding_followup_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class OutstandingDetailsScreen extends StatefulWidget {
  final OutstandingModel outstanding;

  const OutstandingDetailsScreen({super.key, required this.outstanding});

  @override
  State<OutstandingDetailsScreen> createState() => _OutstandingDetailsScreenState();
}

class _OutstandingDetailsScreenState extends State<OutstandingDetailsScreen> {
  final CustomerService _customerService = CustomerService();
  final OutstandingFollowUpService _followUpService = OutstandingFollowUpService();
  final TextEditingController _remarkController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  OutstandingFollowUpMeta _meta = OutstandingFollowUpMeta.empty();
  Map<String, dynamic>? _customer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final meta = await _followUpService.getForId(widget.outstanding.id);

      Map<String, dynamic>? customer;
      try {
        final results = await _customerService.searchCustomers(widget.outstanding.customerName);
        final match = results.where((c) => c.customerName == widget.outstanding.customerName).toList();
        if (match.isNotEmpty) {
          final c = match.first;
          customer = {
            'mobile_number': c.mobileNumber,
            'address': c.address,
            'city': c.city,
            'state': c.state,
            'pincode': c.pincode,
            'gst_number': c.gstNumber,
          };
        }
      } catch (_) {
        customer = null;
      }

      if (!mounted) return;
      setState(() {
        _meta = meta;
        _remarkController.text = meta.remark;
        _customer = customer;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading details: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  String _normalizePhone(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return '';
    final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    if (digits.length == 10) return '91$digits';
    if (digits.length == 11 && digits.startsWith('0')) return '91${digits.substring(1)}';
    return digits;
  }

  String _buildWhatsAppMessage(DateFormat dateFormat) {
    final due = _meta.followUpDate ?? widget.outstanding.dueDate;
    final dueText = due != null ? dateFormat.format(due) : 'Not set';
    final remark = (_meta.remark).trim();

    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final amount = currency.format(widget.outstanding.closingBalance);

    final buffer = StringBuffer();
    buffer.writeln('Hi ${widget.outstanding.customerName},');
    buffer.writeln();
    buffer.writeln('Reminder for your pending payment:');
    buffer.writeln('Invoice: ${widget.outstanding.invoiceNumber}');
    buffer.writeln('Amount: $amount');
    buffer.writeln('Due/Follow-up date: $dueText');
    if (remark.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Note: $remark');
    }
    buffer.writeln();
    buffer.writeln('Thank you.');
    return buffer.toString();
  }

  Future<void> _shareOnWhatsApp() async {
    final dateFormat = DateFormat('dd MMM yyyy');
    final text = _buildWhatsAppMessage(dateFormat);
    final phoneRaw = _customer?['mobile_number'] as String?;
    final phone = _normalizePhone(phoneRaw);

    try {
      final whatsappUri = Uri.parse(
        phone.isEmpty
            ? 'whatsapp://send?text=${Uri.encodeComponent(text)}'
            : 'whatsapp://send?phone=$phone&text=${Uri.encodeComponent(text)}',
      );

      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
        return;
      }

      final waMeUri = Uri.parse(
        phone.isEmpty
            ? 'https://wa.me/?text=${Uri.encodeComponent(text)}'
            : 'https://wa.me/$phone?text=${Uri.encodeComponent(text)}',
      );
      await launchUrl(waMeUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open WhatsApp: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  Future<DateTime?> _pickDateWithMonthYearSelector(DateTime initial) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 2, 1, 1);
    final lastDate = DateTime(now.year + 5, 12, 31);

    DateTime selected = DateTime(initial.year, initial.month, initial.day);
    int selectedMonth = selected.month;
    int selectedYear = selected.year;

    return showDialog<DateTime>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final calendarKey = ValueKey('$selectedYear-$selectedMonth');
            final months = List.generate(12, (i) => i + 1);
            final years = List.generate(
              lastDate.year - firstDate.year + 1,
              (i) => firstDate.year + i,
            );

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Select date'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedMonth,
                            decoration: const InputDecoration(
                              labelText: 'Month',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: months
                                .map(
                                  (m) => DropdownMenuItem<int>(
                                    value: m,
                                    child: Text(DateFormat('MMMM').format(DateTime(2000, m, 1))),
                                  ),
                                )
                                .toList(),
                            onChanged: (m) {
                              if (m == null) return;
                              setState(() {
                                selectedMonth = m;
                                final day = selected.day.clamp(1, _daysInMonth(selectedYear, selectedMonth));
                                selected = DateTime(selectedYear, selectedMonth, day);
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedYear,
                            decoration: const InputDecoration(
                              labelText: 'Year',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: years
                                .map(
                                  (y) => DropdownMenuItem<int>(
                                    value: y,
                                    child: Text('$y'),
                                  ),
                                )
                                .toList(),
                            onChanged: (y) {
                              if (y == null) return;
                              setState(() {
                                selectedYear = y;
                                final day = selected.day.clamp(1, _daysInMonth(selectedYear, selectedMonth));
                                selected = DateTime(selectedYear, selectedMonth, day);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 320,
                      child: CalendarDatePicker(
                        key: calendarKey,
                        initialDate: selected,
                        firstDate: firstDate,
                        lastDate: lastDate,
                        currentDate: DateTime.now(),
                        onDateChanged: (d) {
                          setState(() {
                            selected = DateTime(d.year, d.month, d.day);
                            selectedMonth = d.month;
                            selectedYear = d.year;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, DateTime(0)),
                  child: const Text('Clear'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _setDueOrFollowUpDate(DateTime? date) async {
    setState(() => _isSaving = true);
    try {
      await _followUpService.setFollowUpDate(widget.outstanding.id, date);
      if (!mounted) return;
      setState(() {
        _meta = _meta.copyWith(followUpDate: date);
        _isSaving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving date: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _pickFollowUpDate() async {
    final now = DateTime.now();
    final initial = _meta.followUpDate ?? widget.outstanding.dueDate ?? now;

    final picked = await _pickDateWithMonthYearSelector(
      DateTime(initial.year, initial.month, initial.day),
    );

    if (picked == null) return;

    if (picked.year == 0) {
      await _setDueOrFollowUpDate(null);
      return;
    }

    await _setDueOrFollowUpDate(picked);
  }

  Future<void> _togglePaymentReceived(bool value) async {
    setState(() => _isSaving = true);
    try {
      await _followUpService.setPaymentReceived(widget.outstanding.id, value);
      final updated = await _followUpService.getForId(widget.outstanding.id);
      if (!mounted) return;
      setState(() {
        _meta = updated;
        _remarkController.text = updated.remark;
        _isSaving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving payment status: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  Future<void> _saveRemark() async {
    setState(() => _isSaving = true);
    try {
      await _followUpService.setRemark(
        widget.outstanding.id,
        _remarkController.text,
      );
      final updated = await _followUpService.getForId(widget.outstanding.id);
      if (!mounted) return;
      setState(() {
        _meta = updated;
        _remarkController.text = updated.remark;
        _isSaving = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remark saved'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving remark: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _markComplete() async {
    setState(() => _isSaving = true);
    try {
      await _followUpService.markFollowedUp(widget.outstanding.id);
      final updated = await _followUpService.getForId(widget.outstanding.id);
      if (!mounted) return;
      setState(() {
        _meta = updated;
        _remarkController.text = updated.remark;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marked as complete for today'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error marking complete: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final dateFormat = DateFormat('dd MMM yyyy');
    final dateTimeFormat = DateFormat('dd MMM yyyy, hh:mm a');

    final userType = context.watch<AuthProvider>().currentUser?.userType;
    final isAdminUser = userType == 'admin';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final effectiveDueDate = _meta.followUpDate ?? widget.outstanding.dueDate;

    final isCleared = widget.outstanding.closingBalance <= 0;
    final isPaid = _meta.paymentReceived;
    final canFollowUp = !isCleared && !isPaid && !isAdminUser;

    final isTodayFollowUp =
        effectiveDueDate != null && _isSameDate(effectiveDueDate, today);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Outstanding Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.outstanding.customerName,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              _infoRow('Invoice', widget.outstanding.invoiceNumber),
                              _infoRow('Date', dateFormat.format(widget.outstanding.date)),
                              if (effectiveDueDate != null)
                                _infoRow(
                                    'Due Date', dateFormat.format(effectiveDueDate)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Balance',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              _infoRow('Opening', currencyFormat.format(widget.outstanding.openingBalance)),
                              _infoRow('Closing', currencyFormat.format(widget.outstanding.closingBalance)),
                              _infoRow('Outstanding', currencyFormat.format(widget.outstanding.outstandingAmount)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_customer != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Customer Details',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                if ((_customer?['mobile_number'] as String?)?.isNotEmpty == true)
                                  _infoRow('Mobile', _customer?['mobile_number'] as String),
                                if ((_customer?['address'] as String?)?.isNotEmpty == true)
                                  _infoRow('Address', _customer?['address'] as String),
                                if ((_customer?['city'] as String?)?.isNotEmpty == true)
                                  _infoRow('City', _customer?['city'] as String),
                                if ((_customer?['state'] as String?)?.isNotEmpty == true)
                                  _infoRow('State', _customer?['state'] as String),
                                if ((_customer?['pincode'] as String?)?.isNotEmpty == true)
                                  _infoRow('Pincode', _customer?['pincode'] as String),
                                if ((_customer?['gst_number'] as String?)?.isNotEmpty == true)
                                  _infoRow('GST', _customer?['gst_number'] as String),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Remark',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              if (isAdminUser)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppTheme.primaryBlue.withOpacity(0.12),
                                    ),
                                  ),
                                  child: Text(
                                    (_meta.remark).trim().isEmpty
                                        ? 'No remark'
                                        : (_meta.remark).trim(),
                                    style: TextStyle(
                                      color: (_meta.remark).trim().isEmpty
                                          ? AppTheme.grey
                                          : null,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              else ...[
                                TextField(
                                  controller: _remarkController,
                                  minLines: 2,
                                  maxLines: 5,
                                  textInputAction: TextInputAction.newline,
                                  decoration: InputDecoration(
                                    hintText: 'Add remark / follow-up note...',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _isSaving
                                          ? null
                                          : () {
                                              _remarkController.clear();
                                              _saveRemark();
                                            },
                                      icon: const Icon(Icons.clear, size: 18),
                                      label: const Text('Clear'),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _isSaving ? null : _saveRemark,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryBlue,
                                          padding:
                                              const EdgeInsets.symmetric(vertical: 12),
                                        ),
                                        icon: const Icon(Icons.save_outlined),
                                        label: const Text('Save remark'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Follow-up',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  if (isTodayFollowUp)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.warning.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'Today',
                                        style: TextStyle(
                                          color: AppTheme.warning,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_hasAnyActorInfo(_meta)) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue.withOpacity(0.04),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppTheme.primaryBlue.withOpacity(0.12),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Activity',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      if ((_meta.createdByName).trim().isNotEmpty)
                                        _activityRow(
                                          'Created by',
                                          _formatActorLine(
                                            _meta.createdByName,
                                            _meta.createdByType,
                                            _meta.createdAt,
                                            dateTimeFormat,
                                          ),
                                        ),
                                      if ((_meta.lastUpdatedByName).trim().isNotEmpty)
                                        _activityRow(
                                          'Last updated',
                                          _formatActorLine(
                                            _meta.lastUpdatedByName,
                                            _meta.lastUpdatedByType,
                                            _meta.updatedAt,
                                            dateTimeFormat,
                                          ),
                                        ),
                                      if ((_meta.lastFollowedUpByName).trim().isNotEmpty ||
                                          _meta.lastFollowedUpAt != null)
                                        _activityRow(
                                          'Last completed',
                                          _formatActorLine(
                                            (_meta.lastFollowedUpByName).trim().isNotEmpty
                                                ? _meta.lastFollowedUpByName
                                                : '—',
                                            _meta.lastFollowedUpByType,
                                            _meta.lastFollowedUpAt,
                                            dateTimeFormat,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppTheme.primaryBlue.withOpacity(0.2),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryBlue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.event,
                                        color: AppTheme.primaryBlue,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Due / follow-up date',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            effectiveDueDate != null
                                                ? dateFormat.format(effectiveDueDate)
                                                : 'Not set',
                                            style: TextStyle(
                                              color: effectiveDueDate == null
                                                  ? AppTheme.grey
                                                  : null,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed:
                                          (_isSaving || isAdminUser) ? null : _pickFollowUpDate,
                                      icon: const Icon(Icons.edit, size: 18),
                                      label: const Text('Change'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppTheme.primaryBlue,
                                        side: BorderSide(
                                          color: AppTheme.primaryBlue.withOpacity(0.4),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ActionChip(
                                    label: const Text('Today'),
                                    onPressed: (_isSaving || isAdminUser)
                                        ? null
                                        : () {
                                            final now = DateTime.now();
                                            final d = DateTime(now.year, now.month, now.day);
                                            _setDueOrFollowUpDate(d);
                                          },
                                  ),
                                  ActionChip(
                                    label: const Text('Tomorrow'),
                                    onPressed: (_isSaving || isAdminUser)
                                        ? null
                                        : () {
                                            final now = DateTime.now();
                                            final d = DateTime(now.year, now.month, now.day)
                                                .add(const Duration(days: 1));
                                            _setDueOrFollowUpDate(d);
                                          },
                                  ),
                                  ActionChip(
                                    label: const Text('+7 days'),
                                    onPressed: (_isSaving || isAdminUser)
                                        ? null
                                        : () {
                                            final now = DateTime.now();
                                            final d = DateTime(now.year, now.month, now.day)
                                                .add(const Duration(days: 7));
                                            _setDueOrFollowUpDate(d);
                                          },
                                  ),
                                  ActionChip(
                                    label: const Text('Clear'),
                                    onPressed: (_isSaving || isAdminUser)
                                        ? null
                                        : () => _setDueOrFollowUpDate(null),
                                  ),
                                ],
                              ),
                              if (!isAdminUser) ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _isSaving ? null : _shareOnWhatsApp,
                                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                                    label: const Text('Share on WhatsApp'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF25D366),
                                      side: const BorderSide(color: Color(0xFF25D366)),
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppTheme.primaryBlue.withOpacity(0.15),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: AppTheme.success.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        _meta.paymentReceived
                                            ? Icons.verified
                                            : Icons.payments_outlined,
                                        color: AppTheme.success,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Payment received',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _meta.paymentReceived ? 'Yes' : 'No',
                                            style: TextStyle(
                                              color: _meta.paymentReceived
                                                  ? AppTheme.success
                                                  : AppTheme.grey,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: _meta.paymentReceived,
                                      onChanged:
                                          (_isSaving || isAdminUser)
                                              ? null
                                              : _togglePaymentReceived,
                                      activeThumbColor: AppTheme.success,
                                    ),
                                  ],
                                ),
                              ),
                              if (_meta.paymentReceivedAt != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Paid at: ${dateTimeFormat.format(_meta.paymentReceivedAt!.toLocal())}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.success,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryBlue.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppTheme.primaryBlue.withOpacity(0.12),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Follow-ups done',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.grey,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${_meta.followUpCount}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      (_isSaving || !canFollowUp) ? null : _markComplete,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.success,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: Text(
                                    canFollowUp
                                        ? 'Mark follow-up complete'
                                        : (isAdminUser
                                            ? 'View only (admin)'
                                            : (isCleared
                                                ? 'Already cleared'
                                                : 'Already paid')),
                                  ),
                                ),
                              ),
                              if (_meta.lastFollowedUpAt != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Last completed: ${DateFormat('dd MMM yyyy, hh:mm a').format(_meta.lastFollowedUpAt!.toLocal())}',
                                  style: const TextStyle(color: AppTheme.grey, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                if (_isSaving)
                  Container(
                    color: Colors.white.withOpacity(0.7),
                    child: const Center(
                      child: CircularProgressIndicator(color: AppTheme.primaryBlue),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.grey),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  bool _hasAnyActorInfo(OutstandingFollowUpMeta meta) {
    return meta.createdByName.trim().isNotEmpty ||
        meta.lastUpdatedByName.trim().isNotEmpty ||
        meta.lastFollowedUpByName.trim().isNotEmpty ||
        meta.createdAt != null ||
        meta.updatedAt != null ||
        meta.lastFollowedUpAt != null;
  }

  Widget _activityRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.grey,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatActorLine(
    String name,
    String type,
    DateTime? at,
    DateFormat dateTimeFormat,
  ) {
    final safeName = name.trim().isEmpty ? '—' : name.trim();
    final safeType = type.trim();
    final who = safeType.isEmpty ? safeName : '$safeName ($safeType)';
    if (at == null) return who;
    return '$who • ${dateTimeFormat.format(at.toLocal())}';
  }
}
