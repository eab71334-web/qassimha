import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extras.dart';
import 'extras3.dart';
import 'extras4.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  loadAppSettings();
  runApp(const QassimhaApp());
}

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
    for (final i in items) {
      if (i.eaters.isNotEmpty) {
        buf.writeln('▫️ ${i.name}: ${fmt(i.price)} $kCurrency');
      }
    }
    if (items.isNotEmpty) buf.writeln('────────');
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
    return ListenableBuilder(
      listenable: Listenable.merge([gThemeMode, gTextScale]),
      builder: (context, _) => MaterialApp(
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
      themeMode: gThemeMode.value,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(gTextScale.value)),
        child: child ?? const SizedBox(),
      ),
      home: const HomePage(),
    ),
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => maybeShowWelcome(context));
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

  Future<void> _scanBill() async {
    if (bill.people.isEmpty) {
      _snack('أضف الأشخاص أولاً');
      return;
    }
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('مسح ضوئي للفاتورة (الأدق)'),
              subtitle: const Text('يقصّ الورقة ويعدّل الصورة تلقائياً'),
              onTap: () => Navigator.pop(ctx, 'scan'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('اختر من الصور'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    List<ScanRow>? rows;
    double? totalGuess;
    var mlLines = <String>[];
    var progressShown = false;
    try {
      String imagePath;
      if (source == 'scan') {
        final pics = await CunningDocumentScanner.getPictures(noOfPages: 1);
        if (pics == null || pics.isEmpty) return;
        imagePath = pics.first;
      } else {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
          maxWidth: 1800,
        );
        if (picked == null) return;
        imagePath = picked.path;
      }
      if (!mounted) return;
      progressShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      final path = await _downscale(imagePath);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final result =
            await recognizer.processImage(InputImage.fromFilePath(path));
        final lines = [
          for (final b in result.blocks)
            for (final l in b.lines) l.text
        ];
        mlLines = lines;
        rows = parseReceipt(lines);
        totalGuess = guessTotal(lines);
      } finally {
        await recognizer.close();
      }
      // قراءة عربية بـ Tesseract (تقرأ الأسماء العربية)؛ إن فشلت نكتفي بـ ML Kit
      try {
        final text = await FlutterTesseractOcr.extractText(
          path,
          language: 'ara+eng',
          args: {'psm': '4'},
        );
        final tl = text.split('\n');
        final tRows = parseTesseract(tl);
        if (tRows.isNotEmpty) rows = tRows;
        totalGuess = guessTotal([...mlLines, ...tl]) ?? totalGuess;
      } catch (_) {}
    } catch (_) {
      rows = null;
    } finally {
      if (progressShown && mounted) Navigator.of(context).pop();
    }
    if (!mounted) return;
    final found = rows;
    if (found == null) {
      _snack('تعذّرت قراءة الصورة، جرّب صورة أوضح');
      return;
    }
    if (found.isEmpty && totalGuess == null) {
      _snack('لم أجد أسعاراً واضحة، جرّب صورة أوضح أو أضف البنود يدوياً');
      return;
    }
    final accepted = await showDialog<List<ScanRow>>(
      context: context,
      builder: (_) => _ScanReviewDialog(rows: found, total: totalGuess),
    );
    if (accepted == null || accepted.isEmpty) return;
    for (final r in accepted) {
      bill.addItem(r.name, r.price);
    }
    if (!mounted) return;
    _snack('أُضيف ${accepted.length} بند من الفاتورة');
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
          appBar: AppBar(
            title: const Text('قسّمها'),
            actions: [
              IconButton(
                tooltip: 'المزيد',
                icon: const Icon(Icons.apps_rounded),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MorePage(bill: bill),
                  ),
                ),
              ),
            ],
          ),
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
              OutlinedButton.icon(
                onPressed: _scanBill,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('امسح فاتورة بالكاميرا'),
              ),
              const SizedBox(height: 8),
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
                        if (bill.items.any((i) => i.eaters.isNotEmpty)) ...[
                          const Text(
                            'ما تم تقسيمه',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: green,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (final i in bill.items)
                            if (i.eaters.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        i.name,
                                        style: const TextStyle(
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${fmt(i.price)} $kCurrency',
                                      style: const TextStyle(
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          if (bill.extraPercent > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '+ خدمة / بقشيش ${bill.extraPercent.round()}%',
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ),
                          const Divider(height: 24),
                          const Text(
                            'حصة كل شخص',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: green,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
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

// ───────────────────── مسح الفاتورة بالكاميرا ─────────────────────

/// يصغّر الصورة الكبيرة (مثل ناتج الماسح) لتسريع القراءة.
Future<String> _downscale(String path, {int maxWidth = 1800}) async {
  try {
    final bytes = await File(path).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    if (desc.width <= maxWidth) {
      desc.dispose();
      buffer.dispose();
      return path;
    }
    final codec = await desc.instantiateCodec(targetWidth: maxWidth);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    desc.dispose();
    buffer.dispose();
    if (data == null) return path;
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/scan_small.png');
    await out.writeAsBytes(data.buffer.asUint8List());
    return out.path;
  } catch (_) {
    return path;
  }
}

class ScanRow {
  ScanRow(this.name, this.price);
  String name;
  double price;
}

final RegExp _numRe =
    RegExp(r'\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:[.,]\d+)?');
final RegExp _skipRe = RegExp(
  r'total|subtotal|tax|vat|change|cash|balance|amount|visa|master|card|tel|phone|mob|date|time|invoice|receipt|tip|discount|qty',
  caseSensitive: false,
);

double? _toDouble(String t) {
  var s = t;
  if (s.contains(',') && s.contains('.')) {
    s = s.replaceAll(',', '');
  } else if (RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(s)) {
    s = s.replaceAll(',', '');
  } else {
    s = s.replaceAll(',', '.');
  }
  return double.tryParse(s);
}

/// يستخرج البنود المحتملة (اسم + سعر) من أسطر النص المقروء.
List<ScanRow> parseReceipt(List<String> lines) {
  final rows = <ScanRow>[];
  var lastText = '';
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final matches = _numRe.allMatches(line).toList();
    if (matches.isEmpty) {
      lastText = line;
      continue;
    }
    if (_skipRe.hasMatch(line) || line.contains(':') || line.contains('/')) {
      lastText = '';
      continue;
    }
    final m = matches.last;
    final token = m.group(0)!;
    final price = _toDouble(token);
    if (price == null || price <= 0 || price >= 100000) continue;
    final hasDecimal =
        token.contains('.') || RegExp(r',\d{1,2}$').hasMatch(token);
    if (!hasDecimal) {
      // رقم طويل بلا كسور: غالباً رقم طلب أو هاتف
      if (token.length >= 5 && !token.contains(',')) continue;
      // رقم صغير بلا كسور: غالباً كمية
      if (price < 10) continue;
    }
    var name = line
        .substring(0, m.start)
        .replaceAll(RegExp(r'[\s.,:*×=_\-]+$'), '')
        .trim();
    if (name.isEmpty || !RegExp(r'[A-Za-z؀-ۿ]').hasMatch(name)) {
      name = lastText;
    }
    lastText = '';
    rows.add(ScanRow(name.isEmpty ? 'بند ${rows.length + 1}' : name, price));
  }
  return rows;
}

final RegExp _totalKeyRe = RegExp(
  r'total|amount due|grand|المجموع|الإجمالي|الاجمالي|المطلوب|الصافي',
  caseSensitive: false,
);
final RegExp _headerRe = RegExp(r'السعر|الصنف|العدد|الكمية|البيان');
final RegExp _skipArRe = RegExp(
  r'المجموع|الإجمالي|الاجمالي|المطلوب|المدفوع|الرصيد|الضريبة|الضريبه|ضريبة|الخدمة|هاتف|عنوان|بريد|تاريخ|رقم الفاتورة|@',
);
final RegExp _letterRe = RegExp(r'[A-Za-z؀-ۿ]');

/// يحوّل الأرقام العربية/الفارسية إلى لاتينية ويحذف علامات الاتجاه.
String _normDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    var i = ar.indexOf(ch);
    if (i < 0) i = fa.indexOf(ch);
    b.write(i >= 0 ? '$i' : ch);
  }
  return b
      .toString()
      .replaceAll(RegExp('[‎‏‪-‮⁦-⁩]'), '');
}

/// اسم قصير مختلط عربي + لاتيني (مثل «oe فا»): غالباً ضجيج من عنوان الفاتورة.
bool _isNoiseName(String name) {
  final compact = name.replaceAll(' ', '');
  if (compact.length < 3) return true;
  final hasAr = RegExp(r'[؀-ۿ]').hasMatch(name);
  final hasEn = RegExp(r'[A-Za-z]').hasMatch(name);
  return name.split(' ').length >= 2 && hasAr && hasEn && name.length <= 8;
}

/// «2 0 0 0» → «2000» (أرقام مفصولة بمسافات في سطر الإجمالي).
String _joinSpacedDigits(String s) => s.replaceAllMapped(
      RegExp(r'(?<!\d)\d(?: \d){2,}(?!\d)'),
      (m) => m.group(0)!.replaceAll(' ', ''),
    );

/// يستخرج البنود من نص Tesseract: «[رقم] الاسم السعر العدد المجموع».
List<ScanRow> parseTesseract(List<String> rawLines) {
  final rows = <ScanRow>[];
  for (final raw in rawLines) {
    final line = _normDigits(raw).trim();
    if (line.isEmpty) continue;
    if (_skipRe.hasMatch(line) || _skipArRe.hasMatch(line)) continue;
    if (line.contains(':') || line.contains('/') || _dateRe.hasMatch(line)) {
      continue;
    }
    final ms = _numRe.allMatches(line).toList();
    if (ms.isEmpty) continue;
    var nums = [for (final m in ms) _toDouble(m.group(0)!)]
        .whereType<double>()
        .toList();
    if (nums.isEmpty) continue;
    final name = line
        .replaceAll(_numRe, ' ')
        .replaceAll(RegExp(r'[|_=*×@~\[\]{}()<>]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (!_letterRe.hasMatch(name)) continue;
    if (_isNoiseName(name)) continue;
    // رقم الصف (أو الكمية) في أول السطر
    if (nums.length >= 2 && ms.first.start == 0) nums = nums.sublist(1);
    double amount;
    if (nums.length >= 3 && nums.last == 0) {
      amount = nums[0] * nums[1]; // السعر × العدد حين يكون المجموع صفراً
    } else {
      amount = nums.last;
    }
    if (amount <= 0 || amount >= 100000) continue;
    rows.add(ScanRow(name, amount));
  }
  return rows;
}
final RegExp _subTotalRe = RegExp(r'sub\s*-?\s*total', caseSensitive: false);
final RegExp _dateRe = RegExp(r'\d{1,4}[-.]\d{1,2}[-.]\d{1,4}');

/// يخمّن إجمالي الفاتورة: من سطر فيه «Total»، وإلا أكبر رقم معقول.
double? guessTotal(List<String> rawLines) {
  final lines = [for (final l in rawLines) _normDigits(l)];
  final keyed = <double>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!_totalKeyRe.hasMatch(line) ||
        _subTotalRe.hasMatch(line) ||
        _headerRe.hasMatch(line)) {
      continue;
    }
    var ms = _numRe.allMatches(_joinSpacedDigits(line)).toList();
    if (ms.isEmpty && i + 1 < lines.length) {
      ms = _numRe.allMatches(lines[i + 1]).toList();
    }
    if (ms.isEmpty) continue;
    final v = _toDouble(ms.last.group(0)!);
    if (v != null && v > 0 && v < 10000000) keyed.add(v);
  }
  if (keyed.isNotEmpty) return keyed.reduce(math.max);

  // لا يوجد سطر «Total»: نأخذ أكبر رقم معقول، ونستبعد ما يشبه رقم الطلب
  // (رقم طويل بلا كسور ظهر مرة واحدة) وأسطر التواريخ.
  final count = <double, int>{};
  final plain = <double, bool>{};
  for (final line in lines) {
    if (line.contains(':') || line.contains('/') || _dateRe.hasMatch(line)) {
      continue;
    }
    for (final m in _numRe.allMatches(line)) {
      final token = m.group(0)!;
      final v = _toDouble(token);
      if (v != null && v >= 10 && v < 10000000) {
        count[v] = (count[v] ?? 0) + 1;
        if (RegExp(r'^\d+$').hasMatch(token)) plain[v] = true;
      }
    }
  }
  final sorted = count.keys.toList()..sort((a, b) => b.compareTo(a));
  for (final v in sorted) {
    final looksLikeId = (plain[v] ?? false) && v >= 10000 && count[v] == 1;
    if (!looksLikeId) return v;
  }
  return null;
}

class _ScanReviewDialog extends StatefulWidget {
  const _ScanReviewDialog({required this.rows, this.total});
  final List<ScanRow> rows;
  final double? total;

  @override
  State<_ScanReviewDialog> createState() => _ScanReviewDialogState();
}

class _ScanReviewDialogState extends State<_ScanReviewDialog> {
  late final List<bool> _on = List<bool>.filled(widget.rows.length, true);
  late final List<TextEditingController> _names = [
    for (final r in widget.rows) TextEditingController(text: r.name)
  ];
  late final List<TextEditingController> _prices = [
    for (final r in widget.rows) TextEditingController(text: fmt(r.price))
  ];

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    for (final c in _prices) {
      c.dispose();
    }
    super.dispose();
  }

  double get _sum {
    var s = 0.0;
    for (var i = 0; i < widget.rows.length; i++) {
      if (!_on[i]) continue;
      final p = parsePrice(_prices[i].text);
      if (p != null && p > 0) s += p;
    }
    return s;
  }

  void _setAll(bool v) {
    setState(() {
      for (var i = 0; i < _on.length; i++) {
        _on[i] = v;
      }
    });
  }

  void _confirm() {
    final out = <ScanRow>[];
    for (var i = 0; i < widget.rows.length; i++) {
      if (!_on[i]) continue;
      final p = parsePrice(_prices[i].text);
      if (p == null || p <= 0) continue;
      final n = _names[i].text.trim();
      out.add(ScanRow(n.isEmpty ? 'بند' : n, p));
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('البنود التي وجدتها'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'القراءة قد لا تكون دقيقة. راجع الأسماء والأسعار وألغِ ما لا يلزم.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (widget.total != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الإجمالي المقترح: ${fmt(widget.total!)} $kCurrency',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => Navigator.pop(
                        context,
                        [ScanRow('الفاتورة', widget.total!)],
                      ),
                      child: const Text('قسّم الإجمالي فقط'),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              TextButton(
                onPressed: () => _setAll(true),
                child: const Text('تحديد الكل'),
              ),
              TextButton(
                onPressed: () => _setAll(false),
                child: const Text('إلغاء الكل'),
              ),
            ],
          ),
          Text(
            'مجموع المحدد: ${fmt(_sum)} $kCurrency',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < widget.rows.length; i++)
            Row(
              children: [
                Checkbox(
                  value: _on[i],
                  onChanged: (v) => setState(() => _on[i] = v ?? false),
                ),
                Expanded(
                  child: TextField(
                    controller: _names[i],
                    decoration: const InputDecoration(isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _prices[i],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(isDense: true),
                  ),
                ),
              ],
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('أضف المحدد'),
        ),
      ],
    );
  }
}

// يمنع تحذير الاستيراد غير المستخدم لو تغيّر الكود لاحقاً.
// ignore: unused_element
double _unusedMax(double a, double b) => math.max(a, b);
