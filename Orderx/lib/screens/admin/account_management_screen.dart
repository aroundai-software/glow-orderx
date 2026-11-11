import 'package:flutter/material.dart';
import 'package:Orderx/screens/admin/salesman_management_tab.dart';
import 'package:Orderx/screens/admin/admin_management_tab.dart';
import 'package:Orderx/screens/admin/salesman_sessions_screen.dart';
import 'package:Orderx/widgets/app_bar_actions.dart';

class AccountManagementScreen extends StatelessWidget {
  const AccountManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Account Management'),
          actions: const [
            GlobalCompanySwitcher(),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Salesmen'),
              Tab(text: 'Admins'),
              Tab(text: 'Active Sessions'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            SalesmanManagementTab(),
            AdminManagementTab(),
            SalesmanSessionsTab(),
          ],
        ),
      ),
    );
  }
}
