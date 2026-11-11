import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/company_selection_service.dart';

class CompanyDisplayWidget extends StatelessWidget {
  const CompanyDisplayWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final companyId = authProvider.selectedCompanyId;

    if (companyId == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: CompanySelectionService().getCompanyById(companyId),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          final companyName = snapshot.data!['company_name'] as String? ?? 'Unknown';
          return Text(
            companyName,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white70,
              fontWeight: FontWeight.w300,
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
