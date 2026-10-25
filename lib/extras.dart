import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extras2.dart';
import 'extras3.dart';
import 'extras4.dart';
import 'extras5.dart';
import 'main.dart';

// ═════════════════════════ صفحة «المزيد» ═════════════════════════

class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.bill});
  final Bill bill;

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget Function() page,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_left),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page()),
      ),
    );
  }

  Widget _group(String title, IconData icon, List<Widget> children,
      {bool open = false}) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: open,
        leading: Icon(icon),
        title: Text(title),
        shape: const Border(),
        collapsedShape: const Border(),
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget item(IconData i, String t, String s, Widget Function() p) =>
        _item(context, icon: i, title: t, subtitle: s, page: p);
    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AlertsCard(bill: bill),
          _group('الأساسيات', Icons.star_outline, [
            item(Icons.swap_horiz, 'الديون بين الأصدقاء',
                'مَن عليه لمَن، دفعات جزئية ووعود سداد', () => DebtsPage(bill: bill)),
            item(Icons.beach_access_outlined, 'الرحلات والمصاريف الجماعية',
                'كل واحد يسجل ما دفعه، والتسوية بأقل تحويلات',
                () => const TripsListPage()),
            item(Icons.request_quote_outlined, 'الأقساط',
                'أقساط لك أو عليك: جدول وسداد وتذكير',
                () => const InstallmentsPage()),
            item(Icons.groups_outlined, 'الجمعية الشهرية',
                'جدول القبض ومَن دفع هذا الشهر', () => const JamiyaListPage()),
          ], open: true),
          _group('فواتير وصناديق', Icons.account_balance_wallet_outlined, [
            item(Icons.event_repeat, 'فواتير متكررة',
                'إيجار وكهرباء، ومَن عليه الدور هذا الشهر',
                () => const RecurringPage()),
            item(Icons.savings_outlined, 'الصندوق المشترك',
                'إيداع وصرف ورصيد الجماعة', () => const FundListPage()),
            item(Icons.photo_library_outlined, 'صور الإيصالات',
                'احفظ صورة الإيصال وافتحها لاحقاً', () => const ReceiptsPage()),
          ]),
          _group('أدوات التقسيم', Icons.calculate_outlined, [
            item(Icons.group_outlined, 'مجموعات وقوالب',
                'احفظ شلتك وأضفها للفاتورة بضغطة', () => GroupsPage(bill: bill)),
            item(Icons.volunteer_activism_outlined, 'توزيع الإكرامية',
                'حسب ما أكل كل واحد أو بالتساوي', () => TipPage(bill: bill)),
            item(Icons.currency_exchange, 'عملة أخرى',
                'الحصص بالدولار أو اليورو وغيرها', () => CurrencyPage(bill: bill)),
            item(Icons.qr_code_2, 'كود الحساب',
                'أرسل حسابك بكود، أو افتح كود وصلك', () => ShareCodePage(bill: bill)),
            item(Icons.casino_outlined, 'من يدفع هذه المرة؟',
                'قرعة مرحة تختار الدافع', () => WheelPage(bill: bill)),
          ]),
          _group('تقارير وتحليل', Icons.insights_outlined, [
            item(Icons.assessment_outlined, 'تقرير شهري',
                'الإجمالي والأرصدة، جاهز للمشاركة', () => ReportPage(bill: bill)),
            item(Icons.insights_outlined, 'إحصائيات',
                'كم صرفتم وأين ومَن دفع أكثر', () => StatsPage(bill: bill)),
            item(Icons.speed_outlined, 'الميزانية الشهرية',
                'سقف للصرف وتنبيه عند الاقتراب منه', () => BudgetPage(bill: bill)),
            item(Icons.person_search_outlined, 'سجل الأصدقاء',
                'كل ما بينك وبين كل صديق', () => FriendsPage(bill: bill)),
            item(Icons.emoji_events_outlined, 'مَن يدفع أكثر؟',
                'ألقاب مرحة: كريم الشلة والمتهرّب', () => const LeaderboardPage()),
            item(Icons.search, 'بحث', 'ابحث بالاسم أو المبلغ أو التاريخ',
                () => SearchPage(bill: bill)),
          ]),
          _group('البيانات والإعدادات', Icons.settings_outlined, [
            item(Icons.table_chart_outlined, 'تصدير كشف حساب',
                'ملف CSV يفتح في Excel', () => ExportPage(bill: bill)),
            item(Icons.delete_sweep_outlined, 'سلة المحذوفات',
                'استرجع ما حذفته خلال 30 يوماً', () => const TrashPage()),
            item(Icons.settings_outlined, 'الإعدادات والنسخ الاحتياطي',
                'المظهر، الملف الشخصي، القفل، النسخ', () => const SettingsPage()),
          ]),
        ],
      ),
    );
  }
}

Future<void> _shareOrCopy(BuildContext context, String text) async {
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

/// حقل اسم مع أسماء مقترحة تُملأ بالضغط.
class _NamePicker extends StatelessWidget {
  const _NamePicker({
    required this.controller,
    required this.label,
    required this.names,
  });
  final TextEditingController controller;
  final String label;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
        ),
        if (names.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 0,
              children: [
                for (final n in names)
                  ActionChip(
                    label: Text(n),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => controller.text = n,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ═════════════════════════ الديون بين الأصدقاء ═════════════════════════

class DebtEntry {
  DebtEntry({
    required this.id,
    required this.debtor,
    required this.creditor,
    required this.amount,
    required this.note,
    required this.date,
    this.settled = false,
    this.paid = 0,
    List<Map<String, dynamic>>? payments,
    this.promise,
  }) : payments = payments ?? [];
  final String id;
  final String debtor; // مَن عليه الدين
  final String creditor; // صاحب الحق
  double amount;
  String note;
  final DateTime date;
  bool settled;
  double paid; // ما سُدِّد جزئياً
  final List<Map<String, dynamic>> payments; // [{a: مبلغ, d: تاريخ}]
  DateTime? promise; // تاريخ الوعد بالسداد

  double get remaining => amount - paid > 0 ? amount - paid : 0.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'debtor': debtor,
        'creditor': creditor,
        'amount': amount,
        'note': note,
        'date': date.toIso8601String(),
        'settled': settled,
        'paid': paid,
        'payments': payments,
        'promise': promise?.toIso8601String(),
      };

  factory DebtEntry.fromJson(Map<String, dynamic> j) => DebtEntry(
        id: j['id'] as String,
        debtor: j['debtor'] as String,
        creditor: j['creditor'] as String,
        amount: (j['amount'] as num).toDouble(),
        note: (j['note'] as String?) ?? '',
        date: DateTime.parse(j['date'] as String),
        settled: (j['settled'] as bool?) ?? false,
        paid: (j['paid'] as num?)?.toDouble() ?? 0,
        payments: [
          for (final p in (j['payments'] as List? ?? []))
            Map<String, dynamic>.from(p as Map)
        ],
        promise: j['promise'] == null
            ? null
            : DateTime.tryParse(j['promise'].toString()),
      );
}

class NetDebt {
  NetDebt(this.debtor, this.creditor, this.amount);
  final String debtor;
  final String creditor;
  final double amount;
}

class DebtBook extends ChangeNotifier {
  final List<DebtEntry> entries = [];
  static const _key = 'qassimha_debts_v1';
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final s = sp.getString(_key);
      if (s == null || _disposed) return;
      final list = jsonDecode(s) as List;
      entries
        ..clear()
        ..addAll([
          for (final e in list)
            DebtEntry.fromJson(Map<String, dynamic>.from(e as Map))
        ]);
      if (!_disposed) super.notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _key,
        jsonEncode([for (final e in entries) e.toJson()]),
      );
    } catch (_) {}
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    _save();
  }

  void add(DebtEntry e) {
    entries.insert(0, e);
    notifyListeners();
  }

  void remove(DebtEntry e) {
    final i = entries.indexOf(e);
    entries.remove(e);
    notifyListeners();
    final tid = trashPush(
        _key, '${e.debtor} ← ${e.creditor}', Map<String, dynamic>.from(e.toJson()));
    showUndo('تم حذف الدين', () {
      if (_disposed) {
        restoreToPrefs(_key, e.toJson());
      } else {
        entries.insert(i > entries.length ? entries.length : i, e);
        notifyListeners();
      }
      trashRemove(tid);
    });
  }

  /// دفعة جزئية: تنقص المتبقي، وتُسجَّل في سجل الدفعات.
  void addPayment(DebtEntry e, double amount) {
    final a = amount > e.remaining ? e.remaining : amount;
    if (a <= 0) return;
    e.paid += a;
    e.payments.add({'a': a, 'd': DateTime.now().toIso8601String()});
    if (e.remaining <= 0.005) e.settled = true;
    notifyListeners();
  }

  void editDebt(DebtEntry e, double amount, String note) {
    e.amount = amount;
    e.note = note.trim();
    e.settled = e.remaining <= 0.005;
    notifyListeners();
  }

  void setPromise(DebtEntry e, DateTime? d) {
    e.promise = d;
    notifyListeners();
  }

  void settlePair(String a, String b) {
    for (final e in entries) {
      if (e.settled) continue;
      if ((e.debtor == a && e.creditor == b) ||
          (e.debtor == b && e.creditor == a)) {
        e.settled = true;
      }
    }
    notifyListeners();
  }

  List<String> knownNames(Bill bill) {
    final names = <String>{
      for (final p in bill.people) p.name,
      for (final e in entries) ...[e.debtor, e.creditor],
    };
    return names.toList();
  }

  /// صافي ما على كل شخص تجاه كل شخص آخر (غير المسدد فقط).
  List<NetDebt> nets() {
    final m = <String, Map<String, double>>{};
    for (final e in entries) {
      if (e.settled) continue;
      final inner = m.putIfAbsent(e.debtor, () => <String, double>{});
      inner[e.creditor] = (inner[e.creditor] ?? 0) + e.remaining;
    }
    final out = <NetDebt>[];
    final seen = <String>{};
    for (final a in m.keys) {
      for (final b in m[a]!.keys) {
        final key = a.compareTo(b) < 0 ? '$a\u0000$b' : '$b\u0000$a';
        if (!seen.add(key)) continue;
        final ab = m[a]![b] ?? 0;
        final ba = m[b]?[a] ?? 0;
        final net = ab - ba;
        if (net > 0.005) {
          out.add(NetDebt(a, b, net));
        } else if (net < -0.005) {
          out.add(NetDebt(b, a, -net));
        }
      }
    }
    out.sort((x, y) => y.amount.compareTo(x.amount));
    return out;
  }
}

class DebtsPage extends StatefulWidget {
  const DebtsPage({super.key, required this.bill});
  final Bill bill;

  @override
  State<DebtsPage> createState() => _DebtsPageState();
}

class _DebtsPageState extends State<DebtsPage> {
  final DebtBook book = DebtBook();

  @override
  void initState() {
    super.initState();
    book.load();
  }

  @override
  void dispose() {
    book.dispose();
    super.dispose();
  }

  void _snack(String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  bool _soon(DateTime d) =>
      d.isBefore(DateTime.now().add(const Duration(days: 1)));

  Widget _debtTile(DebtEntry e) {
    final isLate = e.promise != null && e.promise!.isBefore(DateTime.now());
    final status = e.promise == null
        ? 'مستحق'
        : isLate
            ? '⏰ متأخر عن وعد ${fmtDate(e.promise!)}'
            : 'وعد بالدفع ${fmtDate(e.promise!)}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${e.debtor} ← ${e.creditor}'),
      subtitle: Text(
        '$status · ${fmtDate(e.date)}'
        '${e.note.isEmpty ? '' : ' · ${e.note}'}'
        '${e.paid > 0 ? ' · دُفع ${fmt(e.paid)} من ${fmt(e.amount)}' : ''}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${fmt(e.remaining)} $kCurrency'),
          PopupMenuButton<String>(
            onSelected: (v) => _debtAction(e, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pay', child: Text('دفعة جزئية')),
              PopupMenuItem(value: 'promise', child: Text('وعد بالدفع بتاريخ')),
              PopupMenuItem(value: 'edit', child: Text('تعديل المبلغ والملاحظة')),
              PopupMenuItem(value: 'history', child: Text('سجل الدفعات')),
              PopupMenuItem(value: 'remind', child: Text('تذكير')),
              PopupMenuItem(value: 'delete', child: Text('حذف')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _debtAction(DebtEntry e, String v) async {
    switch (v) {
      case 'pay':
        final t = await askText(context, 'دفعة جزئية', 'المبلغ ($kCurrency)');
        final a = t == null ? null : parsePrice(t);
        if (a != null && a > 0) book.addPayment(e, a);
        break;
      case 'promise':
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: e.promise != null && e.promise!.isAfter(now)
              ? e.promise!
              : now.add(const Duration(days: 3)),
          firstDate: now.subtract(const Duration(days: 1)),
          lastDate: now.add(const Duration(days: 730)),
        );
        if (d != null) book.setPromise(e, d);
        break;
      case 'edit':
        final ta = await askText(
            context, 'تعديل المبلغ', 'المبلغ ($kCurrency)', fmt(e.amount));
        final na = ta == null ? null : parsePrice(ta);
        if (na == null || na <= 0) return;
        if (!mounted) return;
        final tn = await askText(context, 'الملاحظة', 'ملاحظة', e.note);
        book.editDebt(e, na, tn ?? e.note);
        break;
      case 'history':
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('سجل الدفعات'),
            content: e.payments.isEmpty
                ? const Text('لا توجد دفعات بعد')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final p in e.payments)
                        ListTile(
                          dense: true,
                          title: Text(
                              '${fmt((p['a'] as num).toDouble())} $kCurrency'),
                          subtitle: Text(fmtDate(
                              DateTime.tryParse(p['d'].toString()) ??
                                  DateTime.now())),
                        ),
                    ],
                  ),
          ),
        );
        break;
      case 'remind':
        if (!mounted) return;
        await shareText(context, remindText(e.debtor, e.remaining, e.note));
        break;
      case 'delete':
        book.remove(e);
        break;
    }
  }

  Future<void> _addDebt() async {
    final e = await showDialog<DebtEntry>(
      context: context,
      builder: (_) => _DebtDialog(names: book.knownNames(widget.bill)),
    );
    if (e != null) book.add(e);
  }

  Future<void> _importFromBill() async {
    final bill = widget.bill;
    final totals = bill.totals;
    if (bill.people.length < 2 || bill.grandTotal <= 0) {
      _snack('لا توجد فاتورة حالية بأشخاص وبنود');
      return;
    }
    final payer = await showDialog<Person>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('مَن دفع الفاتورة؟'),
        children: [
          for (final p in bill.people)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: Text(p.name),
            ),
        ],
      ),
    );
    if (payer == null) return;
    var count = 0;
    for (final p in bill.people) {
      final v = totals[p.id] ?? 0;
      if (p.id == payer.id || v <= 0) continue;
      book.add(DebtEntry(
        id: '${DateTime.now().microsecondsSinceEpoch}_${p.id}',
        debtor: p.name,
        creditor: payer.name,
        amount: v,
        note: 'فاتورة',
        date: DateTime.now(),
      ));
      count++;
    }
    if (!mounted) return;
    _snack('سُجّلت $count ديون من الفاتورة');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الديون بين الأصدقاء')),
      body: ListenableBuilder(
        listenable: book,
        builder: (context, _) {
          final nets = book.nets();
          final open = book.entries.where((e) => !e.settled).toList();
          final done = book.entries.where((e) => e.settled).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (open.any((e) => e.promise != null && _soon(e.promise!)))
                Card(
                  color: cs.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '⏰ ${open.where((e) => e.promise != null && _soon(e.promise!)).length} دين يستحق قريباً أو متأخر',
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _addDebt,
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة دين'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _importFromBill,
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('من الفاتورة'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('الصافي', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (nets.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('لا توجد ديون غير مسددة'),
                ),
              for (final n in nets)
                Card(
                  color: cs.primaryContainer,
                  child: ListTile(
                    title: Text('${n.debtor} ← ${n.creditor}'),
                    subtitle: Text('${fmt(n.amount)} $kCurrency'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'تذكير',
                          icon: const Icon(Icons.notifications_active_outlined),
                          onPressed: () => shareText(
                            context,
                            remindText(n.debtor, n.amount, ''),
                          ),
                        ),
                        TextButton(
                          onPressed: () => book.settlePair(n.debtor, n.creditor),
                          child: const Text('سدّد'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (nets.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => _shareOrCopy(
                        context,
                        [
                          '🤝 ديون الأصدقاء',
                          for (final n in nets)
                            '• ${n.debtor} يدفع لـ ${n.creditor}: ${fmt(n.amount)} $kCurrency',
                          kTagline,
                        ].join('\n'),
                      ),
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('شارك الصافي'),
                    ),
                  ),
                ),
              if (open.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('السجل', style: Theme.of(context).textTheme.titleMedium),
                for (final e in open) _debtTile(e),
              ],
              if (done.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('المسددة (${done.length})'),
                  children: [
                    for (final e in done)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${e.debtor} ← ${e.creditor}'),
                        subtitle: Text(fmtDate(e.date)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${fmt(e.amount)} $kCurrency'),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => book.remove(e),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DebtDialog extends StatefulWidget {
  const _DebtDialog({required this.names});
  final List<String> names;

  @override
  State<_DebtDialog> createState() => _DebtDialogState();
}

class _DebtDialogState extends State<_DebtDialog> {
  final _debtor = TextEditingController();
  final _creditor = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _debtor.dispose();
    _creditor.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final d = _debtor.text.trim();
    final c = _creditor.text.trim();
    final a = parsePrice(_amount.text);
    if (d.isEmpty || c.isEmpty) {
      setState(() => _error = 'اكتب الاسمين');
      return;
    }
    if (d == c) {
      setState(() => _error = 'الاسمان متطابقان');
      return;
    }
    if (a == null || a <= 0) {
      setState(() => _error = 'المبلغ غير صحيح');
      return;
    }
    Navigator.pop(
      context,
      DebtEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        debtor: d,
        creditor: c,
        amount: a,
        note: _note.text.trim(),
        date: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('إضافة دين'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NamePicker(
            controller: _debtor,
            label: 'مَن عليه الدين',
            names: widget.names,
          ),
          const SizedBox(height: 8),
          _NamePicker(
            controller: _creditor,
            label: 'لمَن (صاحب الحق)',
            names: widget.names,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'المبلغ',
              suffixText: kCurrency,
            ),
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _submit, child: const Text('إضافة')),
      ],
    );
  }
}

// ═════════════════════════ الجمعية الشهرية ═════════════════════════

const List<String> _monthNames = [
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

String _monthLabel(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';

class Jamiya {
  Jamiya({
    required this.id,
    required this.name,
    required this.amount,
    required this.members,
    required this.startYear,
    required this.startMonth,
    Set<String>? paid,
  }) : paid = paid ?? <String>{};

  final String id;
  String name;
  double amount;
  List<String> members; // بترتيب القبض
  int startYear;
  int startMonth;
  Set<String> paid; // «شهر:عضو»

  DateTime monthDate(int k) => DateTime(startYear, startMonth + k);
  double get pot => amount * members.length;
  bool isPaid(int k, int i) => paid.contains('$k:$i');
  int paidCount(int k) {
    var c = 0;
    for (var i = 0; i < members.length; i++) {
      if (isPaid(k, i)) c++;
    }
    return c;
  }

  /// فهرس الشهر الحالي داخل الدورة، أو null إن كنا خارجها.
  int? currentIndex() {
    final now = DateTime.now();
    for (var k = 0; k < members.length; k++) {
      final d = monthDate(k);
      if (d.year == now.year && d.month == now.month) return k;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        'members': members,
        'startYear': startYear,
        'startMonth': startMonth,
        'paid': paid.toList(),
      };

  factory Jamiya.fromJson(Map<String, dynamic> j) => Jamiya(
        id: j['id'] as String,
        name: j['name'] as String,
        amount: (j['amount'] as num).toDouble(),
        members: List<String>.from(j['members'] as List),
        startYear: (j['startYear'] as num).toInt(),
        startMonth: (j['startMonth'] as num).toInt(),
        paid: Set<String>.from(j['paid'] as List? ?? const []),
      );
}

class JamiyaBook extends ChangeNotifier {
  final List<Jamiya> items = [];
  static const _key = 'qassimha_jamiya_v1';
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final s = sp.getString(_key);
      if (s == null || _disposed) return;
      final list = jsonDecode(s) as List;
      items
        ..clear()
        ..addAll([
          for (final e in list)
            Jamiya.fromJson(Map<String, dynamic>.from(e as Map))
        ]);
      if (!_disposed) super.notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _key,
        jsonEncode([for (final j in items) j.toJson()]),
      );
    } catch (_) {}
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    _save();
  }

  Jamiya? byId(String id) {
    for (final j in items) {
      if (j.id == id) return j;
    }
    return null;
  }

  void add(Jamiya j) {
    items.insert(0, j);
    notifyListeners();
  }

  void remove(Jamiya j) {
    final i = items.indexOf(j);
    items.remove(j);
    notifyListeners();
    final tid = trashPush(_key, j.name, Map<String, dynamic>.from(j.toJson()));
    showUndo('تم حذف الجمعية', () {
      if (_disposed) {
        restoreToPrefs(_key, j.toJson());
      } else {
        items.insert(i > items.length ? items.length : i, j);
        notifyListeners();
      }
      trashRemove(tid);
    });
  }

  void togglePaid(Jamiya j, int k, int i) {
    final key = '$k:$i';
    if (!j.paid.add(key)) j.paid.remove(key);
    notifyListeners();
  }
}

class JamiyaListPage extends StatefulWidget {
  const JamiyaListPage({super.key});

  @override
  State<JamiyaListPage> createState() => _JamiyaListPageState();
}

class _JamiyaListPageState extends State<JamiyaListPage> {
  final JamiyaBook book = JamiyaBook();

  @override
  void initState() {
    super.initState();
    book.load();
  }

  @override
  void dispose() {
    book.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final j = await showDialog<Jamiya>(
      context: context,
      builder: (_) => const _JamiyaDialog(),
    );
    if (j != null) book.add(j);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الجمعية الشهرية')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('جمعية جديدة'),
      ),
      body: ListenableBuilder(
        listenable: book,
        builder: (context, _) {
          if (book.items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'لا توجد جمعيات بعد. اضغط «جمعية جديدة» وأدخل الأعضاء بترتيب القبض.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              for (final j in book.items)
                Card(
                  child: ListTile(
                    title: Text(j.name),
                    subtitle: Text(
                      'القسط ${fmt(j.amount)} $kCurrency · ${j.members.length} أعضاء · القبض ${fmt(j.pot)} $kCurrency',
                    ),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => JamiyaDetailPage(book: book, id: j.id),
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

class JamiyaDetailPage extends StatelessWidget {
  const JamiyaDetailPage({super.key, required this.book, required this.id});
  final JamiyaBook book;
  final String id;

  String _scheduleText(Jamiya j) {
    final lines = <String>[
      '🤝 جمعية ${j.name}',
      'القسط الشهري: ${fmt(j.amount)} $kCurrency · القبض: ${fmt(j.pot)} $kCurrency',
      for (var k = 0; k < j.members.length; k++)
        '${k + 1}) ${_monthLabel(j.monthDate(k))}: ${j.members[k]}',
      kTagline,
    ];
    return lines.join('\n');
  }

  Future<void> _confirmDelete(BuildContext context, Jamiya j) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الجمعية؟'),
        content: Text('سيُحذف جدول «${j.name}» وكل ما سُجّل فيه.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('احذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      book.remove(j);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: book,
      builder: (context, _) {
        final j = book.byId(id);
        if (j == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('هذه الجمعية غير موجودة')),
          );
        }
        final current = j.currentIndex();
        return Scaffold(
          appBar: AppBar(
            title: Text(j.name),
            actions: [
              IconButton(
                tooltip: 'شارك الجدول',
                icon: const Icon(Icons.share),
                onPressed: () => _shareOrCopy(context, _scheduleText(j)),
              ),
              IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, j),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('القسط الشهري: ${fmt(j.amount)} $kCurrency'),
                      const SizedBox(height: 4),
                      Text(
                        'مبلغ القبض كل شهر: ${fmt(j.pot)} $kCurrency',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('مدة الدورة: ${j.members.length} شهراً'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (var k = 0; k < j.members.length; k++)
                ExpansionTile(
                  key: PageStorageKey<String>('${j.id}_$k'),
                  initiallyExpanded: k == current,
                  tilePadding: EdgeInsets.zero,
                  leading: Icon(
                    j.paidCount(k) == j.members.length
                        ? Icons.check_circle
                        : (k == current
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked),
                  ),
                  title: Text(_monthLabel(j.monthDate(k))),
                  subtitle: Text(
                    'يقبض: ${j.members[k]} · دُفع ${j.paidCount(k)} من ${j.members.length}',
                  ),
                  children: [
                    for (var i = 0; i < j.members.length; i++)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: j.isPaid(k, i),
                        onChanged: (_) => book.togglePaid(j, k, i),
                        title: Text(j.members[i]),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _JamiyaDialog extends StatefulWidget {
  const _JamiyaDialog();

  @override
  State<_JamiyaDialog> createState() => _JamiyaDialogState();
}

class _JamiyaDialogState extends State<_JamiyaDialog> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _members = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _members.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = parsePrice(_amount.text);
    final members = _members.text
        .split(RegExp(r'[\n,،]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (amount == null || amount <= 0) {
      setState(() => _error = 'القسط الشهري غير صحيح');
      return;
    }
    if (members.length < 2) {
      setState(() => _error = 'أدخل عضوين على الأقل');
      return;
    }
    final now = DateTime.now();
    final name = _name.text.trim();
    Navigator.pop(
      context,
      Jamiya(
        id: now.microsecondsSinceEpoch.toString(),
        name: name.isEmpty ? 'جمعية' : name,
        amount: amount,
        members: members,
        startYear: now.year,
        startMonth: now.month,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('جمعية جديدة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'اسم الجمعية'),
          ),
          TextField(
            controller: _amount,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'القسط الشهري لكل عضو',
              suffixText: kCurrency,
            ),
          ),
          TextField(
            controller: _members,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'الأعضاء بترتيب القبض (كل اسم في سطر)',
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _submit, child: const Text('إنشاء')),
      ],
    );
  }
}
