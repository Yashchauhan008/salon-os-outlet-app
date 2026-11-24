import 'package:flutter/material.dart';

import '../format.dart';
import '../state.dart';
import '../widgets.dart';
import 'invoices.dart';

const _next = <String, List<List<String>>>{
  'requested': [['confirmed', 'Confirm']],
  'confirmed': [['checked_in', 'Check in'], ['no_show', 'No-show']],
  'checked_in': [['in_service', 'Start service']],
  'in_service': [['completed', 'Complete']],
};
const _destructive = {'cancelled', 'no_show'};

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});
  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  DateTime _day = DateTime.now();
  late Future<dynamic> _f = _load();

  Future<dynamic> _load() => appState.api.get('/appointments', query: {'date': ymd(_day), 'days': '1', 'limit': '100'});
  void _reload() => setState(() => _f = _load());

  void _shift(int d) {
    _day = _day.add(Duration(days: d));
    _reload();
  }

  Future<void> _setStatus(Map<String, dynamic> a, String status) async {
    String? reason;
    if (_destructive.contains(status)) {
      reason = await confirmWithReason(context, title: status == 'cancelled' ? 'Cancel appointment?' : 'Mark as no-show?', message: '${a['customer_name']} at ${timeLabel(parseApiTime('${a['start_at']}'))}', confirmLabel: status == 'cancelled' ? 'Cancel appointment' : 'Mark no-show');
      if (reason == null) return;
    }
    try {
      await appState.api.post('/appointments/${a['id']}/status', body: {'status': status, if (reason != null && reason.isNotEmpty) 'reason': reason});
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _invoice(Map<String, dynamic> a) async {
    try {
      final inv = await appState.api.post('/invoices', body: {'appointment_id': a['id']}) as Map<String, dynamic>;
      if (mounted) await showInvoice(context, inv['id'] as String);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _book({required bool walkIn}) async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => BookScreen(walkIn: walkIn, day: _day)));
    if (done == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = appState.can('appointment.create');
    return Scaffold(
      floatingActionButton: canCreate
          ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              FloatingActionButton.small(heroTag: 'walkin', tooltip: 'Walk-in', onPressed: () => _book(walkIn: true), child: const Icon(Icons.directions_walk)),
              const SizedBox(height: 8),
              FloatingActionButton.extended(heroTag: 'book', onPressed: () => _book(walkIn: false), icon: const Icon(Icons.add), label: const Text('Book')),
            ])
          : null,
      body: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
          TextButton(
            onPressed: () async {
              final p = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (p != null) { _day = p; _reload(); }
            },
            child: Text(dayLabel(_day)),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
        ]),
        Expanded(
          child: FutureBuilder<dynamic>(
            future: _f,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Loading();
              if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
              final rows = (snap.data['data'] as List).cast<Map<String, dynamic>>();
              if (rows.isEmpty) return const EmptyView('No appointments for this day.');
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 140),
                  itemCount: rows.length,
                  itemBuilder: (c, i) {
                    final a = rows[i];
                    final status = '${a['status']}';
                    final items = (a['items'] as List).map((e) => '${(e as Map)['name']}').join(', ');
                    final actions = canCreate || appState.can('appointment.update') ? (_next[status] ?? const <List<String>>[]) : const <List<String>>[];
                    final cancellable = const ['requested', 'confirmed', 'checked_in'].contains(status) && appState.can('appointment.update');
                    return FadeIn(
                      index: i,
                      child: Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text('${timeLabel(parseApiTime('${a['start_at']}'))} · ${a['customer_name']}', style: Theme.of(context).textTheme.titleSmall)),
                              StatusChip(status),
                            ]),
                            Text(items),
                            Text('${a['employee_name'] ?? 'Unassigned'} · ${money(a['total_price'])}${a['source'] == 'walk_in' ? ' · walk-in' : ''}', style: Theme.of(context).textTheme.bodySmall),
                            Wrap(spacing: 8, children: [
                              for (final act in actions) TextButton(onPressed: () => _setStatus(a, act[0]), child: Text(act[1])),
                              if (['checked_in', 'in_service', 'completed'].contains(status) && appState.can('invoice.create')) TextButton(onPressed: () => _invoice(a), child: const Text('Invoice')),
                              if (cancellable) TextButton(style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), onPressed: () => _setStatus(a, 'cancelled'), child: const Text('Cancel')),
                            ]),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class BookScreen extends StatefulWidget {
  final bool walkIn;
  final DateTime day;
  const BookScreen({super.key, required this.walkIn, required this.day});
  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _customers = [];
  Map<String, dynamic>? _customer;
  List<Map<String, dynamic>> _services = [];
  final Set<String> _picked = {};
  late DateTime _date = widget.day;
  Map<String, dynamic>? _avail;
  Map<String, dynamic>? _slot;
  String? _employeeId;
  bool _busy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    try {
      final d = await appState.api.get('/outlets/${appState.outletId}/services');
      final all = (d['data'] as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _services = all.where((s) => s['is_available'] == true).toList());
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  Future<void> _search() async {
    if (_q.text.trim().length < 2) return;
    try {
      final d = await appState.api.get('/customers', query: {'q': _q.text.trim(), 'limit': '6'});
      if (mounted) setState(() => _customers = (d['data'] as List).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _loadSlots() async {
    if (_picked.isEmpty || widget.walkIn) return;
    setState(() { _avail = null; _slot = null; });
    try {
      final d = await appState.api.get('/appointments/availability', query: {'outlet_id': '${appState.outletId}', 'date': ymd(_date), 'service_ids': _picked.join(',')});
      if (mounted) setState(() => _avail = d as Map<String, dynamic>);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{'customer_id': _customer!['id'], 'service_ids': _picked.toList(), if (_employeeId != null) 'employee_id': _employeeId};
      if (widget.walkIn) {
        await appState.api.post('/appointments/walk-in', body: body);
      } else {
        body['start_at'] = _slot!['start_at'];
        await appState.api.post('/appointments', body: body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        if (!widget.walkIn) _loadSlots();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = (_avail?['slots'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final employees = (_avail?['employees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final visible = _employeeId == null ? slots : slots.where((s) => (s['employee_ids'] as List).contains(_employeeId)).toList();
    final ready = _customer != null && _picked.isNotEmpty && (widget.walkIn || _slot != null);
    return Scaffold(
      appBar: AppBar(title: Text(widget.walkIn ? 'Walk-in' : 'Book appointment')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Customer', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (_customer != null)
          ListTile(contentPadding: EdgeInsets.zero, title: Text('${_customer!['full_name']}'), subtitle: Text('${_customer!['normalized_phone'] ?? ''}'), trailing: TextButton(onPressed: () => setState(() => _customer = null), child: const Text('Change')))
        else ...[
          TextField(controller: _q, textInputAction: TextInputAction.search, onSubmitted: (_) => _search(), decoration: InputDecoration(hintText: 'Search name or phone', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _search))),
          for (final c in _customers) ListTile(title: Text('${c['full_name']}'), subtitle: Text('${c['normalized_phone'] ?? ''}'), onTap: () => setState(() { _customer = c; _customers = []; })),
        ],
        const SizedBox(height: 16),
        Text('Services', style: Theme.of(context).textTheme.titleSmall),
        if (_loadError != null) Text(_loadError!),
        Wrap(spacing: 8, children: [
          for (final s in _services)
            FilterChip(
              label: Text('${s['name']} · ${money(s['effective_price'])}'),
              selected: _picked.contains(s['service_id']),
              onSelected: (v) {
                setState(() { v ? _picked.add('${s['service_id']}') : _picked.remove('${s['service_id']}'); });
                _loadSlots();
              },
            ),
        ]),
        if (!widget.walkIn) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text('Date: ${dayLabel(_date)}', style: Theme.of(context).textTheme.titleSmall)),
            TextButton(
              onPressed: () async {
                final p = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100));
                if (p != null) { setState(() => _date = p); _loadSlots(); }
              },
              child: const Text('Change'),
            ),
          ]),
          if (employees.isNotEmpty)
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('Any stylist'), selected: _employeeId == null, onSelected: (_) => setState(() { _employeeId = null; _slot = null; })),
              for (final e in employees) ChoiceChip(label: Text('${e['name']}'), selected: _employeeId == e['id'], onSelected: (_) => setState(() { _employeeId = '${e['id']}'; _slot = null; })),
            ]),
          const SizedBox(height: 8),
          if (_picked.isEmpty) const Text('Pick services to see free times.')
          else if (_avail == null) const Loading()
          else if (visible.isEmpty) const Text('No free times on this day.')
          else Wrap(spacing: 8, runSpacing: 4, children: [
            for (final s in visible) ChoiceChip(label: Text(timeLabel(parseApiTime('${s['start_at']}'))), selected: _slot == s, onSelected: (_) => setState(() => _slot = s)),
          ]),
        ] else ...[
          const SizedBox(height: 8),
          const Text('Starts now. The server picks the exact time.'),
        ],
        const SizedBox(height: 24),
        FilledButton(onPressed: ready && !_busy ? _save : null, child: Text(widget.walkIn ? 'Add walk-in' : 'Book')),
      ]),
    );
  }
}
