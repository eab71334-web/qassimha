import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:share_plus/share_plus.dart';

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

class Bill extends ChangeNotifier {
  final List<Person> people = [];
  final List<Item> items = [];
  double extraPercent = 0; // خدمة / ضريبة / بقشيش
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

  int get unassignedCount => items.where((i) => i.eaters.isEmpty).length;

  /// نصيب كل شخص (بعد إضافة النسبة الإضافية).
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
}

String fmt(double v) => v.toStringAsFixed(2);

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
  void dispose() {
    bill.dispose();
    super.dispose();
  }

  Future<void> _addPerson() async {
    final name = await _askText('إضافة شخص', 'الاسم');
    if (name != null && name.isNotEmpty) bill.addPerson(name);
  }

  Future<void> _addItem() async {
    if (bill.people.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف الأشخاص أولاً')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('السعر غير صحيح')),
      );
      return;
    }
    bill.addItem(name.isEmpty ? 'بند' : name, price);
  }

  Future<String?> _askText(String title, String label) {
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
            child: const Text('إضافة'),
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
                  child: Text('لا توجد بنود بعد. اضغط «بند جديد» وأدخل ما أُكل أو اشتُري.'),
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
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Share.share(bill.summaryText()),
                  icon: const Icon(Icons.share),
                  label: const Text('شارك الملخص'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
