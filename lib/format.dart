const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _two(int n) => n.toString().padLeft(2, '0');

String ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String dayLabel(DateTime d) => '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

String timeLabel(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${_two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

DateTime parseApiTime(String iso) => DateTime.parse(iso).toLocal();

/// Indian digit grouping, e.g. 1234567.5 -> ₹12,34,567.50
String money(dynamic value) {
  final n = double.tryParse(value?.toString() ?? '') ?? 0;
  final fixed = n.toStringAsFixed(2);
  final parts = fixed.split('.');
  var whole = parts[0];
  final neg = whole.startsWith('-');
  if (neg) whole = whole.substring(1);
  if (whole.length > 3) {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    whole = '${groups.join(',')},$last3';
  }
  return '${neg ? '-' : ''}₹$whole.${parts[1]}';
}

String titleCase(String s) {
  final t = s.replaceAll('_', ' ');
  if (t.isEmpty) return t;
  return t[0].toUpperCase() + t.substring(1);
}
