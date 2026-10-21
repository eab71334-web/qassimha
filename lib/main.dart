import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const QassimhaApp());

const String kCurrency = 'د.ل';

// ───────────────────────── النماذج ─────────────────────────

class Person {
  Person(this.id, this.name);
  final String id;
  String name;
}

class Item {
  Item(this.id, this.name, this.price, this.eaters);
  final String id;
  String name;
  double price;
  Set<String> eaters;
}

/// دفعة خرجت من المحفظة (فاتورة مدفوعة).
class Payment {
  Payment(this.title, this.total, this.date, this.shares);
  final String title;
  final double total;
  final DateTime date;
  final Map<String, double> shares;

  Map<String, dynamic> toJson() => {
        'title': title,
        'total': total,
        'date': date.toIso8601String(),
        'shares': shares,
      };

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
        j['title'] as String,
        (j['total'] as num).toDouble(),
        DateTime.parse(j['date'] as String),
        (j['shares'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
      );
}

class Bill extends ChangeNotifier {
  final List<Person> people = [];
  final List<Item> items = [];
  final Map<String, double> deposits = {}; // مجموع ما أودعه كل شخص
  final List<Payment> history = [];
  double extraPercent = 0; // خدمة / ضريبة / بقشيش
  int _seq = 0;

  String _id() => '${_seq++}';

  // ── الأشخاص والبنود ──

  void addPerson(String name) {
    people.add(Person(_id(), name));
    notifyListeners();
  }

  bool hasMoney(Person p) =>
      (deposits[p.id] ?? 0) != 0 ||
      history.any((h) => h.shares.containsKey(p.id));

  /// يرجع false إذا للشخص حركة مالية في المحفظة فلا يُحذف.
  bool removePerson(Person p) {
    if (hasMoney(p)) return false;
    people.remove(p);
    for (final i in items) {
      i.eaters.remove(p.id);
    }
    notifyListeners();
    return true;
  }

  void addItem(String name, double price) {
    items.add(Item(_id(), name, price, people.map((p) => p.id).toSet()));
    notifyListeners();
  }

  void removeItem(Item i) {
    items.remove(i);
    notifyListeners();
  }

  void toggleEater(Item item, Person p) {
    if (!item.eaters.add(p.id)) {
      item.eaters.remove(p.id);
    }
    notifyListeners();
  }

  void setExtra(double v) {
    extraPercent = v;
    notifyListeners();
  }

  int get unassignedCount => items.where((i) => i.eaters.isEmpty).length;

  /// نصيب كل شخص من الفاتورة الحالية (بعد إضافة النسبة الإضافية).
  Map<String, double> get totals {
    final result = {for (final p in people) p.id: 0.0};
    final factor = 1 + extraPercent / 100;
    for (final i in items) {
      if (i.eaters.isEmpty) continue;
      final share = i.price * factor / i.eaters.length;
      for (final id in i.eaters) {
        if (result.containsKey(id)) result[id] = result[id]! + share;
      }
    }
    return result;
  }

  double get grandTotal => totals.values.fold(0.0, (a, b) => a + b);

  // ── المحفظة المشتركة ──

  double get walletBalance =>
      deposits.values.fold(0.0, (a, b) => a + b) -
      history.fold(0.0, (a, p) => a + p.total);

  /// رصيد الشخص: ما أودعه ناقص حصصه من الفواتير المدفوعة.
  double personBalance(String id) =>
      (deposits[id] ?? 0) -
      history.fold(0.0, (a, p) => a + (p.shares[id] ?? 0));

  void deposit(String personId, double amount) {
    deposits[personId] = (deposits[personId] ?? 0) + amount;
    notifyListeners();
  }

  /// يدفع الفاتورة الحالية من المحفظة ويسجّلها ويفرّغ البنود.
  void payFromWallet(String title) {
    final shares = Map<String, double>.of(totals)
      ..removeWhere((_, v) => v == 0);
    history.insert(0, Payment(title, grandTotal, DateTime.now(), shares));
    items.clear();
    notifyListeners();
  }

  // ── الملخص ──

  String summaryText() {
    final t = totals;
    final buf = StringBuffer('🧾 قسّمها\n');
    for (final p in people) {
      buf.writeln('• ${p.name}: ${fmt(t[p.id] ?? 0)} $kCurrency');
    }
    buf.writeln('────────');
    buf.writeln('الإجمالي: ${fmt(grandTotal)} $kCurrency');
    return buf.toString();
  }

  // ── الحفظ على الجهاز ──

  static const _key = 'qassimha_bill_v1';

  Map<String, dynamic> toJson() => {
        'seq': _seq,
        'extra': extraPercent,
        'people': [
          for (final p in people) {'id': p.id, 'name': p.name}
        ],
        'items': [
          for (final i in items)
            {
              'id': i.id,
              'name': i.name,
              'price': i.price,
              'eaters': i.eaters.toList(),
            }
        ],
        'deposits': deposits,
        'history': [for (final h in history) h.toJson()],
      };

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final s = sp.getString(_key);
      if (s == null) return;
      final m = jsonDecode(s) as Map<String, dynamic>;
      _seq = (m['seq'] as num?)?.toInt() ?? 0;
      extraPercent = (m['extra'] as num?)?.toDouble() ?? 0;
      people
        ..clear()
        ..addAll([
          for (final p in (m['people'] as List? ?? []))
            Person(p['id'] as String, p['name'] as String)
        ]);
      items
        ..clear()
        ..addAll([
          for (final i in (m['items'] as List? ?? []))
            Item(
              i['id'] as String,
              i['name'] as String,
              (i['price'] as num).toDouble(),
              Set<String>.from(i['eaters'] as List),
            )
        ]);
      deposits
        ..clear()
        ..addAll((m['deposits'] as Map? ?? {}).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ));
      history
        ..clear()
        ..addAll([
          for (final h in (m['history'] as List? ?? []))
            Payment.fromJson(Map<String, dynamic>.from(h as Map))
        ]);
      super.notifyListeners();
    } catch (_) {
      // بيانات تالفة: نبدأ من جديد
    }
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, jsonEncode(toJson()));
    } catch (_) {}
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    _save();
  }
}

String fmt(double v) => v.toStringAsFixed(2);

String fmtDate(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// يحوّل الأرقام العربية والفاصلة العربية ثم يقرأ الرقم.
double? parsePrice(String s) {
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  final buf = StringBuffer();
  for (final ch in s.trim().split('')) {
    final idx = arabicDigits.indexOf(ch);
    if (idx >= 0) {
      buf.write(idx);
    } else if (ch == '٫' || ch == ',' || ch == '،') {
      buf.write('.');
    } else {
      buf.write(ch);
    }
  }
  return double.tryParse(buf.toString());
}

// ───────────────────────── التطبيق ─────────────────────────

class QassimhaApp extends StatelessWidget {
  const QassimhaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'قسّمها',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0E7C66),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0E7C66),
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Bill bill = Bill();

  @override
  void initState() {
    super.initState();
    bill.load();
  }

  @override
  void dispose() {
    bill.dispose();
    super.dispose();
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addPerson() async {
    final name = await _askText('إضافة شخص', 'الاسم');
    if (name != null && name.isNotEmpty) bill.addPerson(name);
  }

  void _removePerson(Person p) {
    if (!bill.removePerson(p)) {
      _snack('لا يمكن حذف شخص لديه حركة في المحفظة');
    }
  }

  Future<void> _addItem() async {
    if (bill.people.isEmpty) {
      _snack('أضف الأشخاص أولاً');
      return;
    }
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة بند'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'اسم البند'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'السعر',
                suffixText: kCurrency,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final price = parsePrice(priceCtrl.text);
    final name = nameCtrl.text.trim();
    if (price == null || price <= 0) {
      if (!mounted) return;
      _snack('السعر غير صحيح');
      return;
    }
    bill.addItem(name.isEmpty ? 'بند' : name, price);
  }

  Future<void> _deposit() async {
    if (bill.people.isEmpty) {
      _snack('أضف الأشخاص أولاً');
      return;
    }
    String personId = bill.people.first.id;
    final amountCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('إيداع في المحفظة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                isExpanded: true,
                value: personId,
                items: [
                  for (final p in bill.people)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) {
                  if (v != null) setSt(() => personId = v);
                },
              ),
              TextField(
                controller: amountCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'المبلغ',
                  suffixText: kCurrency,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إيداع'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amount = parsePrice(amountCtrl.text);
    if (amount == null || amount <= 0) {
      if (!mounted) return;
      _snack('المبلغ غير صحيح');
      return;
    }
    bill.deposit(personId, amount);
  }

  Future<void> _payFromWallet() async {
    final title = await _askText(
      'دفع الفاتورة من المحفظة',
      'اسم الفاتورة (مثال: عشاء الخميس)',
      confirm: 'ادفع',
    );
    if (title == null) return;
    bill.payFromWallet(title.isEmpty ? 'فاتورة' : title);
    if (!mounted) return;
    _snack('تم الدفع من المحفظة');
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: bill.summaryText()));
    if (!mounted) return;
    _snack('تم نسخ الملخص');
  }

  Future<void> _share(BuildContext btnContext) async {
    final box = btnContext.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    try {
      await Share.share(bill.summaryText(), sharePositionOrigin: origin);
    } catch (_) {
      await _copy();
    }
  }

  Future<String?> _askText(String title, String label,
      {String confirm = 'إضافة'}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: Text(confirm),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: bill,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('قسّمها')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _addItem,
            icon: const Icon(Icons.add),
            label: const Text('بند جديد'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _section('من معنا؟'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final p in bill.people)
                    InputChip(
                      label: Text(p.name),
                      onDeleted: () => _removePerson(p),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('إضافة شخص'),
                    onPressed: _addPerson,
                  ),
                ],
              ),
              _section('البنود'),
              if (bill.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                      'لا توجد بنود بعد. اضغط «بند جديد» وأدخل ما أُكل أو اشتُري.'),
                ),
              for (final item in bill.items) _itemCard(item),
              _section('خدمة / ضريبة / بقشيش'),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: bill.extraPercent,
                      min: 0,
                      max: 30,
                      divisions: 30,
                      label: '${bill.extraPercent.round()}%',
                      onChanged: bill.setExtra,
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text('${bill.extraPercent.round()}%'),
                  ),
                ],
              ),
              _section('الحساب'),
              _resultsCard(context),
              _section('المحفظة المشتركة'),
              _walletCard(context),
            ],
          ),
        );
      },
    );
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );

  Widget _itemCard(Item item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text('${fmt(item.price)} $kCurrency'),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => bill.removeItem(item),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final p in bill.people)
                  FilterChip(
                    label: Text(p.name),
                    selected: item.eaters.contains(p.id),
                    onSelected: (_) => bill.toggleEater(item, p),
                  ),
              ],
            ),
            if (item.eaters.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'اختر من شارك في هذا البند',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _resultsCard(BuildContext context) {
    final t = bill.totals;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (bill.people.isEmpty)
              const Text('أضف الأشخاص والبنود لتظهر النتيجة'),
            for (final p in bill.people)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(p.name)),
                    Text(
                      '${fmt(t[p.id] ?? 0)} $kCurrency',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            if (bill.people.isNotEmpty) ...[
              const Divider(),
              Row(
                children: [
                  const Expanded(child: Text('الإجمالي')),
                  Text(
                    '${fmt(bill.grandTotal)} $kCurrency',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (bill.unassignedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${bill.unassignedCount} بند بدون أشخاص لم يُحتسب',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copy,
                      icon: const Icon(Icons.copy),
                      label: const Text('نسخ'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Builder(
                      builder: (btnContext) => FilledButton.icon(
                        onPressed: () => _share(btnContext),
                        icon: const Icon(Icons.share),
                        label: const Text('شارك الملخص'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _walletCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = bill.grandTotal;
    final balance = bill.walletBalance;
    final enough = balance + 0.005 >= total;
    final canPay =
        bill.items.isNotEmpty && bill.unassignedCount == 0 && total > 0 && enough;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('رصيد المحفظة')),
                Text(
                  '${fmt(balance)} $kCurrency',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            if (bill.people.isNotEmpty) const Divider(),
            for (final p in bill.people)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(p.name)),
                    Builder(builder: (_) {
                      final b = bill.personBalance(p.id);
                      final neg = b < -0.005;
                      return Text(
                        neg ? 'عليه ${fmt(-b)} $kCurrency' : 'له ${fmt(b)} $kCurrency',
                        style: TextStyle(color: neg ? cs.error : null),
                      );
                    }),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _deposit,
                    icon: const Icon(Icons.add),
                    label: const Text('إيداع'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: canPay ? _payFromWallet : null,
                    icon: const Icon(Icons.account_balance_wallet),
                    label: const Text('ادفع الفاتورة'),
                  ),
                ),
              ],
            ),
            if (bill.items.isNotEmpty && total > 0 && !enough)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'رصيد المحفظة لا يكفي، ينقص ${fmt(total - balance)} $kCurrency',
                  style: TextStyle(color: cs.error),
                ),
              ),
            if (bill.history.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('سجل الدفعات (${bill.history.length})'),
                children: [
                  for (final h in bill.history)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(h.title),
                      subtitle: Text(fmtDate(h.date)),
                      trailing: Text('${fmt(h.total)} $kCurrency'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
