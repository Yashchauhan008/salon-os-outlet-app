import 'package:flutter/material.dart';

import '../format.dart';
import '../state.dart';
import '../widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<dynamic> _f = _load();
  Future<dynamic> _load() => appState.api.get('/dashboard/summary');
  Future<void> _reload() async {
    setState(() => _f = _load());
    await _f.catchError((_) => null);
  }

  Widget _tile(String label, String value, [String? sub]) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            if (sub != null) Text(sub, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Loading();
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
        final d = snap.data as Map<String, dynamic>;
        final t = d['today'] as Map<String, dynamic>;
        final a = t['appointments'] as Map<String, dynamic>;
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Padding(padding: const EdgeInsets.all(4), child: Text('Today · ${t['date']}', style: Theme.of(context).textTheme.titleMedium)),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.7,
              children: [
                _tile('Appointments', '${a['total']}', '${a['completed']} completed'),
                _tile('Walk-ins', '${a['walk_ins']}'),
                _tile('Sales', money(t['sales']), '${t['invoices']} invoices'),
                _tile('Collected', money(t['collections'])),
              ],
            ),
          ]),
        );
      },
    );
  }
}
