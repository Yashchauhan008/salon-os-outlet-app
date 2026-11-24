import 'package:flutter/material.dart';

import '../api.dart';
import '../state.dart';
import '../widgets.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _q = TextEditingController();
  late Future<dynamic> _f = _load();

  Future<dynamic> _load() => appState.api.get('/customers', query: {'limit': '50', if (_q.text.trim().isNotEmpty) 'q': _q.text.trim()});
  void _search() => setState(() => _f = _load());

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New customer'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (with country code)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await appState.api.post('/customers', body: {'full_name': name.text.trim(), 'phone': phone.text.trim()});
        if (mounted) _search();
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
    name.dispose();
    phone.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: appState.can('customer.create') ? FloatingActionButton(onPressed: _add, tooltip: 'New customer', child: const Icon(Icons.person_add)) : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(controller: _q, textInputAction: TextInputAction.search, onSubmitted: (_) => _search(), decoration: InputDecoration(hintText: 'Search name or phone', prefixIcon: const Icon(Icons.search), border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search))),
        ),
        Expanded(
          child: FutureBuilder<dynamic>(
            future: _f,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Loading();
              if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _search);
              final rows = (snap.data['data'] as List).cast<Map<String, dynamic>>();
              if (rows.isEmpty) return const EmptyView('No customers found.');
              return ListView.builder(
                itemCount: rows.length,
                itemBuilder: (c, i) => FadeIn(index: i, child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text('${rows[i]['full_name']}'), subtitle: Text('${rows[i]['normalized_phone'] ?? ''}'))),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// Silences unused import warnings if ApiException is only used in other files.
// ignore: unused_element
Type _t = ApiException;
