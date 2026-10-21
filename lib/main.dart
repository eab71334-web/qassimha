import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const QassimhaApp());

const String kCurrency = 'د.ل';
const String kTagline = 'قُسّمت بتطبيق «قسّمها»';

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

/// فاتورة محفوظة في السجل.
class SavedBill {
  SavedBill(this.title, this.total, this.date, this.lines);
  final String title;
  final double total;
  final DateTime date;
  final Map<String, double> lines; // اسم الشخص -> المبلغ

  Map<String, dynamic> toJson() => {
        'title': title,
        'total': total,
        'date': date.toIso8601String(),
        'lines': lines,
      };

  factory SavedBill.fromJson(Map<String, dynamic> j) => SavedBill(
        j['title'] as String,
        (j['total'] as num).toDouble(),
        DateTime.parse(j['date'] as String),
        (j['lines'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
      );
}

class Bill extends ChangeNotifier {
  final List<Person> people = [];
  final List<Item> items = [];
  final List<SavedBill> saved = [];
  double extraPercent = 0; // خدمة / ضريبة / بقشيش
  double roundStep = 0; // 0 = بدون تقريب، 0.5، 1
  int _seq = 0;

  String _id() => '${_seq++}';

  void addPerson(String name) {
    people.add(Person(_id(), name));
    notifyListeners();
  }

  void removePerson(Person p) {
    people.remove(p);
    for (final i in items) {
      i.eaters.remove(p.id);
    }
    notifyListeners();
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

  void setRound(double v) {
    roundStep = v;
    notifyListeners();
  }

  int get unassignedCount => items.where((i) => i.eaters.isEmpty).length;

  /// نصيب كل شخص (بعد النسبة الإضافية والتقريب).
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
    if (roundStep > 0) {
      for (final id in result.keys.toList()) {
        final v = result[id]!;
        if (v > 0) {
          result[id] = (v / roundStep - 1e-9).ceil() * roundStep;
        }
      }
    }
    return result;
  }

  double get grandTotal => totals.values.fold(0.0, (a, b) => a + b);

  /// يحفظ الفاتورة في السجل ويفرّغ البنود.
  void saveAndClear(String title) {
    final t = totals;
    final lines = <String, double>{};
    for (final p in people) {
      final v = t[p.id] ?? 0;
      if (v > 0) lines[p.name] = v;
    }
    saved.insert(0, SavedBill(title, grandTotal, DateTime.now(), lines));
    items.clear();
    notifyListeners();
  }

  void deleteSaved(SavedBill b) {
    saved.remove(b);
    notifyListeners();
  }

  // ── نصوص المشاركة ──

  String summaryText() {
    final t = totals;
    final buf = StringBuffer('🧾 قسّمها\n');
    for (final p in people) {
      buf.writeln('• ${p.name}: ${fmt(t[p.id] ?? 0)} $kCurrency');
    }
    buf.writeln('────────');
    buf.writeln('الإجمالي: ${fmt(grandTotal)} $kCurrency');
    buf.writeln(kTagline);
    return buf.toString();
  }

  String requestText(Person p) {
    final v = totals[p.id] ?? 0;
    return 'مرحباً ${p.name} 👋\n'
        'حصتك من الحساب: ${fmt(v)} $kCurrency\n'
        'من فضلك حوّلها لي. شكراً!\n'
        '$kTagline';
  }

  // ── الحفظ على الجهاز ──

  static const _key = 'qassimha_bill_v1';

  Map<String, dynamic> toJson() => {
        'seq': _seq,
        'extra': extraPercent,
        'round': roundStep,
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
        'saved': [for (final s in saved) s.toJson()],
      };

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final s = sp.getString(_key);
      if (s == null) return;
      final m = jsonDecode(s) as Map<String, dynamic>;
      _seq = (m['seq'] as num?)?.toInt() ?? 0;
      extraPercent = (m['extra'] as num?)?.toDouble() ?? 0;
      roundStep = (m['round'] as num?)?.toDouble() ?? 0;
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
      saved.clear();
      for (final h in (m['saved'] as List? ?? [])) {
        try {
          saved.add(SavedBill.fromJson(Map<String, dynamic>.from(h as Map)));
        } catch (_) {}
      }
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

  Future<void> _saveBill() async {
    final title = await _askText(
      'حفظ الفاتورة',
      'اسم الفاتورة (مثال: عشاء الخميس)',
      confirm: 'احفظ',
    );
    if (title == null) return;
    bill.saveAndClear(title.isEmpty ? 'فاتورة' : title);
    if (!mounted) return;
    _snack('تم حفظ الفاتورة في السجل');
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: bill.summaryText()));
    if (!mounted) return;
    _snack('تم نسخ الملخص');
  }

  Future<void> _shareText(BuildContext btnContext, String text) async {
    final box = btnContext.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    try {
      await Share.share(text, sharePositionOrigin: origin);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      _snack('تم نسخ النص');
    }
  }

  Future<void> _showCard() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _CardDialog(bill: bill),
    );
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
                      onDeleted: () => bill.removePerson(p),
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
              _section('تقريب المبلغ لكل شخص'),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<double>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('بدون')),
                    ButtonSegment(value: 0.5, label: Text('0.5')),
                    ButtonSegment(value: 1, label: Text('1')),
                  ],
                  selected: {bill.roundStep},
                  onSelectionChanged: (s) => bill.setRound(s.first),
                ),
              ),
              _section('الحساب'),
              _resultsCard(context),
              if (bill.saved.isNotEmpty) ...[
                _section('سجل الفواتير'),
                _historyCard(context),
              ],
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
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(p.name)),
                    Text(
                      '${fmt(t[p.id] ?? 0)} $kCurrency',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Builder(
                      builder: (btnContext) => IconButton(
                        tooltip: 'أرسل له طلب الدفع',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.send, size: 20),
                        onPressed: (t[p.id] ?? 0) > 0
                            ? () => _shareText(btnContext, bill.requestText(p))
                            : null,
                      ),
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
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: bill.grandTotal > 0 ? _showCard : null,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('بطاقة الحساب (صورة للمشاركة)'),
                ),
              ),
              const SizedBox(height: 8),
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
                    child: Builder(
                      builder: (btnContext) => OutlinedButton.icon(
                        onPressed: () =>
                            _shareText(btnContext, bill.summaryText()),
                        icon: const Icon(Icons.share),
                        label: const Text('نص'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: bill.items.isNotEmpty ? _saveBill : null,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('احفظ'),
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

  Widget _historyCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (final b in bill.saved)
            ExpansionTile(
              title: Text(b.title),
              subtitle: Text('${fmtDate(b.date)} · ${fmt(b.total)} $kCurrency'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              children: [
                for (final e in b.lines.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text(e.key)),
                        Text('${fmt(e.value)} $kCurrency'),
                      ],
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: () => bill.deleteSaved(b),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('حذف'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ───────────────────── بطاقة الحساب (صورة) ─────────────────────

class _CardDialog extends StatefulWidget {
  const _CardDialog({required this.bill});
  final Bill bill;

  @override
  State<_CardDialog> createState() => _CardDialogState();
}

class _CardDialogState extends State<_CardDialog> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _busy = false;

  Future<void> _share(BuildContext btnContext) async {
    if (_busy) return;
    setState(() => _busy = true);
    final box = btnContext.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/qassimha_bill.png');
      await file.writeAsBytes(data!.buffer.asUint8List());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: kTagline,
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّرت مشاركة الصورة، جرّب مشاركة النص')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    final t = bill.totals;
    final rows = [
      for (final p in bill.people)
        if ((t[p.id] ?? 0) > 0) MapEntry(p.name, t[p.id]!),
    ];
    const green = Color(0xFF0E7C66);
    const ink = Color(0xFF16302B);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: RepaintBoundary(
                  key: _boundaryKey,
                  child: Container(
                    color: const Color(0xFFF4FBF8),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '🧾 حساب الجلسة',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          fmtDate(DateTime.now()),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 16),
                        for (final r in rows)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    r.key,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      color: ink,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${fmt(r.value)} $kCurrency',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Divider(height: 24, color: green),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'الإجمالي',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: ink,
                                ),
                              ),
                            ),
                            Text(
                              '${fmt(bill.grandTotal)} $kCurrency',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          kTagline,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black45),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إغلاق'),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Builder(
                    builder: (btnContext) => FilledButton.icon(
                      onPressed: _busy ? null : () => _share(btnContext),
                      icon: const Icon(Icons.share),
                      label: Text(_busy ? '...' : 'شارك الصورة'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// يمنع تحذير الاستيراد غير المستخدم لو تغيّر الكود لاحقاً.
// ignore: unused_element
double _unusedMax(double a, double b) => math.max(a, b);
