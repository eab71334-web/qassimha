import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extras3.dart';
import 'main.dart';

// ═════════════════════════ أدوات مشتركة ═════════════════════════

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

List<String> _strs(dynamic v) => [for (final e in (v as List? ?? [])) e.toString()];

double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;

List<Map<String, dynamic>> _maps(dynamic v) => [
      for (final e in (v as List? ?? [])) Map<String, dynamic>.from(e as Map),
    ];

Future<void> shareText(BuildContext context, String text) async {
  try {
    await Share.share(text);
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نسخ النص')),
      );
    }
  }
}

/// رسالة تذكير لطيفة (تُرسل عبر واتساب أو أي تطبيق من قائمة المشاركة).
String remindText(String name, double amount, String what) {
  final w = what.trim().isEmpty ? 'الحساب' : what.trim();
  final pay = gPayInfo.trim().isEmpty ? '' : '\nحوّل لي على: ${gPayInfo.trim()}';
  return 'يا $name 👋 ما تنساش حق $w: ${fmt(amount)} $kCurrency 😄$pay\n$kTagline';
}

Future<String?> askText(BuildContext c, String t, String l) => _askText(c, t, l);

Future<Map<String, dynamic>?> askForm(
  BuildContext context, {
  required String title,
  required String nameLabel,
  required String membersLabel,
  String initialName = '',
}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FormDialog(
        title: title,
        nameLabel: nameLabel,
        membersLabel: membersLabel,
        initialName: initialName,
      ),
    );

Future<bool> _confirm(BuildContext context, String msg) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('تأكيد'),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> _askText(BuildContext context, String title, String label) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            final t = c.text.trim();
            Navigator.pop(context, t.isEmpty ? null : t);
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
}

/// مخزن بسيط لقائمة سجلات JSON في SharedPreferences.
class JsonStore extends ChangeNotifier {
  JsonStore(this.key);
  final String key;
  final List<Map<String, dynamic>> items = [];

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(key);
      if (raw != null) {
        items
          ..clear()
          ..addAll(_maps(jsonDecode(raw)));
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(key, jsonEncode(items));
    } catch (_) {}
  }

  void add(Map<String, dynamic> m) {
    items.insert(0, m);
    _save();
    notifyListeners();
  }

  void removeId(String id) {
    items.removeWhere((e) => e['id'] == id);
    _save();
    notifyListeners();
  }

  /// بعد تعديل أي سجل مباشرة.
  void touch() {
    _save();
    notifyListeners();
  }

  Map<String, dynamic>? byId(String id) {
    for (final e in items) {
      if (e['id'] == id) return e;
    }
    return null;
  }
}

class Transfer {
  Transfer(this.from, this.to, this.amount);
  final String from;
  final String to;
  final double amount;
}

/// تسوية بأقل عدد تحويلات: الرصيد الموجب = له مال، السالب = عليه.
List<Transfer> settleBalances(Map<String, double> bal) {
  final debtors = <MapEntry<String, double>>[];
  final creditors = <MapEntry<String, double>>[];
  bal.forEach((k, v) {
    if (v < -0.005) debtors.add(MapEntry(k, -v));
    if (v > 0.005) creditors.add(MapEntry(k, v));
  });
  debtors.sort((a, b) => b.value.compareTo(a.value));
  creditors.sort((a, b) => b.value.compareTo(a.value));
  final out = <Transfer>[];
  var i = 0, j = 0;
  var d = debtors.isEmpty ? 0.0 : debtors[0].value;
  var c = creditors.isEmpty ? 0.0 : creditors[0].value;
  while (i < debtors.length && j < creditors.length) {
    final m = d < c ? d : c;
    if (m > 0.005) out.add(Transfer(debtors[i].key, creditors[j].key, m));
    d -= m;
    c -= m;
    if (d <= 0.005) {
      i++;
      if (i < debtors.length) d = debtors[i].value;
    }
    if (c <= 0.005) {
      j++;
      if (j < creditors.length) c = creditors[j].value;
    }
  }
  return out;
}

/// نموذج: اسم + (مبلغ اختياري) + أسماء الأشخاص كل واحد في سطر.
class _FormDialog extends StatefulWidget {
  const _FormDialog({
    required this.title,
    required this.nameLabel,
    required this.membersLabel,
    this.amountLabel,
    this.initialName = '',
  });
  final String initialName;
  final String title;
  final String nameLabel;
  final String membersLabel;
  final String? amountLabel;

  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  late final name = TextEditingController(text: widget.initialName);
  final amount = TextEditingController();
  final members = TextEditingController();
  String? error;

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    members.dispose();
    super.dispose();
  }

  void _save() {
    final n = name.text.trim();
    final ms = members.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    double? a;
    if (widget.amountLabel != null) {
      a = parsePrice(amount.text);
      if (a == null || a <= 0) {
        setState(() => error = 'اكتب المبلغ');
        return;
      }
    }
    if (n.isEmpty) {
      setState(() => error = 'اكتب الاسم');
      return;
    }
    if (ms.length < 2) {
      setState(() => error = 'أضف شخصين على الأقل (كل اسم في سطر)');
      return;
    }
    Navigator.pop(context, {'name': n, 'amount': a ?? 0.0, 'members': ms});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: widget.nameLabel),
            ),
            if (widget.amountLabel != null)
              TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: widget.amountLabel),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: members,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: widget.membersLabel,
                alignLabelWithHint: true,
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _save, child: const Text('حفظ')),
      ],
    );
  }
}

// ═════════════════════════ 1) الرحلات والمصاريف الجماعية ═════════════════════════
// الرحلة: {id, name, people: [..], expenses: [{id,title,payer,amount,date,shares:{اسم:مبلغ}}]}

Map<String, double> tripBalances(Map<String, dynamic> trip) {
  final bal = <String, double>{
    for (final p in _strs(trip['people'])) p: 0.0,
  };
  for (final e in _maps(trip['expenses'])) {
    final payer = e['payer'].toString();
    bal[payer] = (bal[payer] ?? 0) + _num(e['amount']);
    final shares = Map<String, dynamic>.from(e['shares'] as Map? ?? {});
    shares.forEach((k, v) => bal[k] = (bal[k] ?? 0) - _num(v));
  }
  return bal;
}

class TripsListPage extends StatefulWidget {
  const TripsListPage({super.key});

  @override
  State<TripsListPage> createState() => _TripsListPageState();
}

class _TripsListPageState extends State<TripsListPage> {
  final store = JsonStore('qassimha_trips_v1');

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  Future<void> _new() async {
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _FormDialog(
        title: 'رحلة جديدة',
        nameLabel: 'اسم الرحلة (مثل: مصيف طرابلس)',
        membersLabel: 'المشاركون (كل اسم في سطر)',
      ),
    );
    if (r == null) return;
    store.add({
      'id': _newId(),
      'name': r['name'],
      'people': r['members'],
      'expenses': <Map<String, dynamic>>[],
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الرحلات والمصاريف')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('رحلة جديدة'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (store.items.isEmpty) {
            return const Center(child: Text('لا توجد رحلات بعد'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
              for (final t in store.items)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.beach_access_outlined),
                    title: Text(t['name'].toString()),
                    subtitle: Text(
                      '${_strs(t['people']).length} أشخاص · '
                      '${fmt(_maps(t['expenses']).fold<double>(0, (s, e) => s + _num(e['amount'])))} $kCurrency',
                    ),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TripDetailPage(
                          store: store,
                          tripId: t['id'].toString(),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class TripDetailPage extends StatelessWidget {
  const TripDetailPage({super.key, required this.store, required this.tripId});
  final JsonStore store;
  final String tripId;

  Future<void> _addExpense(BuildContext context, Map<String, dynamic> t) async {
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ExpenseDialog(people: _strs(t['people'])),
    );
    if (r == null) return;
    (t['expenses'] as List).insert(0, r);
    store.touch();
  }

  Future<void> _addPerson(BuildContext context, Map<String, dynamic> t) async {
    final n = await _askText(context, 'إضافة شخص', 'الاسم');
    if (n == null) return;
    final people = t['people'] as List;
    if (!people.contains(n)) people.add(n);
    store.touch();
  }

  String _summary(Map<String, dynamic> t) {
    final bal = tripBalances(t);
    final tr = settleBalances(bal);
    final total =
        _maps(t['expenses']).fold<double>(0, (s, e) => s + _num(e['amount']));
    return [
      '🏖️ ${t['name']}',
      'إجمالي المصاريف: ${fmt(total)} $kCurrency',
      '',
      if (tr.isEmpty) 'الحساب متساوي ✅',
      for (final x in tr) '• ${x.from} يدفع لـ ${x.to}: ${fmt(x.amount)} $kCurrency',
      '',
      kTagline,
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final t = store.byId(tripId);
        if (t == null) {
          return Scaffold(appBar: AppBar(), body: const SizedBox());
        }
        final cs = Theme.of(context).colorScheme;
        final bal = tripBalances(t);
        final transfers = settleBalances(bal);
        final expenses = _maps(t['expenses']);
        final total = expenses.fold<double>(0, (s, e) => s + _num(e['amount']));
        return Scaffold(
          appBar: AppBar(
            title: Text(t['name'].toString()),
            actions: [
              IconButton(
                tooltip: 'حذف الرحلة',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await _confirm(context, 'حذف الرحلة نهائياً؟')) {
                    store.removeId(tripId);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final p in _strs(t['people'])) Chip(label: Text(p)),
                  ActionChip(
                    avatar: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('شخص'),
                    onPressed: () => _addPerson(context, t),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _addExpense(context, t),
                icon: const Icon(Icons.add),
                label: const Text('إضافة مصروف'),
              ),
              const SizedBox(height: 16),
              Text(
                'التسوية (أقل عدد تحويلات)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (transfers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('لا توجد تحويلات مطلوبة'),
                ),
              for (final x in transfers)
                Card(
                  color: cs.primaryContainer,
                  child: ListTile(
                    title: Text('${x.from} ← ${x.to}'),
                    subtitle: Text('${fmt(x.amount)} $kCurrency'),
                    trailing: IconButton(
                      tooltip: 'تذكير',
                      icon: const Icon(Icons.notifications_active_outlined),
                      onPressed: () => shareText(
                        context,
                        remindText(x.from, x.amount, t['name'].toString()),
                      ),
                    ),
                  ),
                ),
              if (expenses.isNotEmpty)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => shareText(context, _summary(t)),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('شارك التسوية'),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'المصاريف · ${fmt(total)} $kCurrency',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final e in expenses)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${e['title']} · ${fmt(_num(e['amount']))} $kCurrency'),
                  subtitle: Text(
                    'دفع: ${e['payer']} · على ${(e['shares'] as Map).length} أشخاص',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      (t['expenses'] as List)
                          .removeWhere((x) => (x as Map)['id'] == e['id']);
                      store.touch();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// مصروف: يدفعه شخص، ويُقسَّم بالتساوي أو بالنسب أو بمبالغ ثابتة.
class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({required this.people});
  final List<String> people;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final title = TextEditingController();
  final amount = TextEditingController();
  final Map<String, TextEditingController> ctl = {};
  late String payer = widget.people.first;
  late final Set<String> who = {...widget.people};
  int mode = 0; // 0 بالتساوي، 1 نسب %، 2 مبالغ
  String? error;

  TextEditingController _c(String n) =>
      ctl.putIfAbsent(n, () => TextEditingController());

  @override
  void dispose() {
    title.dispose();
    amount.dispose();
    for (final c in ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final a = parsePrice(amount.text);
    if (a == null || a <= 0) {
      setState(() => error = 'اكتب المبلغ');
      return;
    }
    if (who.isEmpty) {
      setState(() => error = 'اختر من يشارك في المصروف');
      return;
    }
    final names = widget.people.where(who.contains).toList();
    final shares = <String, double>{};
    if (mode == 0) {
      final each = (a / names.length * 100).floorToDouble() / 100;
      var used = 0.0;
      for (var i = 0; i < names.length; i++) {
        final v = i == names.length - 1 ? a - used : each;
        shares[names[i]] = v;
        used += v;
      }
    } else {
      var sum = 0.0;
      for (final n in names) {
        final v = parsePrice(_c(n).text) ?? 0;
        shares[n] = mode == 1 ? a * v / 100 : v;
        sum += v;
      }
      final target = mode == 1 ? 100.0 : a;
      if ((sum - target).abs() > 0.01) {
        setState(() => error = mode == 1
            ? 'مجموع النسب ${fmt(sum)}% ويجب أن يكون 100%'
            : 'مجموع المبالغ ${fmt(sum)} ويجب أن يساوي ${fmt(a)}');
        return;
      }
    }
    Navigator.pop(context, {
      'id': _newId(),
      'title': title.text.trim().isEmpty ? 'مصروف' : title.text.trim(),
      'payer': payer,
      'amount': a,
      'date': DateTime.now().toIso8601String(),
      'shares': shares,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('مصروف جديد'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'على ماذا؟ (عشاء، بنزين…)'),
            ),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'المبلغ ($kCurrency)'),
            ),
            const SizedBox(height: 12),
            const Text('مَن دفع؟'),
            Wrap(
              spacing: 6,
              children: [
                for (final p in widget.people)
                  ChoiceChip(
                    label: Text(p),
                    selected: payer == p,
                    onSelected: (_) => setState(() => payer = p),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('مَن يشارك؟'),
            Wrap(
              spacing: 6,
              children: [
                for (final p in widget.people)
                  FilterChip(
                    label: Text(p),
                    selected: who.contains(p),
                    onSelected: (v) => setState(() {
                      if (v) {
                        who.add(p);
                      } else {
                        who.remove(p);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('بالتساوي')),
                ButtonSegment(value: 1, label: Text('نسب %')),
                ButtonSegment(value: 2, label: Text('مبالغ')),
              ],
              selected: {mode},
              onSelectionChanged: (s) => setState(() => mode = s.first),
            ),
            if (mode != 0)
              for (final p in widget.people.where(who.contains))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TextField(
                    controller: _c(p),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: mode == 1 ? 'نسبة $p (%)' : 'حصة $p',
                      isDense: true,
                    ),
                  ),
                ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _save, child: const Text('حفظ')),
      ],
    );
  }
}

// ═════════════════════════ 2) فواتير متكررة ═════════════════════════
// {id, name, amount, members: [..], startY, startM, paid: ["y-m"]}

String _monthKey(DateTime d) => '${d.year}-${d.month}';

class RecurringPage extends StatefulWidget {
  const RecurringPage({super.key});

  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage> {
  final store = JsonStore('qassimha_recurring_v1');

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  Future<void> _new() async {
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _FormDialog(
        title: 'فاتورة متكررة',
        nameLabel: 'الاسم (إيجار، كهرباء…)',
        amountLabel: 'المبلغ الشهري',
        membersLabel: 'الأشخاص بترتيب الدور (كل اسم في سطر)',
      ),
    );
    if (r == null) return;
    final now = DateTime.now();
    store.add({
      'id': _newId(),
      'name': r['name'],
      'amount': r['amount'],
      'members': r['members'],
      'startY': now.year,
      'startM': now.month,
      'paid': <String>[],
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final mk = _monthKey(now);
    return Scaffold(
      appBar: AppBar(title: const Text('فواتير متكررة')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('فاتورة جديدة'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (store.items.isEmpty) {
            return const Center(child: Text('لا توجد فواتير متكررة بعد'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
              for (final r in store.items) _card(context, r, now, mk),
            ],
          );
        },
      ),
    );
  }

  Widget _card(
      BuildContext context, Map<String, dynamic> r, DateTime now, String mk) {
    final members = _strs(r['members']);
    final amount = _num(r['amount']);
    final months =
        (now.year - (r['startY'] as int)) * 12 + now.month - (r['startM'] as int);
    final payerIdx = months < 0 ? 0 : months % members.length;
    final payer = members[payerIdx];
    final next = members[(payerIdx + 1) % members.length];
    final each = amount / members.length;
    final paid = _strs(r['paid']);
    final isPaid = paid.contains(mk);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${r['name']} · ${fmt(amount)} $kCurrency',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await _confirm(context, 'حذف هذه الفاتورة؟')) {
                      store.removeId(r['id'].toString());
                    }
                  },
                ),
              ],
            ),
            Text('دور هذا الشهر: $payer · الشهر القادم: $next'),
            Text('حصة كل واحد: ${fmt(each)} $kCurrency'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: isPaid,
              title: const Text('تم دفعها هذا الشهر'),
              onChanged: (v) {
                if (v == true) {
                  paid.add(mk);
                } else {
                  paid.remove(mk);
                }
                r['paid'] = paid;
                store.touch();
              },
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => shareText(
                  context,
                  '🧾 ${r['name']} هذا الشهر\n'
                  '$payer يدفعها ويجمع من الباقي ${fmt(each)} $kCurrency لكل واحد 😄\n'
                  '$kTagline',
                ),
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('ذكّر المجموعة'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════ 3) صندوق مشترك ═════════════════════════
// {id, name, members: [..], entries: [{id,kind:'in'|'out',who,amount,note,date}]}

class FundListPage extends StatefulWidget {
  const FundListPage({super.key});

  @override
  State<FundListPage> createState() => _FundListPageState();
}

class _FundListPageState extends State<FundListPage> {
  final store = JsonStore('qassimha_funds_v1');

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  double _balance(Map<String, dynamic> f) => _maps(f['entries']).fold<double>(
      0, (s, e) => s + (e['kind'] == 'in' ? _num(e['amount']) : -_num(e['amount'])));

  Future<void> _new() async {
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _FormDialog(
        title: 'صندوق جديد',
        nameLabel: 'اسم الصندوق (مثل: صندوق السفرة)',
        membersLabel: 'الأعضاء (كل اسم في سطر)',
      ),
    );
    if (r == null) return;
    store.add({
      'id': _newId(),
      'name': r['name'],
      'members': r['members'],
      'entries': <Map<String, dynamic>>[],
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الصندوق المشترك')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('صندوق جديد'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (store.items.isEmpty) {
            return const Center(child: Text('لا توجد صناديق بعد'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
              for (final f in store.items)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.savings_outlined),
                    title: Text(f['name'].toString()),
                    subtitle: Text('الرصيد: ${fmt(_balance(f))} $kCurrency'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FundDetailPage(
                          store: store,
                          fundId: f['id'].toString(),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class FundDetailPage extends StatelessWidget {
  const FundDetailPage({super.key, required this.store, required this.fundId});
  final JsonStore store;
  final String fundId;

  Future<void> _entry(
      BuildContext context, Map<String, dynamic> f, bool isIn) async {
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FundEntryDialog(members: _strs(f['members']), isIn: isIn),
    );
    if (r == null) return;
    (f['entries'] as List).insert(0, r);
    store.touch();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final f = store.byId(fundId);
        if (f == null) {
          return Scaffold(appBar: AppBar(), body: const SizedBox());
        }
        final cs = Theme.of(context).colorScheme;
        final entries = _maps(f['entries']);
        var inSum = 0.0, outSum = 0.0;
        final per = <String, double>{
          for (final m in _strs(f['members'])) m: 0.0,
        };
        for (final e in entries) {
          final a = _num(e['amount']);
          if (e['kind'] == 'in') {
            inSum += a;
            per[e['who'].toString()] = (per[e['who'].toString()] ?? 0) + a;
          } else {
            outSum += a;
          }
        }
        final bal = inSum - outSum;
        return Scaffold(
          appBar: AppBar(
            title: Text(f['name'].toString()),
            actions: [
              IconButton(
                tooltip: 'حذف الصندوق',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await _confirm(context, 'حذف الصندوق نهائياً؟')) {
                    store.removeId(fundId);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: cs.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الرصيد الحالي',
                          style: Theme.of(context).textTheme.labelLarge),
                      Text(
                        '${fmt(bal)} $kCurrency',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Text(
                          'إجمالي الإيداع ${fmt(inSum)} · إجمالي الصرف ${fmt(outSum)}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _entry(context, f, true),
                      icon: const Icon(Icons.add),
                      label: const Text('إيداع'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _entry(context, f, false),
                      icon: const Icon(Icons.remove),
                      label: const Text('صرف'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('مساهمة كل عضو',
                  style: Theme.of(context).textTheme.titleMedium),
              for (final e in per.entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.key),
                  trailing: Text('${fmt(e.value)} $kCurrency'),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => shareText(
                    context,
                    [
                      '💰 ${f['name']}',
                      'الرصيد: ${fmt(bal)} $kCurrency',
                      for (final e in per.entries)
                        '• ${e.key}: ${fmt(e.value)} $kCurrency',
                      kTagline,
                    ].join('\n'),
                  ),
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('شارك الرصيد'),
                ),
              ),
              const SizedBox(height: 8),
              Text('الحركات', style: Theme.of(context).textTheme.titleMedium),
              for (final e in entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    e['kind'] == 'in' ? Icons.south_west : Icons.north_east,
                    color: e['kind'] == 'in' ? cs.primary : cs.error,
                  ),
                  title: Text(
                    '${e['kind'] == 'in' ? '+' : '-'}${fmt(_num(e['amount']))} $kCurrency',
                  ),
                  subtitle: Text(
                    '${e['kind'] == 'in' ? e['who'] : (e['note'].toString().isEmpty ? 'صرف' : e['note'])}'
                    ' · ${fmtDate(DateTime.parse(e['date'].toString()))}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      (f['entries'] as List)
                          .removeWhere((x) => (x as Map)['id'] == e['id']);
                      store.touch();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FundEntryDialog extends StatefulWidget {
  const _FundEntryDialog({required this.members, required this.isIn});
  final List<String> members;
  final bool isIn;

  @override
  State<_FundEntryDialog> createState() => _FundEntryDialogState();
}

class _FundEntryDialogState extends State<_FundEntryDialog> {
  final amount = TextEditingController();
  final note = TextEditingController();
  late String who = widget.members.first;
  String? error;

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isIn ? 'إيداع في الصندوق' : 'صرف من الصندوق'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'المبلغ ($kCurrency)'),
            ),
            if (widget.isIn) ...[
              const SizedBox(height: 12),
              const Text('مَن أودع؟'),
              Wrap(
                spacing: 6,
                children: [
                  for (final m in widget.members)
                    ChoiceChip(
                      label: Text(m),
                      selected: who == m,
                      onSelected: (_) => setState(() => who = m),
                    ),
                ],
              ),
            ] else
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'على ماذا صُرف؟'),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            final a = parsePrice(amount.text);
            if (a == null || a <= 0) {
              setState(() => error = 'اكتب المبلغ');
              return;
            }
            Navigator.pop(context, {
              'id': _newId(),
              'kind': widget.isIn ? 'in' : 'out',
              'who': widget.isIn ? who : '',
              'amount': a,
              'note': note.text.trim(),
              'date': DateTime.now().toIso8601String(),
            });
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

// ═════════════════════════ 4) إحصائيات ═════════════════════════

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.bill});
  final Bill bill;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final trips = JsonStore('qassimha_trips_v1');

  @override
  void initState() {
    super.initState();
    trips.load();
  }

  @override
  void dispose() {
    trips.dispose();
    super.dispose();
  }

  Widget _bars(BuildContext context, Map<String, double> data, {int max = 5}) {
    final list = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = list.take(max).toList();
    if (top.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('لا توجد بيانات بعد'),
      );
    }
    final mx = top.first.value <= 0 ? 1.0 : top.first.value;
    return Column(
      children: [
        for (final e in top)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(e.key)),
                    Text('${fmt(e.value)} $kCurrency'),
                  ],
                ),
                const SizedBox(height: 2),
                LinearProgressIndicator(value: e.value / mx),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final byMonth = <String, double>{};
    final places = <String, double>{};
    final friends = <String, double>{}; // مجموع حصص كل شخص
    final payers = <String, double>{}; // مَن دفع أكثر في الرحلات
    var thisMonth = 0.0;
    var all = 0.0;

    void addSpend(DateTime d, double v) {
      all += v;
      if (d.year == now.year && d.month == now.month) thisMonth += v;
      final k = '${d.year}/${d.month.toString().padLeft(2, '0')}';
      byMonth[k] = (byMonth[k] ?? 0) + v;
    }

    for (final b in widget.bill.saved) {
      addSpend(b.date, b.total);
      places[b.title] = (places[b.title] ?? 0) + b.total;
      b.lines.forEach((k, v) => friends[k] = (friends[k] ?? 0) + v);
    }
    for (final t in trips.items) {
      for (final e in _maps(t['expenses'])) {
        final a = _num(e['amount']);
        final d = DateTime.tryParse(e['date'].toString()) ?? now;
        addSpend(d, a);
        final nm = t['name'].toString();
        places[nm] = (places[nm] ?? 0) + a;
        payers[e['payer'].toString()] = (payers[e['payer'].toString()] ?? 0) + a;
        Map<String, dynamic>.from(e['shares'] as Map? ?? {}).forEach(
            (k, v) => friends[k] = (friends[k] ?? 0) + _num(v));
      }
    }
    final recent = Map.fromEntries(
      (byMonth.entries.toList()..sort((a, b) => b.key.compareTo(a.key)))
          .take(6),
    );
    final tt = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(title: const Text('إحصائيات')),
      body: ListenableBuilder(
        listenable: trips,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('صرفتم هذا الشهر'),
                    Text(
                      '${fmt(thisMonth)} $kCurrency',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text('الإجمالي الكلي: ${fmt(all)} $kCurrency'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('حسب الشهر', style: tt),
            _bars(context, recent, max: 6),
            const SizedBox(height: 16),
            Text('أكثر الأماكن والرحلات إنفاقاً', style: tt),
            _bars(context, places),
            const SizedBox(height: 16),
            Text('أكثر حصص الأصدقاء', style: tt),
            _bars(context, friends),
            const SizedBox(height: 16),
            Text('أكثر مَن دفع في الرحلات', style: tt),
            _bars(context, payers),
            const SizedBox(height: 8),
            const Text(
              'الأرقام من الفواتير المحفوظة ومصاريف الرحلات.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
