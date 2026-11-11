import 'package:supabase_flutter/supabase_flutter.dart';

final Map<String, List<String>> _companyKeyCache = {};

/// Resolve every identifier that may be stored on rows for this company:
/// tally_companies.id and tally_companies.Guid.
Future<List<String>> companyKeys(String? companyId) async {
  if (companyId == null || companyId.trim().isEmpty || companyId == 'ALL') {
    return const [];
  }
  final key = companyId.trim();
  final cached = _companyKeyCache[key];
  if (cached != null) return cached;

  final keys = <String>{key};
  try {
    final client = Supabase.instance.client;
    Map<String, dynamic>? row = await client
        .from('tally_companies')
        .select('id, Guid')
        .eq('id', key)
        .maybeSingle();
    row ??= await client
        .from('tally_companies')
        .select('id, Guid')
        .eq('Guid', key)
        .maybeSingle();
    if (row != null) {
      final id = (row['id'] as String?)?.trim();
      final guid = (row['Guid'] as String?)?.trim();
      if (id != null && id.isNotEmpty) keys.add(id);
      if (guid != null && guid.isNotEmpty) keys.add(guid);
    }
  } catch (_) {}

  final list = keys.toList();
  _companyKeyCache[key] = list;
  return list;
}

/// Filter a query on company_id matching id and/or Guid.
dynamic applyCompanyIdFilter(dynamic query, List<String> keys) {
  if (keys.isEmpty) return query;
  if (keys.length == 1) return query.eq('company_id', keys.first);
  return query.or(keys.map((k) => 'company_id.eq.$k').join(','));
}

/// Sales orders store the company Guid in the Guid column.
dynamic applySalesOrderCompanyFilter(dynamic query, List<String> keys) {
  if (keys.isEmpty) return query;
  final parts = <String>[];
  for (final k in keys) {
    parts.add('company_id.eq.$k');
    parts.add('Guid.eq.$k');
  }
  return query.or(parts.join(','));
}
