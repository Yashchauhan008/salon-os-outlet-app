import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../state.dart';
import '../widgets.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});
  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  String _status = '';
  late Future<dynamic> _f = _load();
  Future<dynamic> _load() => appState.api.get('/invoices', query: {'limit': '50', if (_status.isNotEmpty) 'status': _status});
  void _reload() => setState(() => _f = _load());

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(spacing: 8, children: [
          for (final s in const ['', 'open', 'paid', 'void'])
            ChoiceChip(label: Text(s.isEmpty ? 'All' : titleCase(s)), selected: _status == s, onSelected: (_) { _status = s; _reload(); }),
        ]),
      ),
      Expanded(
        child: FutureBuilder<dynamic>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Loading();
            if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
            final rows = (snap.data['data'] as List).cast<Map<String, dynamic>>();
            if (rows.isEmpty) return const EmptyView('No invoices yet.');
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (c, i) {
                  final r = rows[i];
                  return FadeIn(
                    index: i,
                    child: ListTile(
                      title: Text('${r['invoice_number']} · ${r['customer_name']}'),
                      subtitle: Text('Total ${money(r['total'])} · Due ${money(r['amount_due'])}'),
                      trailing: StatusChip('${r['status']}'),
                      onTap: () async {
                        await showInvoice(context, r['id'] as String);
                        _reload();
                      },
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    ]);
  }
}

Future<void> showInvoice(BuildContext context, String id) {
  return showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => InvoiceSheet(id: id));
}

class InvoiceSheet extends StatefulWidget {
  final String id;
  const InvoiceSheet({super.key, required this.id});
  @override
  State<InvoiceSheet> createState() => _InvoiceSheetState();
}

class _InvoiceSheetState extends State<InvoiceSheet> {
  Map<String, dynamic>? _inv;
  Object? _error;
  bool _busy = false;
  String _method = 'cash';
  final _amount = TextEditingController();
  String _payKey = newIdempotencyKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await appState.api.get('/invoices/${widget.id}');
      if (mounted) setState(() { _inv = d as Map<String, dynamic>; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay() => _run(() async {
        await appState.api.post('/invoices/${widget.id}/payments', body: {'method': _method, 'amount': _amount.text.trim()}, headers: {'Idempotency-Key': _payKey});
        _amount.clear();
        _payKey = newIdempotencyKey();
        if (mounted) showInfo(context, 'Payment recorded');
      });

  Future<void> _void() async {
    final reason = await confirmWithReason(context, title: 'Void this invoice?', message: 'This cannot be undone.', confirmLabel: 'Void invoice', reasonRequired: true);
    if (reason == null) return;
    await _run(() async => appState.api.post('/invoices/${widget.id}/void', body: {'reason': reason}));
  }

  Future<void> _refund(Map<String, dynamic> p) async {
    final reason = await confirmWithReason(context, title: 'Refund ${money(p['amount'])}?', message: 'The full payment will be refunded.', confirmLabel: 'Refund', reasonRequired: true);
    if (reason == null) return;
    await _run(() async => appState.api.post('/payments/${p['id']}/refund', body: {'reason': reason}));
  }

  @override
  Widget build(BuildContext context) {
    final inv = _inv;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: _error != null
            ? ErrorView(error: _error!, onRetry: _load)
            : inv == null
                ? const Loading()
                : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                    Row(children: [Expanded(child: Text('${inv['invoice_number']}', style: Theme.of(context).textTheme.titleLarge)), StatusChip('${inv['status']}')]),
                    Text('${inv['customer_name']}'),
                    const Divider(),
                    for (final i in (inv['items'] as List).cast<Map<String, dynamic>>())
                      Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [Expanded(child: Text('${i['description_snapshot']} × ${i['quantity']}')), Text(money(i['line_total']))])),
                    const Divider(),
                    _line('Subtotal', money(inv['subtotal'])),
                    _line('Discount', '-${money(inv['discount_total'])}'),
                    _line('Tax', money(inv['tax_total'])),
                    _line('Total', money(inv['total']), bold: true),
                    _line('Paid', money(inv['amount_paid'])),
                    _line('Due', money(inv['amount_due']), bold: true),
                    if ((inv['payments'] as List).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Payments', style: Theme.of(context).textTheme.titleSmall),
                      for (final p in (inv['payments'] as List).cast<Map<String, dynamic>>())
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${money(p['amount'])} · ${'${p['method']}'.toUpperCase()}'),
                          subtitle: Text('${p['status']}'),
                          trailing: p['status'] == 'completed' && inv['status'] != 'void' && appState.can('payment.refund') ? TextButton(onPressed: _busy ? null : () => _refund(p), child: const Text('Refund')) : null,
                        ),
                    ],
                    if (inv['status'] == 'open' && appState.can('payment.create')) ...[
                      const SizedBox(height: 12),
                      Text('Record payment', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [ButtonSegment(value: 'cash', label: Text('Cash')), ButtonSegment(value: 'upi', label: Text('UPI')), ButtonSegment(value: 'card', label: Text('Card'))],
                        selected: {_method},
                        onSelectionChanged: (s) => setState(() => _method = s.first),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Amount', border: const OutlineInputBorder(), suffixIcon: TextButton(onPressed: () => _amount.text = '${inv['amount_due']}', child: const Text('Full'))))),
                        const SizedBox(width: 8),
                        FilledButton(onPressed: _busy ? null : _pay, child: const Text('Pay')),
                      ]),
                    ],
                    if (inv['status'] != 'void' && appState.can('invoice.void') && double.tryParse('${inv['amount_paid']}') == 0) ...[
                      const SizedBox(height: 16),
                      OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), onPressed: _busy ? null : _void, child: const Text('Void invoice')),
                    ],
                  ]),
      ),
    );
  }

  Widget _line(String l, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l, style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null), Text(v, style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null)]),
      );
}
