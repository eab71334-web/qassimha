import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extras2.dart';
import 'extras4.dart';
import 'extras5.dart';
import 'main.dart';

// ═════════════════════════ إعدادات عامة (يقرؤها main.dart) ═════════════════════════

final ValueNotifier<ThemeMode> gThemeMode = ValueNotifier(ThemeMode.system);
final ValueNotifier<double> gTextScale = ValueNotifier(1.0);

/// بيانات استلام الحوالة، تُضاف لرسائل التذكير.
String gPayInfo = '';
String gMyName = '';
String gFavCurrency = 'USD';

Future<void> loadAppSettings() async {
  try {
    final sp = await SharedPreferences.getInstance();
    final t = sp.getString('qassimha_theme');
    gThemeMode.value = t == 'light'
        ? ThemeMode.light
        : t == 'dark'
            ? ThemeMode.dark
            : ThemeMode.system;
    gTextScale.value = sp.getDouble('qassimha_scale') ?? 1.0;
    gPayInfo = sp.getString('qassimha_payinfo') ?? '';
    gMyName = sp.getString('qassimha_myname') ?? '';
    gFavCurrency = sp.getString('qassimha_favcur') ?? 'USD';
    gPinHash.value = sp.getString('qassimha_pin');
  } catch (_) {}
}


/// قائمة العملات للاختيار (رمز، اسم).
const List<List<String>> kCurrencies = [
  ['USD', 'دولار أمريكي'],
  ['EUR', 'يورو'],
  ['GBP', 'جنيه إسترليني'],
  ['TND', 'دينار تونسي'],
  ['EGP', 'جنيه مصري'],
  ['TRY', 'ليرة تركية'],
  ['AED', 'درهم إماراتي'],
  ['SAR', 'ريال سعودي'],
  ['QAR', 'ريال قطري'],
  ['KWD', 'دينار كويتي'],
  ['BHD', 'دينار بحريني'],
  ['OMR', 'ريال عماني'],
  ['JOD', 'دينار أردني'],
  ['LBP', 'ليرة لبنانية'],
  ['MAD', 'درهم مغربي'],
  ['DZD', 'دينار جزائري'],
  ['SDG', 'جنيه سوداني'],
  ['CNY', 'يوان صيني'],
  ['RUB', 'روبل روسي'],
  ['CAD', 'دولار كندي'],
  ['AUD', 'دولار أسترالي'],
  ['CHF', 'فرنك سويسري'],
  ['JPY', 'ين ياباني'],
  ['INR', 'روبية هندية'],
  ['MYR', 'رينغيت ماليزي'],
  ['SEK', 'كرونة سويدية'],
];

String currencyLabel(String code) {
  for (final c in kCurrencies) {
    if (c[0] == code) return '${c[1]} ($code)';
  }
  return code;
}

/// نافذة اختيار عملة من قائمة (مع بحث).
Future<String?> pickCurrency(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      var q = '';
      return StatefulBuilder(
        builder: (ctx, setS) {
          final list = kCurrencies
              .where((c) => c[0].toLowerCase().contains(q.toLowerCase()) || c[1].contains(q))
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      onChanged: (v) => setS(() => q = v.trim()),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'ابحث عن عملة',
                        isDense: true,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final c in list)
                          ListTile(
                            title: Text(c[1]),
                            subtitle: Text(c[0]),
                            trailing: c[0] == current ? const Icon(Icons.check) : null,
                            onTap: () => Navigator.pop(ctx, c[0]),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// حصص الفاتورة الحالية: اسم الشخص -> المبلغ (الأشخاص ذوو الحصص فقط).
Map<String, double> _currentShares(Bill bill) {
  final t = bill.totals;
  final m = <String, double>{};
  for (final p in bill.people) {
    final v = t[p.id] ?? 0;
    if (v > 0) m[p.name] = v;
  }
  return m;
}

// ═════════════════════════ الإعدادات والنسخ الاحتياطي ═════════════════════════

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final pay = TextEditingController(text: gPayInfo);
  final myName = TextEditingController(text: gMyName);
  String favCur = gFavCurrency;
  final restore = TextEditingController();

  @override
  void dispose() {
    pay.dispose();
    myName.dispose();
    restore.dispose();
    super.dispose();
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _setTheme(ThemeMode m) async {
    gThemeMode.value = m;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        'qassimha_theme',
        m == ThemeMode.light
            ? 'light'
            : m == ThemeMode.dark
                ? 'dark'
                : 'system');
  }

  Future<void> _setScale(double v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble('qassimha_scale', v);
  }

  Future<void> _savePay() async {
    gPayInfo = pay.text.trim();
    gMyName = myName.text.trim();
    gFavCurrency = favCur;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('qassimha_payinfo', gPayInfo);
    await sp.setString('qassimha_myname', gMyName);
    await sp.setString('qassimha_favcur', gFavCurrency);
    _snack('تم الحفظ');
  }

  Future<void> _backup() async {
    final sp = await SharedPreferences.getInstance();
    final data = <String, String>{};
    for (final k in sp.getKeys()) {
      if (!k.startsWith('qassimha_')) continue;
      final v = sp.get(k);
      if (v is String) data[k] = v;
    }
    final code = 'QSMBK1:${base64Url.encode(utf8.encode(jsonEncode(data)))}';
    await sp.setString('qassimha_last_backup', DateTime.now().toIso8601String());
    if (!mounted) return;
    await shareText(context, code);
  }

  Future<void> _restore() async {
    try {
      var raw = restore.text.trim();
      if (!raw.startsWith('QSMBK1:')) throw const FormatException('bad');
      raw = raw.substring(7);
      final data = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(base64Url.decode(raw))) as Map);
      final sp = await SharedPreferences.getInstance();
      for (final e in data.entries) {
        if (e.key.startsWith('qassimha_') && e.value is String) {
          await sp.setString(e.key, e.value as String);
        }
      }
      _snack('تم الاستيراد. أغلق التطبيق وافتحه من جديد لتظهر البيانات');
    } catch (_) {
      _snack('الكود غير صالح');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات والنسخ الاحتياطي')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('المظهر', style: tt),
          const SizedBox(height: 8),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: gThemeMode,
            builder: (context, m, _) => SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('تلقائي')),
                ButtonSegment(value: ThemeMode.light, label: Text('نهاري')),
                ButtonSegment(value: ThemeMode.dark, label: Text('ليلي')),
              ],
              selected: {m},
              onSelectionChanged: (s) => _setTheme(s.first),
            ),
          ),
          const SizedBox(height: 16),
          Text('حجم الخط', style: tt),
          ValueListenableBuilder<double>(
            valueListenable: gTextScale,
            builder: (context, v, _) => Slider(
              min: 0.9,
              max: 1.5,
              divisions: 6,
              value: math.min(1.5, math.max(0.9, v)),
              label: '${(v * 100).round()}%',
              onChanged: (x) => gTextScale.value = x,
              onChangeEnd: _setScale,
            ),
          ),
          const Divider(height: 32),
          Text('ملفي الشخصي', style: tt),
          const SizedBox(height: 4),
          const Text('تُملأ تلقائياً في رسائل التذكير وصفحة العملات',
              style: TextStyle(fontSize: 12)),
          TextField(
            controller: myName,
            decoration: const InputDecoration(labelText: 'اسمك'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('عملتك المفضلة للتحويل'),
            subtitle: Text(currencyLabel(favCur)),
            trailing: const Icon(Icons.arrow_drop_down),
            onTap: () async {
              final c = await pickCurrency(context, favCur);
              if (c != null) setState(() => favCur = c);
            },
          ),
          TextField(
            controller: pay,
            decoration: const InputDecoration(
              labelText: 'بيانات استلام الحوالة (رقم حسابك أو محفظتك)',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(onPressed: _savePay, child: const Text('حفظ')),
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.help_outline),
            title: const Text('شرح التطبيق'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const WelcomePage()),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: const Text('قفل التطبيق برمز PIN'),
            subtitle: const Text('يحمي ديونك وحساباتك'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PinSettingsPage()),
            ),
          ),
          const Divider(height: 32),
          Text('نسخ احتياطي', style: tt),
          const SizedBox(height: 4),
          const Text(
            'يُنشئ كوداً فيه كل بياناتك (فواتير، ديون، رحلات…). أرسله لنفسك واحتفظ به.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _backup,
            icon: const Icon(Icons.upload_outlined),
            label: const Text('إنشاء نسخة احتياطية'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: restore,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'ألصق كود النسخة هنا للاستعادة',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: _restore,
              icon: const Icon(Icons.download_outlined),
              label: const Text('استعادة'),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════ كود مشاركة الحساب ═════════════════════════

class ShareCodePage extends StatefulWidget {
  const ShareCodePage({super.key, required this.bill});
  final Bill bill;

  @override
  State<ShareCodePage> createState() => _ShareCodePageState();
}

class _ShareCodePageState extends State<ShareCodePage> {
  final title = TextEditingController();
  final paste = TextEditingController();
  Map<String, dynamic>? opened;
  String? mine;

  @override
  void dispose() {
    title.dispose();
    paste.dispose();
    super.dispose();
  }

  String? _code() {
    final bill = widget.bill;
    final shares = _currentShares(bill);
    if (shares.isEmpty) return null;
    final payload = {
      't': title.text.trim(),
      'd': DateTime.now().toIso8601String(),
      'l': shares,
      'i': [
        for (final i in bill.items) [i.name, i.price]
      ],
    };
    return 'QSM1:${base64Url.encode(utf8.encode(jsonEncode(payload)))}';
  }

  void _open() {
    try {
      var raw = paste.text.trim();
      final at = raw.indexOf('QSM1:');
      if (at < 0) throw const FormatException('bad');
      raw = raw.substring(at + 5).split(RegExp(r'\s')).first;
      final m = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(base64Url.decode(raw))) as Map);
      setState(() {
        opened = m;
        mine = null;
      });
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('الكود غير صالح')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme.titleMedium;
    final cs = Theme.of(context).colorScheme;
    final code = _code();
    final o = opened;
    return Scaffold(
      appBar: AppBar(title: const Text('كود الحساب')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('أرسل حسابك لأصدقائك', style: tt),
          const SizedBox(height: 4),
          const Text(
            'يولّد كوداً للفاتورة الحالية. صاحبك يلصقه عنده في التطبيق ويرى حصته.',
            style: TextStyle(fontSize: 12),
          ),
          TextField(
            controller: title,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'عنوان الحساب (اختياري)'),
          ),
          const SizedBox(height: 8),
          if (code == null)
            const Text('لا توجد فاتورة حالية بحصص. أضف أشخاصاً وبنوداً أولاً.')
          else
            FilledButton.icon(
              onPressed: () => shareText(
                context,
                '🧾 حسابنا${title.text.trim().isEmpty ? '' : ' (${title.text.trim()})'}\n'
                'افتح «قسّمها» ← المزيد ← كود الحساب، وألصق الكود لترى حصتك:\n\n$code\n\n$kTagline',
              ),
              icon: const Icon(Icons.share),
              label: const Text('شارك الكود'),
            ),
          const Divider(height: 32),
          Text('استلمت كود حساب؟', style: tt),
          TextField(
            controller: paste,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'ألصق الكود هنا',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.lock_open),
              label: const Text('افتح الحساب'),
            ),
          ),
          if (o != null) ...[
            const SizedBox(height: 16),
            Text(
              (o['t'] ?? '').toString().isEmpty ? 'الحساب' : o['t'].toString(),
              style: tt,
            ),
            const SizedBox(height: 4),
            const Text('اضغط على اسمك لتظهر حصتك', style: TextStyle(fontSize: 12)),
            for (final e in Map<String, dynamic>.from(o['l'] as Map).entries)
              Card(
                color: mine == e.key ? cs.primaryContainer : null,
                child: ListTile(
                  title: Text(e.key),
                  trailing: Text('${fmt((e.value as num).toDouble())} $kCurrency'),
                  onTap: () => setState(() => mine = e.key),
                ),
              ),
            if (mine != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'حصتك يا $mine: ${fmt((Map<String, dynamic>.from(o['l'] as Map)[mine] as num).toDouble())} $kCurrency',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            if ((o['i'] as List? ?? []).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('البنود', style: tt),
              for (final it in (o['i'] as List))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text((it as List)[0].toString()),
                  trailing: Text('${fmt((it[1] as num).toDouble())} $kCurrency'),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════ مجموعات الأصدقاء وقوالب ═════════════════════════

class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key, required this.bill});
  final Bill bill;

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  final store = JsonStore('qassimha_groups_v1');
  static const templates = ['غداء', 'قهوة', 'سفرة', 'كهرباء', 'العائلة', 'شلة الأصدقاء'];

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

  Future<void> _new([String initial = '']) async {
    final r = await askForm(
      context,
      title: 'مجموعة جديدة',
      nameLabel: 'اسم المجموعة',
      membersLabel: 'الأعضاء (كل اسم في سطر)',
      initialName: initial,
    );
    if (r == null) return;
    store.add({
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'name': r['name'],
      'members': r['members'],
    });
  }

  void _apply(Map<String, dynamic> g) {
    final have = widget.bill.people.map((p) => p.name).toSet();
    var added = 0;
    for (final m in (g['members'] as List)) {
      final n = m.toString();
      if (!have.contains(n)) {
        widget.bill.addPerson(n);
        added++;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('أُضيف $added شخص للفاتورة الحالية')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مجموعات وقوالب')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _new(),
        icon: const Icon(Icons.add),
        label: const Text('مجموعة جديدة'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            const Text('ابدأ بقالب (تكتب أسماء أشخاصك مرة واحدة فقط):'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final t in templates)
                  ActionChip(label: Text(t), onPressed: () => _new(t)),
              ],
            ),
            const SizedBox(height: 16),
            if (store.items.isEmpty) const Text('لا توجد مجموعات محفوظة بعد'),
            for (final g in store.items)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.group_outlined),
                  title: Text(g['name'].toString()),
                  subtitle: Text((g['members'] as List).join('، ')),
                  onTap: () => _apply(g),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => store.removeId(g['id'].toString()),
                  ),
                ),
              ),
            if (store.items.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'اضغط على المجموعة لإضافة أعضائها للفاتورة الحالية.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════ من يدفع؟ (قرعة) ═════════════════════════

class WheelPage extends StatefulWidget {
  const WheelPage({super.key, required this.bill});
  final Bill bill;

  @override
  State<WheelPage> createState() => _WheelPageState();
}

class _WheelPageState extends State<WheelPage> {
  late final List<String> names =
      widget.bill.people.map((p) => p.name).toList();
  int? hi;
  String? winner;
  bool spinning = false;

  Future<void> _spin() async {
    if (names.length < 2 || spinning) return;
    setState(() {
      spinning = true;
      winner = null;
    });
    final rnd = math.Random();
    final n = names.length;
    final start = hi ?? 0;
    final target = rnd.nextInt(n);
    final steps = n * 3 + ((target - start) % n + n) % n + 8;
    for (var i = 1; i <= steps; i++) {
      if (!mounted) return;
      setState(() => hi = (start + i) % n);
      HapticFeedback.selectionClick();
      final f = i / steps;
      await Future<void>.delayed(
          Duration(milliseconds: (45 + f * f * 320).round()));
    }
    if (!mounted) return;
    setState(() {
      spinning = false;
      winner = names[hi ?? 0];
    });
  }

  Future<void> _add() async {
    final n = await askText(context, 'إضافة اسم', 'الاسم');
    if (n != null && !names.contains(n)) setState(() => names.add(n));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('من يدفع هذه المرة؟')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < names.length; i++)
                Chip(
                  label: Text(names[i], style: const TextStyle(fontSize: 16)),
                  backgroundColor: hi == i ? cs.primary : null,
                  labelStyle:
                      hi == i ? TextStyle(color: cs.onPrimary, fontSize: 16) : null,
                  onDeleted: spinning
                      ? null
                      : () => setState(() {
                            names.removeAt(i);
                            hi = null;
                            winner = null;
                          }),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('اسم'),
                onPressed: spinning ? null : _add,
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: names.length < 2 || spinning ? null : _spin,
            icon: const Icon(Icons.casino_outlined),
            label: const Text('لفّ القرعة'),
          ),
          if (names.length < 2)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('أضف اسمين على الأقل'),
            ),
          if (winner != null) ...[
            const SizedBox(height: 24),
            Center(
              child: Text(
                '🎉 $winner يدفع!',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () => shareText(
                  context,
                  '🎲 القرعة اختارت $winner يدفع هذه المرة! 😄\n$kTagline',
                ),
                icon: const Icon(Icons.share, size: 18),
                label: const Text('شارك النتيجة'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════ عملة أخرى ═════════════════════════

class CurrencyPage extends StatefulWidget {
  const CurrencyPage({super.key, required this.bill});
  final Bill bill;

  @override
  State<CurrencyPage> createState() => _CurrencyPageState();
}

class _CurrencyPageState extends State<CurrencyPage> {
  String code = gFavCurrency;
  final rate = TextEditingController();

  @override
  void dispose() {
    rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shares = _currentShares(widget.bill);
    final r = parsePrice(rate.text);
    final c = code;
    final ok = r != null && r > 0;
    String conv(double v) => ok ? '${fmt(v / r!)} $c' : '—';
    return Scaffold(
      appBar: AppBar(title: const Text('عملة أخرى')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('العملة'),
            subtitle: Text(currencyLabel(code)),
            trailing: const Icon(Icons.arrow_drop_down),
            onTap: () async {
              final p = await pickCurrency(context, code);
              if (p != null) setState(() => code = p);
            },
          ),
          TextField(
            controller: rate,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'سعر الصرف: 1 $c = كم $kCurrency؟',
            ),
          ),
          const SizedBox(height: 16),
          if (shares.isEmpty)
            const Text('لا توجد فاتورة حالية بحصص.')
          else ...[
            for (final e in shares.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.key),
                subtitle: Text('${fmt(e.value)} $kCurrency'),
                trailing: Text(
                  conv(e.value),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('الإجمالي'),
              subtitle: Text(
                  '${fmt(shares.values.fold(0.0, (a, b) => a + b))} $kCurrency'),
              trailing: Text(
                conv(shares.values.fold(0.0, (a, b) => a + b)),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (ok)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => shareText(
                    context,
                    [
                      '🌍 الحساب بعملتين (1 $c = ${fmt(r!)} $kCurrency)',
                      for (final e in shares.entries)
                        '• ${e.key}: ${fmt(e.value)} $kCurrency = ${conv(e.value)}',
                      kTagline,
                    ].join('\n'),
                  ),
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('شارك'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════ توزيع الإكرامية ═════════════════════════

class TipPage extends StatefulWidget {
  const TipPage({super.key, required this.bill});
  final Bill bill;

  @override
  State<TipPage> createState() => _TipPageState();
}

class _TipPageState extends State<TipPage> {
  final tip = TextEditingController();
  bool proportional = true;

  @override
  void dispose() {
    tip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shares = _currentShares(widget.bill);
    final total = shares.values.fold(0.0, (a, b) => a + b);
    final t = parsePrice(tip.text) ?? 0;
    final tipOf = <String, double>{
      for (final e in shares.entries)
        e.key: shares.isEmpty
            ? 0.0
            : proportional
                ? (total <= 0 ? 0.0 : t * e.value / total)
                : t / shares.length,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('توزيع الإكرامية')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'اكتب مبلغ الإكرامية (بقشيش) كاملاً، ويُوزَّع على الأشخاص.',
          ),
          TextField(
            controller: tip,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'الإكرامية ($kCurrency)'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('حسب ما أكل كل واحد')),
              ButtonSegment(value: false, label: Text('بالتساوي')),
            ],
            selected: {proportional},
            onSelectionChanged: (s) => setState(() => proportional = s.first),
          ),
          const SizedBox(height: 16),
          if (shares.isEmpty)
            const Text('لا توجد فاتورة حالية بحصص.')
          else ...[
            for (final e in shares.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.key),
                subtitle: Text(
                    'حصته ${fmt(e.value)} + إكرامية ${fmt(tipOf[e.key] ?? 0)}'),
                trailing: Text(
                  '${fmt(e.value + (tipOf[e.key] ?? 0))} $kCurrency',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => shareText(
                  context,
                  [
                    '💸 الحساب مع الإكرامية (${fmt(t)} $kCurrency)',
                    for (final e in shares.entries)
                      '• ${e.key}: ${fmt(e.value + (tipOf[e.key] ?? 0))} $kCurrency',
                    kTagline,
                  ].join('\n'),
                ),
                icon: const Icon(Icons.share, size: 18),
                label: const Text('شارك'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════ ملخص أسبوعي ═════════════════════════

class WeeklyPage extends StatefulWidget {
  const WeeklyPage({super.key, required this.bill});
  final Bill bill;

  @override
  State<WeeklyPage> createState() => _WeeklyPageState();
}

class _WeeklyPageState extends State<WeeklyPage> {
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

  String _text() {
    final since = DateTime.now().subtract(const Duration(days: 7));
    var total = 0.0;
    var count = 0;
    final payers = <String, double>{};
    final places = <String, double>{};
    for (final b in widget.bill.saved) {
      if (b.date.isAfter(since)) {
        total += b.total;
        count++;
        places[b.title] = (places[b.title] ?? 0) + b.total;
      }
    }
    for (final t in trips.items) {
      final rawEx = t['expenses'] as List? ?? [];
      for (final e0 in rawEx) {
        final e = Map<String, dynamic>.from(e0 as Map);
        final d = DateTime.tryParse(e['date'].toString());
        if (d == null || !d.isAfter(since)) continue;
        final a = (e['amount'] as num).toDouble();
        total += a;
        count++;
        places[t['name'].toString()] = (places[t['name'].toString()] ?? 0) + a;
        payers[e['payer'].toString()] = (payers[e['payer'].toString()] ?? 0) + a;
      }
    }
    if (count == 0) return '';
    String top(Map<String, double> m) =>
        (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
    return [
      '📊 ملخص الأسبوع',
      'صرفنا ${fmt(total)} $kCurrency في $count عملية',
      if (places.isNotEmpty) 'الأكثر إنفاقاً: ${top(places)}',
      if (payers.isNotEmpty) 'الأكثر دفعاً: ${top(payers)} 👏',
      kTagline,
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ملخص أسبوعي')),
      body: ListenableBuilder(
        listenable: trips,
        builder: (context, _) {
          final text = _text();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (text.isEmpty)
                const Text(
                    'لا توجد عمليات في آخر 7 أيام. احفظ فاتورة أو سجّل مصروف رحلة.')
              else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(text),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => shareText(context, text),
                  icon: const Icon(Icons.share),
                  label: const Text('شارك الملخص'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
