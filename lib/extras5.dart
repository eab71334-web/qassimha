import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extras2.dart';
import 'extras3.dart';
import 'extras4.dart';
import 'main.dart';

const List<String> _months = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

double _n(dynamic v) => (v as num?)?.toDouble() ?? 0;

List<Map<String, dynamic>> _maps(dynamic v) => [
      for (final e in (v as List? ?? [])) Map<String, dynamic>.from(e as Map),
    ];

// ═════════════════════════ قفل التطبيق (PIN) ═════════════════════════

/// الرمز المحفوظ (مُشفَّر ببصمة بسيطة). null = لا يوجد قفل.
final ValueNotifier<String?> gPinHash = ValueNotifier<String?>(null);

String hashPin(String p) {
  var h = 7;
  for (final c in 'qsm$p'.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h.toString();
}

/// يغلّف الشاشة الرئيسية: إن كان هناك رمز يعرض شاشة القفل عند الفتح،
/// وكذلك بعد غياب التطبيق في الخلفية أكثر من دقيقة.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool loaded = false;
  bool locked = false;
  DateTime? pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    gPinHash.addListener(_onPin);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    gPinHash.removeListener(_onPin);
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      gPinHash.value = sp.getString('qassimha_pin');
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      loaded = true;
      locked = gPinHash.value != null;
    });
  }

  void _onPin() {
    if (gPinHash.value == null && locked && mounted) {
      setState(() => locked = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final p = pausedAt;
      pausedAt = null;
      if (p != null &&
          gPinHash.value != null &&
          DateTime.now().difference(p).inSeconds > 60 &&
          mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        setState(() => locked = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!loaded)
          const Positioned.fill(child: Scaffold(body: SizedBox.expand()))
        else if (locked)
          Positioned.fill(
            child: _LockScreen(onUnlock: () => setState(() => locked = false)),
          ),
      ],
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  String entered = '';
  String? err;

  void _tap(String d) {
    if (entered.length >= 4) return;
    setState(() {
      entered += d;
      err = null;
    });
    if (entered.length == 4) {
      if (hashPin(entered) == gPinHash.value) {
        widget.onUnlock();
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          entered = '';
          err = 'رمز خاطئ';
        });
      }
    }
  }

  Widget _key(String label, {VoidCallback? onTap, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: 72,
        height: 72,
        child: onTap == null
            ? const SizedBox()
            : FilledButton.tonal(
                style: FilledButton.styleFrom(shape: const CircleBorder()),
                onPressed: onTap,
                child: icon != null
                    ? Icon(icon)
                    : Text(label, style: const TextStyle(fontSize: 22)),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              const Text('أدخل رمز القفل'),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      margin: const EdgeInsets.all(6),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < entered.length
                            ? cs.primary
                            : cs.outlineVariant,
                      ),
                    ),
                ],
              ),
              SizedBox(
                height: 28,
                child: Text(err ?? '', style: TextStyle(color: cs.error)),
              ),
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final d in row) _key(d, onTap: () => _tap(d)),
                  ],
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _key(''),
                  _key('0', onTap: () => _tap('0')),
                  _key(
                    '',
                    icon: Icons.backspace_outlined,
                    onTap: () {
                      if (entered.isNotEmpty) {
                        setState(() =>
                            entered = entered.substring(0, entered.length - 1));
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PinSettingsPage extends StatefulWidget {
  const PinSettingsPage({super.key});

  @override
  State<PinSettingsPage> createState() => _PinSettingsPageState();
}

class _PinSettingsPageState extends State<PinSettingsPage> {
  final a = TextEditingController();
  final b = TextEditingController();

  @override
  void dispose() {
    a.dispose();
    b.dispose();
    super.dispose();
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _set() async {
    final p = a.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(p)) {
      _snack('الرمز 4 أرقام');
      return;
    }
    if (p != b.text.trim()) {
      _snack('الرمزان غير متطابقين');
      return;
    }
    final h = hashPin(p);
    final sp = await SharedPreferences.getInstance();
    await sp.setString('qassimha_pin', h);
    gPinHash.value = h;
    a.clear();
    b.clear();
    _snack('تم تفعيل القفل');
  }

  Future<void> _remove() async {
    if (hashPin(a.text.trim()) != gPinHash.value) {
      _snack('الرمز الحالي خاطئ');
      return;
    }
    final sp = await SharedPreferences.getInstance();
    await sp.remove('qassimha_pin');
    gPinHash.value = null;
    a.clear();
    _snack('تم إلغاء القفل');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('قفل التطبيق')),
      body: ValueListenableBuilder<String?>(
        valueListenable: gPinHash,
        builder: (context, pin, _) {
          final has = pin != null;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(has ? 'القفل مفعّل ✅' : 'القفل غير مفعّل'),
              const SizedBox(height: 8),
              TextField(
                controller: a,
                obscureText: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: has ? 'الرمز الحالي' : 'رمز جديد (4 أرقام)',
                ),
              ),
              if (!has)
                TextField(
                  controller: b,
                  obscureText: true,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'أعد كتابة الرمز'),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: has
                    ? OutlinedButton(
                        onPressed: _remove,
                        child: const Text('إلغاء القفل'),
                      )
                    : FilledButton(
                        onPressed: _set,
                        child: const Text('تفعيل'),
                      ),
              ),
              const SizedBox(height: 16),
              const Text(
                'يُطلب الرمز عند فتح التطبيق وبعد غيابه دقيقة في الخلفية. '
                'إن نسيته فلن يمكن فتح التطبيق إلا بحذفه وإعادة تثبيته، فاحتفظ بنسخة احتياطية.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═════════════════════════ سلة المحذوفات ═════════════════════════

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<Map<String, dynamic>> items = [];
  bool loaded = false;

  static const kinds = {
    'qassimha_debts_v1': 'دين',
    'qassimha_trips_v1': 'رحلة',
    'qassimha_funds_v1': 'صندوق',
    'qassimha_recurring_v1': 'فاتورة متكررة',
    'qassimha_groups_v1': 'مجموعة',
    'qassimha_receipts_v1': 'إيصال',
    'qassimha_installments_v1': 'أقساط',
    'qassimha_jamiya_v1': 'جمعية',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var list = <Map<String, dynamic>>[];
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(kTrashKey);
      if (raw != null) list = _maps(jsonDecode(raw));
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      list.removeWhere((e) {
        final d = DateTime.tryParse(e['at'].toString());
        return d == null || d.isBefore(cutoff);
      });
      await sp.setString(kTrashKey, jsonEncode(list));
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      items = list;
      loaded = true;
    });
  }

  Future<void> _restore(Map<String, dynamic> e) async {
    await restoreToPrefs(
      e['store'].toString(),
      Map<String, dynamic>.from(e['item'] as Map),
    );
    await trashRemove(e['id'].toString());
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تمت الاستعادة')),
    );
  }

  Future<void> _drop(Map<String, dynamic> e) async {
    await trashRemove(e['id'].toString());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سلة المحذوفات'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () async {
                final sp = await SharedPreferences.getInstance();
                await sp.remove(kTrashKey);
                await _load();
              },
              child: const Text('إفراغ'),
            ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('السلة فارغة'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'تُحفظ العناصر المحذوفة 30 يوماً ثم تُمسح. بعد الاستعادة افتح الصفحة الأصلية من جديد.',
                      style: TextStyle(fontSize: 12),
                    ),
                    for (final e in items)
                      Card(
                        child: ListTile(
                          title: Text(e['label'].toString()),
                          subtitle: Text(
                            '${kinds[e['store']] ?? 'عنصر'} · حُذف ${fmtDate(DateTime.tryParse(e['at'].toString()) ?? DateTime.now())}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'استعادة',
                                icon: const Icon(Icons.restore),
                                onPressed: () => _restore(e),
                              ),
                              IconButton(
                                tooltip: 'حذف نهائي',
                                icon: const Icon(Icons.delete_forever_outlined),
                                onPressed: () => _drop(e),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

// ═════════════════════════ البحث ═════════════════════════

class _Hit {
  _Hit(this.kind, this.icon, this.title, this.sub);
  final String kind;
  final IconData icon;
  final String title;
  final String sub;
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.bill});
  final Bill bill;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final q = TextEditingController();
  AppData? data;
  String kind = 'all';

  @override
  void initState() {
    super.initState();
    loadAppData().then((d) {
      if (mounted) setState(() => data = d);
    });
  }

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  List<_Hit> _search() {
    final s = q.text.trim().toLowerCase();
    final d = data;
    if (s.isEmpty || d == null) return [];
    bool has(Iterable<String> xs) => xs.any((x) => x.toLowerCase().contains(s));
    String money(double v) => fmt(v);
    final out = <_Hit>[];
    if (kind == 'all' || kind == 'bill') {
      for (final b in widget.bill.saved) {
        if (has([
          b.title,
          ...b.lines.keys,
          money(b.total),
          fmtDate(b.date),
          ...b.lines.values.map(money),
        ])) {
          out.add(_Hit('bill', Icons.receipt_long_outlined, b.title,
              '${fmtDate(b.date)} · ${money(b.total)} $kCurrency · ${b.lines.keys.join('، ')}'));
        }
      }
    }
    if (kind == 'all' || kind == 'debt') {
      for (final e in d.debts) {
        if (has([
          e.debtor,
          e.creditor,
          e.note,
          money(e.amount),
          fmtDate(e.date),
        ])) {
          out.add(_Hit(
            'debt',
            Icons.swap_horiz,
            '${e.debtor} ← ${e.creditor}',
            '${money(e.remaining)} $kCurrency${e.settled ? ' · مسدّد' : ''}'
                '${e.note.isEmpty ? '' : ' · ${e.note}'} · ${fmtDate(e.date)}',
          ));
        }
      }
    }
    if (kind == 'all' || kind == 'trip') {
      for (final t in d.trips) {
        final ex = _maps(t['expenses']);
        final people = [for (final p in (t['people'] as List? ?? [])) p.toString()];
        if (has([
          t['name'].toString(),
          ...people,
          for (final e in ex) ...[
            e['title'].toString(),
            e['payer'].toString(),
            money(_n(e['amount'])),
          ],
        ])) {
          out.add(_Hit('trip', Icons.beach_access_outlined, t['name'].toString(),
              '${ex.length} مصروف · ${people.join('، ')}'));
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final hits = _search();
    return Scaffold(
      appBar: AppBar(title: const Text('بحث')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: q,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'اسم، مبلغ، تاريخ، ملاحظة…',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final k in const [
                ['all', 'الكل'],
                ['bill', 'فواتير'],
                ['debt', 'ديون'],
                ['trip', 'رحلات'],
              ])
                ChoiceChip(
                  label: Text(k[1]),
                  selected: kind == k[0],
                  onSelected: (_) => setState(() => kind = k[0]),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (data == null)
            const Center(child: CircularProgressIndicator())
          else if (q.text.trim().isEmpty)
            const Text('اكتب للبحث في الفواتير والديون والرحلات')
          else if (hits.isEmpty)
            const Text('لا توجد نتائج'),
          for (final h in hits)
            Card(
              child: ListTile(
                leading: Icon(h.icon),
                title: Text(h.title),
                subtitle: Text(h.sub),
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════ تقرير شهري ═════════════════════════

class ReportPage extends StatefulWidget {
  const ReportPage({super.key, required this.bill});
  final Bill bill;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  AppData? data;
  late DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    loadAppData().then((d) {
      if (mounted) setState(() => data = d);
    });
  }

  String _text(AppData d) {
    bool same(DateTime x) => x.year == month.year && x.month == month.month;
    var total = 0.0;
    var count = 0;
    final places = <String, double>{};
    final cats = <String, double>{};
    for (final b in widget.bill.saved) {
      if (!same(b.date)) continue;
      total += b.total;
      count++;
      places[b.title] = (places[b.title] ?? 0) + b.total;
    }
    for (final t in d.trips) {
      for (final e in _maps(t['expenses'])) {
        final dt = DateTime.tryParse(e['date'].toString());
        if (dt == null || !same(dt)) continue;
        final a = _n(e['amount']);
        total += a;
        count++;
        places[t['name'].toString()] = (places[t['name'].toString()] ?? 0) + a;
        final c = (e['cat'] ?? 'أخرى').toString();
        cats[c] = (cats[c] ?? 0) + a;
      }
    }
    String top(Map<String, double> m) =>
        (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
    // أرصدة مفتوحة: صافي كل زوج
    final net = <String, double>{};
    for (final e in d.debts) {
      if (e.settled) continue;
      final pair = [e.debtor, e.creditor]..sort();
      final key = '${pair[0]}\u0000${pair[1]}';
      net[key] =
          (net[key] ?? 0) + (e.debtor == pair[0] ? e.remaining : -e.remaining);
    }
    final owes = <String>[];
    net.forEach((k, v) {
      if (v.abs() < 0.005) return;
      final p = k.split('\u0000');
      final from = v > 0 ? p[0] : p[1];
      final to = v > 0 ? p[1] : p[0];
      owes.add('• $from يدفع لـ $to: ${fmt(v.abs())} $kCurrency');
    });
    return [
      '📅 تقرير ${_months[month.month - 1]} ${month.year}',
      'الإجمالي: ${fmt(total)} $kCurrency ($count عملية)',
      if (places.isNotEmpty) 'الأكثر إنفاقاً: ${top(places)}',
      if (cats.isNotEmpty) 'أكثر فئة: ${top(cats)}',
      if (owes.isNotEmpty) ...['', 'الأرصدة المفتوحة:', ...owes],
      kTagline,
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Scaffold(
      appBar: AppBar(title: const Text('تقرير شهري')),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => setState(
                          () => month = DateTime(month.year, month.month - 1)),
                    ),
                    Text(
                      '${_months[month.month - 1]} ${month.year}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => setState(
                          () => month = DateTime(month.year, month.month + 1)),
                    ),
                  ],
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_text(d)),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => shareText(context, _text(d)),
                  icon: const Icon(Icons.share),
                  label: const Text('شارك التقرير'),
                ),
              ],
            ),
    );
  }
}

// ═════════════════════════ الأقساط ═════════════════════════
// {id, name, total, months, startY, startM, mine: bool, paid: [i]}
// mine = true: أقساط عليّ أدفعها، false: أقساط لي يدفعها غيري

class InstallmentsPage extends StatefulWidget {
  const InstallmentsPage({super.key});

  @override
  State<InstallmentsPage> createState() => _InstallmentsPageState();
}

class _InstallmentsPageState extends State<InstallmentsPage> {
  final store = JsonStore('qassimha_installments_v1');

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
      builder: (_) => const _InstDialog(),
    );
    if (r == null) return;
    final first = DateTime(DateTime.now().year, DateTime.now().month + 1);
    store.add({
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'name': r['name'],
      'total': r['total'],
      'months': r['months'],
      'mine': r['mine'],
      'startY': first.year,
      'startM': first.month,
      'paid': <int>[],
    });
  }

  double _each(Map<String, dynamic> p, int i) {
    final months = p['months'] as int;
    final total = _n(p['total']);
    final base = (total / months * 100).floorToDouble() / 100;
    return i == months - 1 ? total - base * (months - 1) : base;
  }

  String _label(Map<String, dynamic> p, int i) {
    final d = DateTime(p['startY'] as int, (p['startM'] as int) + i);
    return '${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأقساط')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('قسط جديد'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (store.items.isEmpty) {
            return const Center(child: Text('لا توجد أقساط بعد'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [for (final p in store.items) _card(context, p)],
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, Map<String, dynamic> p) {
    final months = p['months'] as int;
    final paid = [for (final x in (p['paid'] as List? ?? [])) x as int];
    final mine = p['mine'] == true;
    var left = 0.0;
    int? next;
    for (var i = 0; i < months; i++) {
      if (!paid.contains(i)) {
        left += _each(p, i);
        next ??= i;
      }
    }
    final nx = next;
    return Card(
      child: ExpansionTile(
        leading: Icon(mine ? Icons.north_east : Icons.south_west),
        title: Text('${p['name']}'),
        subtitle: Text(
          '${mine ? 'عليّ' : 'لي'} · مدفوع ${paid.length}/$months · المتبقي ${fmt(left)} $kCurrency',
        ),
        children: [
          for (var i = 0; i < months; i++)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: paid.contains(i),
              title: Text('${_label(p, i)} · ${fmt(_each(p, i))} $kCurrency'),
              onChanged: (v) {
                if (v == true) {
                  paid.add(i);
                } else {
                  paid.remove(i);
                }
                p['paid'] = paid;
                store.touch();
              },
            ),
          Row(
            children: [
              if (nx != null)
                TextButton.icon(
                  onPressed: () => shareText(
                    context,
                    mine
                        ? '🧾 قسط ${p['name']} لشهر ${_label(p, nx)}: ${fmt(_each(p, nx))} $kCurrency\n$kTagline'
                        : 'ما تنساش قسط ${p['name']} لشهر ${_label(p, nx)}: ${fmt(_each(p, nx))} $kCurrency 😄\n$kTagline',
                  ),
                  icon: const Icon(Icons.notifications_active_outlined, size: 18),
                  label: const Text('تذكير'),
                ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => store.removeId(p['id'].toString()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InstDialog extends StatefulWidget {
  const _InstDialog();

  @override
  State<_InstDialog> createState() => _InstDialogState();
}

class _InstDialogState extends State<_InstDialog> {
  final name = TextEditingController();
  final total = TextEditingController();
  final months = TextEditingController(text: '6');
  bool mine = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    total.dispose();
    months.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('قسط جديد'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('أقساط لي')),
                ButtonSegment(value: true, label: Text('أقساط عليّ')),
              ],
              selected: {mine},
              onSelectionChanged: (s) => setState(() => mine = s.first),
            ),
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: mine ? 'لمن أدفع / ما السلعة؟' : 'مَن يدفع لي / ما السلعة؟',
              ),
            ),
            TextField(
              controller: total,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'المبلغ الكلي ($kCurrency)'),
            ),
            TextField(
              controller: months,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'عدد الأشهر'),
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
            final t = parsePrice(total.text);
            final m = int.tryParse(months.text.trim());
            if (name.text.trim().isEmpty || t == null || t <= 0 || m == null || m < 1 || m > 60) {
              setState(() => error = 'تأكد من الاسم والمبلغ وعدد الأشهر (1-60)');
              return;
            }
            Navigator.pop(context, {
              'name': name.text.trim(),
              'total': t,
              'months': m,
              'mine': mine,
            });
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

// ═════════════════════════ تنبيهات ورصيدي (أعلى صفحة «المزيد») ═════════════════════════

class AlertsCard extends StatelessWidget {
  const AlertsCard({super.key, required this.bill});
  final Bill bill;

  Future<List<String>> _compute() async {
    final out = <String>[];
    final d = await loadAppData();
    final now = DateTime.now();
    final soon = now.add(const Duration(days: 1));

    // رصيدي (يحتاج اسمك في الملف الشخصي)
    final me = gMyName.trim();
    if (me.isNotEmpty) {
      var toMe = 0.0, fromMe = 0.0;
      for (final e in d.debts) {
        if (e.settled) continue;
        if (e.creditor == me) toMe += e.remaining;
        if (e.debtor == me) fromMe += e.remaining;
      }
      if (toMe > 0 || fromMe > 0) {
        out.add('💰 رصيدك: لك ${fmt(toMe)} · عليك ${fmt(fromMe)} $kCurrency');
      }
    }

    final lateCount = d.debts
        .where((e) =>
            !e.settled && e.promise != null && e.promise!.isBefore(soon))
        .length;
    if (lateCount > 0) out.add('⏰ $lateCount دين تجاوز وعد السداد أو يستحق قريباً');

    try {
      final sp = await SharedPreferences.getInstance();
      final mk = '${now.year}-${now.month}';
      final rec = sp.getString('qassimha_recurring_v1');
      if (rec != null) {
        final names = <String>[];
        for (final r in _maps(jsonDecode(rec))) {
          final paid = [for (final x in (r['paid'] as List? ?? [])) x.toString()];
          if (!paid.contains(mk)) names.add(r['name'].toString());
        }
        if (names.isNotEmpty) {
          out.add('🧾 فواتير هذا الشهر غير المدفوعة: ${names.join('، ')}');
        }
      }
      final ins = sp.getString('qassimha_installments_v1');
      if (ins != null) {
        for (final p in _maps(jsonDecode(ins))) {
          final months = p['months'] as int;
          final paid = [for (final x in (p['paid'] as List? ?? [])) x as int];
          for (var i = 0; i < months; i++) {
            if (paid.contains(i)) continue;
            final due = DateTime(p['startY'] as int, (p['startM'] as int) + i);
            if (!DateTime(now.year, now.month).isBefore(due)) {
              out.add(
                  '📆 قسط ${p['name']} لشهر ${_months[due.month - 1]} مستحق');
            }
            break;
          }
        }
      }
      final hasData =
          d.debts.isNotEmpty || d.trips.isNotEmpty || bill.saved.isNotEmpty;
      final lb = DateTime.tryParse(sp.getString('qassimha_last_backup') ?? '');
      if (hasData && (lb == null || now.difference(lb).inDays > 14)) {
        out.add('💾 لم تأخذ نسخة احتياطية منذ مدة: الإعدادات ← نسخ احتياطي');
      }
    } catch (_) {}
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _compute(),
      builder: (context, snap) {
        final lines = snap.data ?? const <String>[];
        if (lines.isEmpty) return const SizedBox.shrink();
        return Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تنبيهات', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(l),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
