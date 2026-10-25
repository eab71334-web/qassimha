import 'package:flutter/material.dart';

import 'extras.dart';
import 'extras2.dart';
import 'extras3.dart';
import 'extras4.dart';
import 'extras5.dart';
import 'main.dart';

// ═════════════════════════ المساعد الذكي (يفهم أوامر مكتوبة بالعربية) ═════════════════════════
// يعمل بدون إنترنت: يحلّل الجملة بقواعد، ويعرض ما فهمه ويطلب تأكيدك قبل التنفيذ.

String _norm(String s) {
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
      .replaceAll(RegExp('[ً-ْـ]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي')
      .replaceAll('ء', '')
      .replaceAll('ث', 'ت')
      .replaceAll('ذ', 'د')
      .replaceAll('ظ', 'ض')
      .replaceAll('ک', 'ك')
      .replaceAll('ی', 'ي')
      .replaceAllMapped(RegExp(r'(.)\1{2,}'), (m) => m.group(1)!)
      .toLowerCase();
}

/// يختصر الحروف المكررة (دييين = دين) للمقارنة المتسامحة.
String _squash(String s) =>
    s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);

int _dist(String a, String b) {
  if (a == b) return 0;
  if ((a.length - b.length).abs() > 2) return 3;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final c = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + c].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// هل الكلمة تشبه الكلمة المفتاحية (مع تسامح مع الأخطاء الإملائية)؟
bool _close(String t, String w) {
  if (t == w) return true;
  if (_squash(t) == _squash(w)) return true;
  final m = t.length < w.length ? t.length : w.length;
  if (m < 4) return false;
  final d = _dist(t, w);
  return d <= 1 || (m >= 7 && d <= 2);
}

List<String> _tokens(String s) => s
    .replaceAll(RegExp('[؟?!؛:]'), ' ')
    .replaceAll('،', ' ')
    .replaceAll(',', ' ')
    .trim()
    .split(RegExp(r'\s+'))
    .where((e) => e.isNotEmpty)
    .toList();

const Map<String, int> _numWords = {
  'واحد': 1,
  'اثنين': 2,
  'اتنين': 2,
  'ثلاثه': 3,
  'تلاته': 3,
  'اربعه': 4,
  'خمسه': 5,
  'سته': 6,
  'سبعه': 7,
  'ثمانيه': 8,
  'تمانيه': 8,
  'تسعه': 9,
  'عشره': 10,
  'عشرين': 20,
  'ثلاثين': 30,
  'تلاتين': 30,
  'اربعين': 40,
  'خمسين': 50,
  'ستين': 60,
  'سبعين': 70,
  'ثمانين': 80,
  'تمانين': 80,
  'تسعين': 90,
  'ميه': 100,
  'مايه': 100,
  'مائه': 100,
  'ميتين': 200,
  'مئتين': 200,
  'ثلاثميه': 300,
  'تلتميه': 300,
  'اربعميه': 400,
  'ربعميه': 400,
  'خمسميه': 500,
  'الف': 1000,
  'الفين': 2000,
};

const Set<String> _stop = {
  'ضيف',
  'اضف',
  'سجل',
  'زيد',
  'اكتب',
  'اعمل',
  'انشئ',
  'سوي',
  'دين',
  'ديون',
  'عليه',
  'عليها',
  'عليهم',
  'يدين',
  'مديون',
  'مديونه',
  'عندي',
  'عنده',
  'عندها',
  'عند',
  'لدي',
  'على',
  'علي',
  'عليا',
  'عن',
  'من',
  'في',
  'الي',
  'لي',
  'ليا',
  'مبلغ',
  'قدره',
  'قيمه',
  'دينار',
  'دينارا',
  'دل',
  'د.ل',
  'ل.د',
  'فاتوره',
  'الفاتوره',
  'حساب',
  'بند',
  'شخص',
  'اشخاص',
  'اسم',
  'للفاتوره',
  'رحله',
  'مع',
  'و',
  'ب',
  'بي',
  'يا',
  'لو',
  'سمحت',
  'ممكن',
  'اريد',
  'ابي',
  'نبي',
  'نبغي',
  'ابغي',
  'هذا',
  'هذه',
  'الان',
  'كم',
  'هل',
};

const Set<String> _extraStop = {
  'سلفت',
  'اسلفت',
  'اقرضت',
  'عطيت',
  'اعطيت',
  'استلفت',
  'اقترضت',
  'سلفني',
  'اسلفني',
  'اقرضني',
  'عطاني',
  'اعطاني',
  'احذف',
  'امسح',
  'الغي',
  'شيل',
  'قسم',
  'وزع',
  'اخذت',
  'خذت',
  'سدد',
  'سددت',
  'دفع',
  'دفعت',
  'رجع',
  'رجعت',
  'ذكر',
  'ذكرني',
  'تذكير',
  'افتح',
  'اذهب',
  'روح',
  'اعرض',
  'اظهر',
  'وريني',
  'ورني',
  'قداه',
  'قداش',
  'قديش',
  'بكم',
  'شحال',
  'شقد',
  'كام',
  'ملخص',
  'مساعده',
};

const Set<String> _debtCues = {
  'دين',
  'عليه',
  'عليها',
  'عليهم',
  'يدين',
  'مديون',
  'مديونه',
  'عندي',
  'عنده',
  'عندها',
};

class _Res {
  _Res.say(this.text)
      : run = null,
        page = null;
  _Res.ask(this.text, this.run) : page = null;
  _Res.go(this.text, this.page) : run = null;
  final String text;
  final Future<String> Function()? run;
  final Widget Function()? page;
}

class _Msg {
  _Msg(this.text, {required this.user, this.run});
  final String text;
  final bool user;
  Future<String> Function()? run;
}

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key, required this.bill});
  final Bill bill;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final List<_Msg> msgs = [
    _Msg(
      'أهلاً 👋 اكتب لي ما تريد وأنا أنفّذه بعد تأكيدك.\n'
      'مثال: «ضيف دين على أحمد 50 لمحمد» أو «كم عليّ؟» أو «افتح الديون».\n'
      'اكتب «مساعدة» لرؤية كل ما أفهمه.',
      user: false,
    ),
  ];
  bool busy = false;

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  String get _me => gMyName.trim().isEmpty ? 'أنا' : gMyName.trim();

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? input.text).trim();
    if (text.isEmpty || busy) return;
    input.clear();
    setState(() {
      msgs.add(_Msg(text, user: true));
      busy = true;
    });
    _scrollDown();
    _Res res;
    try {
      res = await _understand(text);
    } catch (_) {
      res = _Res.say('ما قدرت أفهم الطلب. اكتب «مساعدة» لرؤية الأمثلة.');
    }
    if (!mounted) return;
    setState(() {
      msgs.add(_Msg(res.text, user: false, run: res.run));
      busy = false;
    });
    if (res.page != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => res.page!()),
      );
    }
    _scrollDown();
  }

  Future<void> _confirm(_Msg m) async {
    final run = m.run;
    if (run == null) return;
    setState(() => m.run = null);
    String out;
    try {
      out = await run();
    } catch (_) {
      out = 'حصل خطأ ولم يكتمل التنفيذ.';
    }
    if (!mounted) return;
    setState(() => msgs.add(_Msg(out, user: false)));
    _scrollDown();
  }

  void _cancel(_Msg m) {
    setState(() {
      m.run = null;
      msgs.add(_Msg('تم الإلغاء.', user: false));
    });
  }

  // ───────────── الفهم ─────────────

  Future<_Res> _understand(String raw) async {
    final toksRaw = _tokens(raw);
    final toks = [for (final t in toksRaw) _norm(t)];
    final joined = toks.join(' ');
    final data = await loadAppData();
    final bill = widget.bill;
    final me = _me;

    // الأسماء المعروفة
    final known = <String>{
      for (final p in bill.people) p.name,
      for (final d in data.debts) ...[d.debtor, d.creditor],
      for (final t in data.trips)
        for (final p in (t['people'] as List? ?? [])) p.toString(),
    }..remove(me);
    String? canon(String token) {
      final n = _norm(token);
      for (final k in known) {
        if (_norm(k) == n) return k;
      }
      return null;
    }

    bool has(Iterable<String> words) {
      final ws = [for (final w in words) _norm(w)];
      for (var i = 0; i < toks.length; i++) {
        final known = canon(toksRaw[i]) != null;
        for (final w in ws) {
          if (toks[i] == w || (!known && _close(toks[i], w))) return true;
        }
      }
      return false;
    }
    bool hasPart(String s) => joined.contains(s);

    // مساعدة
    if (has(const {'مساعده', 'ساعدني', 'اوامر', 'help'}) ||
        hasPart('شنو تقدر') ||
        hasPart('وش تقدر')) {
      return _Res.say(_helpText);
    }

    // مبلغ
    double? amount;
    final amountIdx = <int>{};
    for (var i = 0; i < toks.length; i++) {
      final m = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(toks[i]);
      if (m != null) {
        amount = double.tryParse(m.group(0)!.replaceAll(',', '.'));
        amountIdx.add(i);
        break;
      }
    }
    if (amount == null) {
      var sum = 0;
      var lastSmall = 0;
      for (var i = 0; i < toks.length; i++) {
        var t = toks[i];
        if ((t == 'الاف' || t == 'الاف') && sum > 0 && sum <= 10) {
          sum = sum * 1000;
          amountIdx.add(i);
          continue;
        }
        if (t.length > 2 && t.startsWith('و') && _numVal(t.substring(1)) != null) {
          t = t.substring(1);
        }
        final v = _numVal(t);
        if (v != null) {
          sum += v;
          lastSmall = v;
          amountIdx.add(i);
        }
      }
      if (sum > 0 && lastSmall >= 0) amount = sum.toDouble();
    }

    // تنقّل
    if (has(const {'افتح', 'روح', 'اذهب', 'وريني', 'اعرض', 'اظهر', 'ورني'})) {
      final pages = <List<Object>>[
        ['اقساط', 'الأقساط', () => const InstallmentsPage()],
        ['قسط', 'الأقساط', () => const InstallmentsPage()],
        ['متكرر', 'الفواتير المتكررة', () => const RecurringPage()],
        ['ديون', 'الديون', () => DebtsPage(bill: bill)],
        ['رحل', 'الرحلات', () => const TripsListPage()],
        ['جمعي', 'الجمعية', () => const JamiyaListPage()],
        ['احصائ', 'الإحصائيات', () => StatsPage(bill: bill)],
        ['بحث', 'البحث', () => SearchPage(bill: bill)],
        ['تقرير', 'التقرير الشهري', () => ReportPage(bill: bill)],
        ['ميزاني', 'الميزانية', () => BudgetPage(bill: bill)],
        ['محذوف', 'سلة المحذوفات', () => const TrashPage()],
        ['سله', 'سلة المحذوفات', () => const TrashPage()],
        ['اعدادات', 'الإعدادات', () => const SettingsPage()],
        ['صندوق', 'الصندوق المشترك', () => const FundListPage()],
        ['اصدقاء', 'سجل الأصدقاء', () => FriendsPage(bill: bill)],
        ['ايصال', 'صور الإيصالات', () => const ReceiptsPage()],
        ['تصدير', 'التصدير', () => ExportPage(bill: bill)],
        ['قرعه', 'القرعة', () => WheelPage(bill: bill)],
        ['اكثر', 'مَن يدفع أكثر', () => const LeaderboardPage()],
      ];
      for (final p in pages) {
        if (joined.contains(p[0] as String)) {
          return _Res.go('فتحت ${p[1]} ✅', p[2] as Widget Function());
        }
      }
    }

    // مجاميع الديون
    double owedToMe(String? who) {
      var s = 0.0;
      for (final d in data.debts) {
        if (d.settled || d.creditor != me) continue;
        if (who != null && d.debtor != who) continue;
        s += d.remaining;
      }
      return s;
    }

    double iOwe(String? who) {
      var s = 0.0;
      for (final d in data.debts) {
        if (d.settled || d.debtor != me) continue;
        if (who != null && d.creditor != who) continue;
        s += d.remaining;
      }
      return s;
    }

    String? mentioned;
    for (final t in toksRaw) {
      final k = canon(t);
      if (k != null) {
        mentioned = k;
        break;
      }
    }

    // استعلامات
    if (has(const {'كم', 'قداه', 'قداش', 'قديش', 'بكم', 'شحال', 'شقد', 'كام'}) ||
        has(const {'ملخص', 'وضعي', 'حالتي'})) {
      if (hasPart('صرف') || hasPart('مصروف')) {
        final now = DateTime.now();
        var total = 0.0;
        for (final b in bill.saved) {
          if (b.date.year == now.year && b.date.month == now.month) {
            total += b.total;
          }
        }
        for (final t in data.trips) {
          for (final e in (t['expenses'] as List? ?? [])) {
            final m = Map<String, dynamic>.from(e as Map);
            final d = DateTime.tryParse(m['date'].toString());
            if (d != null && d.year == now.year && d.month == now.month) {
              total += (m['amount'] as num).toDouble();
            }
          }
        }
        return _Res.say('صرفتم هذا الشهر ${fmt(total)} $kCurrency.');
      }
      if (mentioned != null) {
        final a = owedToMe(mentioned);
        final b = iOwe(mentioned);
        return _Res.say(
          '$mentioned: عليه لك ${fmt(a)} $kCurrency، وعليك له ${fmt(b)} $kCurrency.',
        );
      }
      if (has(const {'لي', 'ليا', 'عندهم', 'يدينوني'})) {
        return _Res.say('الناس مدينون لك بـ ${fmt(owedToMe(null))} $kCurrency.');
      }
      if (has(const {'علي', 'عليا', 'ادين'})) {
        return _Res.say('عليك للناس ${fmt(iOwe(null))} $kCurrency.');
      }
      final open = data.debts.where((d) => !d.settled).length;
      return _Res.say(
        'ملخصك: لك ${fmt(owedToMe(null))}، وعليك ${fmt(iOwe(null))} $kCurrency'
        '، و$open دين مفتوح.${gMyName.trim().isEmpty ? '\n(اكتب اسمك في الإعدادات ← ملفي الشخصي لحساب دقيق)' : ''}',
      );
    }

    // حاسبة القسمة: «قسّم 300 على 4»
    if (has(const {'قسم', 'وزع', 'قسمها', 'وزعها'})) {
      final nums = <double>[];
      for (final t in toks) {
        final m = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(t);
        if (m != null) {
          final v = double.tryParse(m.group(0)!.replaceAll(',', '.'));
          if (v != null) nums.add(v);
        }
      }
      if (nums.length >= 2 && nums[1] > 0) {
        return _Res.say(
          'كل واحد يدفع ${fmt(nums[0] / nums[1])} $kCurrency (${fmt(nums[0])} ÷ ${nums[1].round()}).',
        );
      }
      if (nums.length == 1 && bill.people.length >= 2) {
        return _Res.say(
          'على ${bill.people.length} أشخاص: كل واحد يدفع ${fmt(nums[0] / bill.people.length)} $kCurrency.',
        );
      }
      return _Res.say('اكتب مثلاً: «قسّم 300 على 4».');
    }

    // حذف ديون شخص
    if (has(const {'احذف', 'امسح', 'الغي', 'شيل'}) &&
        mentioned != null &&
        (hasPart('دين') || hasPart('ديون'))) {
      final who = mentioned;
      final count = data.debts
          .where((d) => !d.settled && (d.debtor == who || d.creditor == who))
          .length;
      if (count == 0) return _Res.say('ما فيه ديون مفتوحة مع $who.');
      return _Res.ask('أحذف $count دين مفتوح مع $who؟ (تجدها في سلة المحذوفات 30 يوماً)', () async {
        final book = DebtBook();
        await book.load();
        for (final d in List<DebtEntry>.of(book.entries)) {
          if (!d.settled && (d.debtor == who || d.creditor == who)) book.remove(d);
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        book.dispose();
        return 'تم الحذف ✅';
      });
    }

    // تذكير
    if (has(const {'ذكر', 'تذكير', 'ذكرني', 'ذكره', 'ذكرها'}) && mentioned != null) {
      final who = mentioned;
      final sum = owedToMe(who);
      if (sum <= 0) {
        return _Res.say('$who ما عليه شي لك حسب السجل.');
      }
      return _Res.ask('أجهّز رسالة تذكير لـ $who بمبلغ ${fmt(sum)} $kCurrency؟', () async {
        if (mounted) await shareText(context, remindText(who, sum, ''));
        return 'جهّزت الرسالة ✅';
      });
    }

    // سداد
    if (has(const {'سدد', 'سددت', 'دفع', 'دفعت', 'رجع', 'رجعت', 'خالص', 'خلص'}) &&
        mentioned != null) {
      final who = mentioned;
      final iPaid = has(const {'سددت', 'دفعت', 'رجعت'});
      final debtor = iPaid ? me : who;
      final creditor = iPaid ? who : me;
      final list = data.debts
          .where((d) => !d.settled && d.debtor == debtor && d.creditor == creditor)
          .toList();
      if (list.isEmpty) {
        return _Res.say('ما لقيت دين مفتوح من $debtor إلى $creditor.');
      }
      final total = list.fold<double>(0, (s, d) => s + d.remaining);
      final amt = amount;
      final text = amt == null || amt >= total - 0.005
          ? 'أسجّل سداد كامل: $debtor ← $creditor (${fmt(total)} $kCurrency)؟'
          : 'أسجّل دفعة ${fmt(amt)} $kCurrency من $debtor إلى $creditor (المتبقي بعدها ${fmt(total - amt)})؟';
      return _Res.ask(text, () async {
        final book = DebtBook();
        await book.load();
        var left = amt ?? total;
        for (final d in book.entries) {
          if (left <= 0.005) break;
          if (d.settled || d.debtor != debtor || d.creditor != creditor) continue;
          final pay = left < d.remaining ? left : d.remaining;
          book.addPayment(d, pay);
          left -= pay;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
        book.dispose();
        return 'تم تسجيل السداد ✅';
      });
    }

    // رحلة جديدة
    if (hasPart('رحله') && has(const {'ضيف', 'اضف', 'سجل', 'اعمل', 'انشئ', 'سوي'})) {
      final iWith = toks.indexOf('مع');
      final nameEnd = iWith < 0 ? toksRaw.length : iWith;
      final iTrip = toks.indexWhere((t) => t.contains('رحله'));
      final name = toksRaw
          .sublist(iTrip + 1 > nameEnd ? nameEnd : (iTrip < 0 ? 0 : iTrip + 1), nameEnd)
          .join(' ')
          .trim();
      final members = <String>{
        if (gMyName.trim().isNotEmpty) gMyName.trim(),
        if (iWith >= 0)
          for (final t in toksRaw.sublist(iWith + 1))
            if (_norm(t) != 'و')
              (canon(t) ??
                  (t.startsWith('و') && t.length > 3 ? t.substring(1) : t)),
      }.toList();
      if (name.isEmpty || members.length < 2) {
        return _Res.say(
          'لإنشاء رحلة اكتب مثلاً: «اعمل رحلة مصيف مع أحمد ومحمد وعلي».',
        );
      }
      return _Res.ask(
        'أنشئ رحلة «$name» مع: ${members.join('، ')}؟',
        () async {
          final store = JsonStore('qassimha_trips_v1');
          await store.load();
          store.add({
            'id': DateTime.now().microsecondsSinceEpoch.toString(),
            'name': name,
            'people': members,
            'expenses': <Map<String, dynamic>>[],
          });
          await Future<void>.delayed(const Duration(milliseconds: 150));
          store.dispose();
          return 'أنشأت الرحلة ✅ (افتحها من المزيد ← الرحلات)';
        },
      );
    }

    // أسماء مرشحة (بعد حذف الكلمات العامة والأرقام)
    final cand = <String>[]; // الاسم كما كتبه المستخدم
    final marked = <String>[]; // أسماء بعد «ل» (الدائن)
    for (var i = 0; i < toksRaw.length; i++) {
      if (amountIdx.contains(i)) continue;
      final n = toks[i];
      var isName = !_isStopWord(n);
      if (!isName && !_stopN.contains(n) && canon(toksRaw[i]) != null) {
        isName = true;
      }
      // «علي» اسم شخص إذا تلاها كلمة دين
      if ((n == 'علي' || n == 'على') &&
          ((i + 1 < toks.length && _debtN.contains(toks[i + 1])) ||
              (i > 0 && (toks[i - 1] == 'علي' || toks[i - 1] == 'على')))) {
        isName = true;
      }
      if (RegExp(r'\d').hasMatch(n)) isName = false;
      if (!isName) continue;
      var t = toksRaw[i];
      final tn = toks[i];
      if (t.startsWith('لـ') && t.length > 2) {
        marked.add(canon(t.substring(2)) ?? t.substring(2));
        continue;
      }
      final k = canon(t);
      if (k == null &&
          tn.length > 3 &&
          tn.startsWith('ل') &&
          (i > 0 &&
              (_debtN.contains(toks[i - 1]) ||
                  toks[i - 1] == 'علي' ||
                  toks[i - 1] == 'على' ||
                  amountIdx.contains(i - 1) ||
                  cand.isNotEmpty))) {
        final stripped = t.substring(1);
        marked.add(canon(stripped) ?? stripped);
        continue;
      }
      if (i > 0 && t.startsWith('و') && t.length > 3 && k == null && cand.isNotEmpty) {
        t = t.substring(1);
      }
      cand.add(k ?? t);
    }

    final lent = has(const {'سلفت', 'اسلفت', 'اقرضت', 'عطيت', 'اعطيت'});
    final borrowed = has(const {
      'استلفت',
      'اقترضت',
      'سلفني',
      'اسلفني',
      'اقرضني',
      'عطاني',
      'اعطاني',
      'اخذت',
      'خذت',
    });
    final isDebt = has(_debtCues) ||
        lent ||
        borrowed ||
        (amount != null && (has(const {'لي', 'ليا'}) || marked.isNotEmpty));
    if (isDebt) {
      final amt = amount;
      if (amt == null || amt <= 0) {
        return _Res.say('ما لقيت المبلغ. مثال: «ضيف دين على أحمد 50».');
      }
      String? debtor;
      String? creditor;
      if (has(const {'لي', 'ليا'})) {
        creditor = me;
        debtor = cand.isNotEmpty ? cand.first : (marked.isNotEmpty ? marked.first : null);
      } else if (borrowed ||
          has(const {'عندي', 'لدي'}) ||
          (cand.isEmpty && marked.isNotEmpty)) {
        debtor = me;
        creditor = marked.isNotEmpty ? marked.first : (cand.isNotEmpty ? cand.first : null);
      } else if (lent) {
        creditor = me;
        debtor = cand.isNotEmpty ? cand.first : (marked.isNotEmpty ? marked.first : null);
      } else {
        debtor = cand.isNotEmpty ? cand.first : null;
        creditor = marked.isNotEmpty
            ? marked.first
            : (cand.length > 1 ? cand[1] : me);
      }
      if (debtor == null || creditor == null || debtor == creditor) {
        return _Res.say('ما فهمت مين المدين ومين الدائن. مثال: «ضيف دين على أحمد 50 لمحمد».');
      }
      final d0 = debtor;
      final c0 = creditor;
      return _Res.ask(
        'أسجّل دين: $d0 ← $c0 بمبلغ ${fmt(amt)} $kCurrency؟\n($d0 يدفع لـ $c0)',
        () async {
          final book = DebtBook();
          await book.load();
          book.add(DebtEntry(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            debtor: d0,
            creditor: c0,
            amount: amt,
            note: '',
            date: DateTime.now(),
          ));
          await Future<void>.delayed(const Duration(milliseconds: 150));
          book.dispose();
          return 'تم تسجيل الدين ✅';
        },
      );
    }

    // بند في الفاتورة الحالية
    if ((has(const {'بند'}) || has(const {'فاتوره', 'الفاتوره', 'للفاتوره'})) &&
        amount != null &&
        amount > 0) {
      final price = amount;
      final name = [...cand, ...marked].join(' ').trim();
      final label = name.isEmpty ? 'بند' : name;
      return _Res.ask(
        'أضيف بند «$label» بسعر ${fmt(price)} $kCurrency للفاتورة الحالية؟',
        () async {
          bill.addItem(label, price);
          return 'أضفت البند ✅ (يظهر في الشاشة الرئيسية)';
        },
      );
    }

    // أشخاص في الفاتورة الحالية
    if (has(const {'ضيف', 'اضف', 'زيد', 'سجل'}) && amount == null && cand.isNotEmpty) {
      final names = [...cand];
      return _Res.ask(
        'أضيف إلى الفاتورة الحالية: ${names.join('، ')}؟',
        () async {
          final have = bill.people.map((p) => p.name).toSet();
          var n = 0;
          for (final p in names) {
            if (!have.contains(p)) {
              bill.addPerson(p);
              n++;
            }
          }
          return 'أضفت $n شخص ✅';
        },
      );
    }

    return _Res.say(
      'ما فهمت الطلب 🤔 جرّب مثلاً:\n'
      '• ضيف دين على أحمد 50 لمحمد\n'
      '• كم عليّ؟  •  كم لي؟\n'
      '• افتح الإحصائيات\n'
      'أو اكتب «مساعدة» لكل الأمثلة.',
    );
  }

  static const String _helpText = 'أفهم هذه الأوامر (بالعربية):\n'
      '💸 الديون: «ضيف دين على أحمد 50 لمحمد» · «أحمد عليه 30» · «عندي لمحمد 20»\n'
      '✅ السداد: «أحمد سدد 20» · «أحمد سدد» (كامل) · «سددت لمحمد»\n'
      '❓ الأسئلة: «كم عليّ؟» · «كم لي؟» · «كم على أحمد؟» · «كم صرفنا هذا الشهر؟» · «ملخص»\n'
      '🤝 السلف: «سلّفت أحمد 100» · «استلفت من محمد 50» · «احذف ديون أحمد»\n'
      '🧮 القسمة: «قسّم 300 على 4»\n'
      '🔔 التذكير: «ذكّر أحمد»\n'
      '🧾 الفاتورة: «ضيف أحمد ومحمد» · «ضيف بند بيتزا 25»\n'
      '🏖️ الرحلات: «اعمل رحلة مصيف مع أحمد وعلي»\n'
      '📂 التنقل: «افتح الديون / الرحلات / الأقساط / الإحصائيات…»\n'
      'أفهم الأرقام بالأرقام أو بالكلمات (خمسين، مية)، وأتسامح مع أخطاء الكتابة واللهجة (قداه، شحال، سلّفت…). وأعرض لك ما فهمته قبل التنفيذ دائماً.';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('المساعد')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(12),
              children: [
                for (final m in msgs)
                  Align(
                    alignment: m.user
                        ? AlignmentDirectional.centerStart
                        : AlignmentDirectional.centerEnd,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.85,
                      ),
                      decoration: BoxDecoration(
                        color: m.user
                            ? cs.primaryContainer
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.text),
                          if (m.run != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FilledButton(
                                    onPressed: () => _confirm(m),
                                    child: const Text('نفّذ'),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: () => _cancel(m),
                                    child: const Text('إلغاء'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final s in const [
                  'كم عليّ؟',
                  'كم لي؟',
                  'ملخص',
                  'افتح الديون',
                  'ضيف دين على أحمد 50',
                  'مساعدة',
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ActionChip(
                      label: Text(s),
                      onPressed: () {
                        input.text = s;
                        input.selection = TextSelection.collapsed(offset: s.length);
                      },
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'اكتب ما تريد…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: busy ? null : () => _send(),
                    icon: const Icon(Icons.send),
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

final Set<String> _stopN = {for (final w in {..._stop, ..._extraStop}) _norm(w)};
final Set<String> _debtN = {for (final w in _debtCues) _norm(w)};
final Map<String, int> _numN = {
  for (final e in _numWords.entries) _norm(e.key): e.value
};
final List<String> _verbsN = [
  for (final w in {..._stop, ..._extraStop, ..._debtCues})
    if (_norm(w).length >= 5) _norm(w)
];

/// هل الكلمة (غير الاسم) من الكلمات العامة، حتى لو أخطأ كاتبها في حرف؟
bool _isStopWord(String n) {
  if (_stopN.contains(n)) return true;
  if (n.length < 5) return false;
  for (final w in _verbsN) {
    if (_close(n, w)) return true;
  }
  return false;
}

int? _numVal(String t) {
  final v = _numN[t];
  if (v != null) return v;
  if (t.length >= 5) {
    for (final e in _numN.entries) {
      if (e.key.length >= 5 && _close(t, e.key)) return e.value;
    }
  }
  return null;
}
