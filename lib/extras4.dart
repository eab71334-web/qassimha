import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extras.dart';
import 'extras2.dart';
import 'main.dart';

// ═════════════════════════ بيانات مشتركة بين الصفحات ═════════════════════════

class AppData {
  AppData(this.debts, this.trips);
  final List<DebtEntry> debts;
  final List<Map<String, dynamic>> trips;
}

Future<AppData> loadAppData() async {
  final debts = <DebtEntry>[];
  final trips = <Map<String, dynamic>>[];
  try {
    final sp = await SharedPreferences.getInstance();
    final d = sp.getString('qassimha_debts_v1');
    if (d != null) {
      for (final e in (jsonDecode(d) as List)) {
        try {
          debts.add(DebtEntry.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (_) {}
      }
    }
    final t = sp.getString('qassimha_trips_v1');
    if (t != null) {
      for (final e in (jsonDecode(t) as List)) {
        trips.add(Map<String, dynamic>.from(e as Map));
      }
    }
  } catch (_) {}
  return AppData(debts, trips);
}

double _n(dynamic v) => (v as num?)?.toDouble() ?? 0;

List<Map<String, dynamic>> _expensesOf(Map<String, dynamic> trip) => [
      for (final e in (trip['expenses'] as List? ?? []))
        Map<String, dynamic>.from(e as Map),
    ];

List<String> _peopleOf(Map<String, dynamic> trip) =>
    [for (final p in (trip['people'] as List? ?? [])) p.toString()];

// ═════════════════════════ 1) سجل كل صديق ═════════════════════════

class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key, required this.bill});
  final Bill bill;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل الأصدقاء')),
      body: FutureBuilder<AppData>(
        future: loadAppData(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          final names = <String>{
            for (final p in bill.people) p.name,
            for (final d in data.debts) ...[d.debtor, d.creditor],
            for (final t in data.trips) ..._peopleOf(t),
            for (final b in bill.saved) ...b.lines.keys,
          }.toList()
            ..sort();
          if (names.isEmpty) {
            return const Center(child: Text('لا يوجد أصدقاء بعد'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final n in names)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(n.characters.first)),
                    title: Text(n),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            FriendDetailPage(name: n, data: data, bill: bill),
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

class FriendDetailPage extends StatelessWidget {
  const FriendDetailPage({
    super.key,
    required this.name,
    required this.data,
    required this.bill,
  });
  final String name;
  final AppData data;
  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme.titleMedium;
    final cs = Theme.of(context).colorScheme;
    final debts = data.debts
        .where((d) => !d.settled && (d.debtor == name || d.creditor == name))
        .toList();
    final trips = data.trips.where((t) => _peopleOf(t).contains(name)).toList();
    final bills = bill.saved.where((b) => b.lines.containsKey(name)).toList();
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('الديون المفتوحة', style: tt),
          if (debts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('لا توجد ديون مفتوحة ✅'),
            ),
          for (final d in debts)
            Builder(builder: (context) {
              final days = now.difference(d.date).inDays;
              final isLate = days >= 3;
              final owes = d.debtor == name;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  owes ? Icons.arrow_upward : Icons.arrow_downward,
                  color: owes ? cs.error : cs.primary,
                ),
                title: Text(
                  owes
                      ? 'عليه لـ ${d.creditor}: ${fmt(d.remaining)} $kCurrency'
                      : 'له عند ${d.debtor}: ${fmt(d.remaining)} $kCurrency',
                ),
                subtitle: Text(
                  '${d.note.isEmpty ? 'دين' : d.note} · منذ $days يوم'
                  '${isLate ? ' ⏰ متأخر' : ''}',
                ),
                trailing: owes && isLate
                    ? IconButton(
                        tooltip: 'تذكير',
                        icon: const Icon(Icons.notifications_active_outlined),
                        onPressed: () => shareText(
                          context,
                          remindText(name, d.remaining, d.note),
                        ),
                      )
                    : null,
              );
            }),
          const SizedBox(height: 16),
          Text('الرحلات', style: tt),
          if (trips.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('لم يشارك في رحلات'),
            ),
          for (final t in trips)
            Builder(builder: (context) {
              final b = tripBalances(t)[name] ?? 0;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.beach_access_outlined),
                title: Text(t['name'].toString()),
                subtitle: Text(
                  b > 0.005
                      ? 'له ${fmt(b)} $kCurrency'
                      : b < -0.005
                          ? 'عليه ${fmt(-b)} $kCurrency'
                          : 'متساوي ✅',
                ),
              );
            }),
          const SizedBox(height: 16),
          Text('الفواتير المحفوظة', style: tt),
          if (bills.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('لا توجد فواتير محفوظة له'),
            ),
          for (final b in bills)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(b.title),
              subtitle: Text(fmtDate(b.date)),
              trailing: Text('${fmt(b.lines[name]!)} $kCurrency'),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════ 2) عدّاد المرات والألقاب ═════════════════════════

class LeaderboardPage extends StatelessWidget {
  const LeaderboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مَن يدفع أكثر؟')),
      body: FutureBuilder<AppData>(
        future: loadAppData(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          final paid = <String, int>{};
          final took = <String, int>{};
          void inc(Map<String, int> m, String k) => m[k] = (m[k] ?? 0) + 1;
          for (final t in data.trips) {
            for (final e in _expensesOf(t)) {
              inc(paid, e['payer'].toString());
              for (final k in Map<String, dynamic>.from(e['shares'] as Map? ?? {}).keys) {
                inc(took, k);
              }
            }
          }
          for (final d in data.debts) {
            inc(paid, d.creditor);
            inc(took, d.debtor);
          }
          final names = {...paid.keys, ...took.keys}.toList()
            ..sort((a, b) => (paid[b] ?? 0).compareTo(paid[a] ?? 0));
          if (names.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'سجّل مصاريف في الرحلات أو ديوناً لتظهر الألقاب هنا.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          String? king = (paid[names.first] ?? 0) > 0 ? names.first : null;
          String? dodger;
          var worst = 2.0;
          for (final n in names) {
            final tk = took[n] ?? 0;
            if (tk < 2 || n == king) continue;
            final ratio = (paid[n] ?? 0) / tk;
            if (ratio < worst && ratio < 1) {
              worst = ratio;
              dodger = n;
            }
          }
          String? titleOf(String n) => n == king
              ? '👑 كريم الشلة'
              : n == dodger
                  ? '🏃 المتهرّب'
                  : null;
          final text = [
            '🏆 ترتيب الشلة',
            if (king != null) '👑 كريم الشلة: $king',
            if (dodger != null) '🏃 المتهرّب: $dodger',
            kTagline,
          ].join('\n');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final n in names)
                Card(
                  child: ListTile(
                    title: Text(n),
                    subtitle: Text(
                      'دفع ${paid[n] ?? 0} مرة · شارك في ${took[n] ?? 0}',
                    ),
                    trailing: titleOf(n) == null ? null : Text(titleOf(n)!),
                  ),
                ),
              if (king != null || dodger != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => shareText(context, text),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('شارك الألقاب'),
                  ),
                ),
              const Text(
                'الأرقام من مصاريف الرحلات والديون المسجّلة.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═════════════════════════ 3) ميزانية شهرية ═════════════════════════

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key, required this.bill});
  final Bill bill;

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  final cap = TextEditingController();
  double spent = 0;
  double limit = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    cap.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final sp = await SharedPreferences.getInstance();
    final data = await loadAppData();
    final now = DateTime.now();
    bool same(DateTime d) => d.year == now.year && d.month == now.month;
    var s = 0.0;
    for (final b in widget.bill.saved) {
      if (same(b.date)) s += b.total;
    }
    for (final t in data.trips) {
      for (final e in _expensesOf(t)) {
        final d = DateTime.tryParse(e['date'].toString());
        if (d != null && same(d)) s += _n(e['amount']);
      }
    }
    if (!mounted) return;
    setState(() {
      spent = s;
      limit = sp.getDouble('qassimha_budget') ?? 0;
      if (limit > 0) cap.text = fmt(limit);
    });
  }

  Future<void> _save() async {
    final v = parsePrice(cap.text) ?? 0;
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble('qassimha_budget', v);
    setState(() => limit = v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = limit <= 0 ? 0.0 : spent / limit;
    final color = ratio >= 1
        ? cs.error
        : ratio >= 0.8
            ? Colors.orange
            : cs.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('الميزانية الشهرية')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: cap,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'سقف الصرف الشهري ($kCurrency)'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(onPressed: _save, child: const Text('حفظ')),
          ),
          const SizedBox(height: 24),
          Text(
            'صرفتم هذا الشهر: ${fmt(spent)} $kCurrency',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (limit > 0) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: math.min(1.0, math.max(0.0, ratio)),
              minHeight: 10,
              color: color,
            ),
            const SizedBox(height: 8),
            Text(
              ratio >= 1
                  ? '⚠️ تجاوزتم السقف بـ ${fmt(spent - limit)} $kCurrency'
                  : ratio >= 0.8
                      ? '⚠️ اقتربتم من السقف، باقي ${fmt(limit - spent)} $kCurrency'
                      : 'باقي ${fmt(limit - spent)} $kCurrency ✅',
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('حدّد سقفاً لتتابع صرفك.'),
            ),
          const SizedBox(height: 16),
          const Text(
            'يحسب من الفواتير المحفوظة ومصاريف الرحلات.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════ 4) صور الإيصالات ═════════════════════════

class ReceiptsPage extends StatefulWidget {
  const ReceiptsPage({super.key});

  @override
  State<ReceiptsPage> createState() => _ReceiptsPageState();
}

class _ReceiptsPageState extends State<ReceiptsPage> {
  final store = JsonStore('qassimha_receipts_v1');
  String dir = '';

  @override
  void initState() {
    super.initState();
    store.load();
    getApplicationDocumentsDirectory().then((d) {
      if (mounted) setState(() => dir = d.path);
    });
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  Future<void> _add(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(source: src, maxWidth: 1600);
      if (x == null || !mounted) return;
      final title = await askText(context, 'عنوان الإيصال', 'مثل: عشاء مطعم…');
      if (title == null) return;
      final d = await getApplicationDocumentsDirectory();
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final name = 'receipt_$id.jpg';
      await File(x.path).copy('${d.path}/$name');
      store.add({
        'id': id,
        'title': title,
        'file': name,
        'date': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر حفظ الصورة')),
        );
      }
    }
  }

  void _sheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('التقاط صورة'),
              onTap: () {
                Navigator.pop(context);
                _add(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('من المعرض'),
              onTap: () {
                Navigator.pop(context);
                _add(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _view(Map<String, dynamic> r) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                child: Image.file(File('$dir/${r['file']}')),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(r['title'].toString()),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('صور الإيصالات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sheet,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('إضافة إيصال'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (store.items.isEmpty) {
            return const Center(child: Text('لا توجد إيصالات محفوظة'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
              for (final r in store.items)
                Card(
                  child: ListTile(
                    leading: dir.isEmpty
                        ? const Icon(Icons.image_outlined)
                        : SizedBox(
                            width: 48,
                            height: 48,
                            child: Image.file(
                              File('$dir/${r['file']}'),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                    title: Text(r['title'].toString()),
                    subtitle: Text(
                        fmtDate(DateTime.parse(r['date'].toString()))),
                    onTap: dir.isEmpty ? null : () => _view(r),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        store.removeId(r['id'].toString());
                      },
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

// ═════════════════════════ 5) تصدير (CSV يفتح في Excel) ═════════════════════════

String _csv(List<List<String>> rows) {
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  return '﻿${rows.map((r) => r.map(q).join(',')).join('\n')}';
}

class ExportPage extends StatefulWidget {
  const ExportPage({super.key, required this.bill});
  final Bill bill;

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  Future<void> _send(String fileName, String content) async {
    try {
      final d = await getTemporaryDirectory();
      final f = File('${d.path}/$fileName');
      await f.writeAsString(content);
      await Share.shareXFiles([XFile(f.path)]);
    } catch (_) {
      if (mounted) await shareText(context, content);
    }
  }

  void _bills() {
    final rows = <List<String>>[
      ['التاريخ', 'العنوان', 'الشخص', 'المبلغ'],
      for (final b in widget.bill.saved)
        for (final e in b.lines.entries)
          [fmtDate(b.date), b.title, e.key, fmt(e.value)],
    ];
    _send('qassimha_bills.csv', _csv(rows));
  }

  void _trip(Map<String, dynamic> t) {
    final rows = <List<String>>[
      ['التاريخ', 'المصروف', 'دفعه', 'المبلغ', 'الشخص', 'حصته'],
      for (final e in _expensesOf(t))
        for (final s
            in Map<String, dynamic>.from(e['shares'] as Map? ?? {}).entries)
          [
            fmtDate(DateTime.tryParse(e['date'].toString()) ?? DateTime.now()),
            e['title'].toString(),
            e['payer'].toString(),
            fmt(_n(e['amount'])),
            s.key,
            fmt(_n(s.value)),
          ],
      [],
      ['التسوية'],
      for (final x in settleBalances(tripBalances(t)))
        [x.from, 'يدفع لـ', x.to, fmt(x.amount)],
    ];
    _send('qassimha_trip.csv', _csv(rows));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تصدير كشف حساب')),
      body: FutureBuilder<AppData>(
        future: loadAppData(),
        builder: (context, snap) {
          final trips = snap.data?.trips ?? [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('ملف CSV يفتح في Excel وGoogle Sheets.'),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('الفواتير المحفوظة'),
                  subtitle: Text('${widget.bill.saved.length} فاتورة'),
                  trailing: const Icon(Icons.ios_share),
                  onTap: widget.bill.saved.isEmpty ? null : _bills,
                ),
              ),
              for (final t in trips)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.beach_access_outlined),
                    title: Text(t['name'].toString()),
                    subtitle: Text('${_expensesOf(t).length} مصروف'),
                    trailing: const Icon(Icons.ios_share),
                    onTap: () => _trip(t),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ═════════════════════════ 6) شاشة الترحيب ═════════════════════════

Future<void> maybeShowWelcome(BuildContext context) async {
  try {
    final sp = await SharedPreferences.getInstance();
    if (sp.getBool('qassimha_welcome_seen') ?? false) return;
    await sp.setBool('qassimha_welcome_seen', true);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WelcomePage()),
    );
  } catch (_) {}
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final ctrl = PageController();
  int page = 0;

  static const slides = [
    (Icons.document_scanner_outlined, 'امسح فاتورتك',
        'صوّر الفاتورة وتُقرأ البنود والأسعار تلقائياً، أو أضفها بنفسك.'),
    (Icons.balance_outlined, 'قسّم بالعدل وشارك',
        'حدّد مَن أكل ماذا، واحصل على حصة كل شخص كصورة أو رسالة جاهزة.'),
    (Icons.apps_rounded, 'وأكثر من ذلك',
        'من زر «المزيد»: الديون، الرحلات، الجمعية، الصندوق المشترك والإحصائيات.'),
  ];

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = page == slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('تخطي'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: ctrl,
                onPageChanged: (i) => setState(() => page = i),
                children: [
                  for (final s in slides)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(s.$1,
                              size: 96,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 24),
                          Text(
                            s.$2,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          Text(s.$3, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < slides.length; i++)
                  Container(
                    margin: const EdgeInsets.all(4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == page
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (last) {
                      Navigator.pop(context);
                    } else {
                      ctrl.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  child: Text(last ? 'ابدأ' : 'التالي'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
