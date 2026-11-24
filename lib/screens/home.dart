import 'package:flutter/material.dart';

import '../state.dart';
import '../widgets.dart';
import 'appointments.dart';
import 'customers.dart';
import 'dashboard.dart';
import 'invoices.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  Future<void> _logout() async {
    final ok = await confirmDestructive(context, title: 'Sign out?', message: 'You will need to sign in again.', confirmLabel: 'Sign out');
    if (ok) await appState.logout();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <_Tab>[
      _Tab('Home', Icons.dashboard_outlined, const DashboardScreen()),
      if (appState.can('appointment.read') || appState.can('appointment.read_all')) _Tab('Appointments', Icons.event_outlined, const AppointmentsScreen()),
      if (appState.can('customer.read')) _Tab('Customers', Icons.people_outline, const CustomersScreen()),
      if (appState.can('invoice.read')) _Tab('Billing', Icons.receipt_long_outlined, const InvoicesScreen()),
    ];
    if (_index >= tabs.length) _index = 0;
    final icon = appState.themeMode == ThemeMode.dark ? Icons.dark_mode : appState.themeMode == ThemeMode.light ? Icons.light_mode : Icons.brightness_auto;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(appState.outletName.isEmpty ? 'Salon OS' : appState.outletName, style: const TextStyle(fontSize: 18)),
          Text('${appState.userName} · ${appState.roleLabel}', style: const TextStyle(fontSize: 12)),
        ]),
        actions: [
          IconButton(tooltip: 'Theme', icon: Icon(icon), onPressed: appState.cycleTheme),
          IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: KeyedSubtree(key: ValueKey(_index), child: tabs[_index].page)),
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.icon), label: t.label)],
            ),
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  final Widget page;
  _Tab(this.label, this.icon, this.page);
}
