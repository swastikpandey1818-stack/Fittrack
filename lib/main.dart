import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const kBg = Color(0xFF040706);
const kCard = Color(0xFF0D1511);
const kG1 = Color(0xFF00E676);
const kG2 = Color(0xFF00A152);
const kMu = Color(0xFF86A194);
const kLine = Color(0x2200E676);
const kGrad = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kG1, kG2]);
const img = 'assets/images/';
const dn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const muscles = ['Chest', 'Back', 'Shoulders', 'Arms', 'Legs', 'Core', 'Cardio', 'Other'];
const mColors = [Color(0xFF00E676), Color(0xFF00BFA5), Color(0xFFB2FF59), Color(0xFF64FFDA), Color(0xFF69F0AE), Color(0xFF76FF03), Color(0xFF1DE9B6), Color(0xFF86A194)];
final tick = ValueNotifier<int>(0);

typedef Rows = List<Map<String, Object?>>;

String dk(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String fmt(int s) {
  String t(int n) => n.toString().padLeft(2, '0');
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, x = s % 60;
  return h > 0 ? '$h:${t(m)}:${t(x)}' : '${t(m)}:${t(x)}';
}

Color mc(String m) {
  final i = muscles.indexOf(m);
  return mColors[i < 0 ? 7 : i];
}

String guess(String n) {
  final s = n.toLowerCase();
  bool h(List<String> k) => k.any((x) => s.contains(x));
  if (h(['squat', 'lunge', 'leg press', 'calf', 'leg curl', 'leg ext', 'glute', 'hamstring', 'quad'])) return 'Legs';
  if (h(['plank', 'crunch', 'sit-up', 'situp', 'abs', 'leg raise', 'twist'])) return 'Core';
  if (h(['run', 'burpee', 'jump', 'climber', 'skip', 'cycl', 'rope', 'jog'])) return 'Cardio';
  if (h(['curl', 'tricep', 'bicep'])) return 'Arms';
  if (h(['push', 'bench', 'chest', 'fly', 'dip'])) return 'Chest';
  if (h(['pull', 'row', 'deadlift', 'lat', 'back'])) return 'Back';
  if (h(['shoulder', 'press', 'raise', 'shrug'])) return 'Shoulders';
  return 'Other';
}

List<String> mlist(Rows it) => [for (final i in it) (i['muscle'] as String?) ?? guess(i['name'] as String)];

String cover(List<String> ms) {
  final c = <String, int>{};
  for (final m in ms) {
    c[m] = (c[m] ?? 0) + 1;
  }
  var top = 'Other', n = 0;
  c.forEach((k, v) {
    if (v > n) {
      n = v;
      top = k;
    }
  });
  return top == 'Legs' ? 'legs' : top == 'Core' ? 'core' : top == 'Cardio' ? 'cardio' : 'upper';
}

// ---------- database ----------
class DB {
  static late Database d;

  static Future<void> init() async {
    d = await openDatabase(
      p.join(await getDatabasesPath(), 'fittrack.db'),
      version: 2,
      onCreate: (db, v) async {
        await db.execute('CREATE TABLE kv(k TEXT PRIMARY KEY, v TEXT)');
        await db.execute('CREATE TABLE routines(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)');
        await db.execute('CREATE TABLE items(id INTEGER PRIMARY KEY AUTOINCREMENT, rid INTEGER, name TEXT, sets INTEGER, reps INTEGER, muscle TEXT)');
        await db.execute('CREATE TABLE workouts(id INTEGER PRIMARY KEY AUTOINCREMENT, day TEXT, ts INTEGER, routine TEXT, secs INTEGER)');
        await db.execute('CREATE TABLE sets(id INTEGER PRIMARY KEY AUTOINCREMENT, wid INTEGER, ex TEXT, reps INTEGER, kg REAL, muscle TEXT)');
        await db.execute('CREATE TABLE logins(day TEXT PRIMARY KEY)');
        await db.execute('CREATE TABLE schedule(day INTEGER PRIMARY KEY, rid INTEGER)');
        await db.execute('CREATE TABLE photos(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER, day TEXT, path TEXT, kg REAL, note TEXT)');
        await seed(db, fresh: true);
      },
      onUpgrade: (db, o, n) async {
        if (o < 2) {
          await db.execute('ALTER TABLE items ADD COLUMN muscle TEXT');
          await db.execute('ALTER TABLE sets ADD COLUMN muscle TEXT');
          await db.execute('CREATE TABLE schedule(day INTEGER PRIMARY KEY, rid INTEGER)');
          await db.execute('CREATE TABLE photos(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER, day TEXT, path TEXT, kg REAL, note TEXT)');
          for (final r in await db.query('items')) {
            await db.update('items', {'muscle': guess(r['name'] as String)}, where: 'id=?', whereArgs: [r['id']]);
          }
          for (final r in await db.query('sets')) {
            await db.update('sets', {'muscle': guess(r['ex'] as String)}, where: 'id=?', whereArgs: [r['id']]);
          }
          await seed(db, fresh: false);
        }
      },
    );
  }

  static Future<void> seed(Database db, {required bool fresh}) async {
    Future<void> mk(String n, List<List<Object>> it) async {
      final r = await db.insert('routines', {'name': n});
      for (final e in it) {
        await db.insert('items', {'rid': r, 'name': e[0], 'sets': e[1], 'reps': e[2], 'muscle': e[3]});
      }
    }

    if (fresh) await mk('Full Body', [['Push-ups', 3, 15, 'Chest'], ['Squats', 3, 20, 'Legs'], ['Lunges', 3, 12, 'Legs'], ['Burpees', 3, 10, 'Cardio']]);
    await mk('Chest & Triceps', [['Bench Press', 4, 10, 'Chest'], ['Push-ups', 3, 15, 'Chest'], ['Shoulder Press', 3, 10, 'Shoulders'], ['Tricep Dips', 3, 12, 'Arms']]);
    await mk('Back & Biceps', [['Pull-ups', 3, 8, 'Back'], ['Barbell Row', 4, 10, 'Back'], ['Deadlift', 3, 6, 'Back'], ['Bicep Curls', 3, 12, 'Arms']]);
    await mk('Leg Day', [['Squats', 4, 12, 'Legs'], ['Lunges', 3, 12, 'Legs'], ['Leg Press', 3, 12, 'Legs'], ['Calf Raises', 4, 15, 'Legs']]);
    await mk('Core & Cardio', [['Crunches', 3, 20, 'Core'], ['Leg Raises', 3, 15, 'Core'], ['Burpees', 3, 10, 'Cardio'], ['Mountain Climbers', 3, 30, 'Cardio']]);
    final ids = {for (final r in await db.query('routines')) r['name'] as String: r['id'] as int};
    const plan = {1: 'Chest & Triceps', 2: 'Back & Biceps', 3: 'Leg Day', 4: 'Core & Cardio', 5: 'Full Body'};
    for (var d = 1; d <= 7; d++) {
      await db.insert('schedule', {'day': d, 'rid': ids[plan[d]] ?? 0}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  static Future<String?> kv(String k) async {
    final r = await d.query('kv', where: 'k=?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as String?;
  }

  static Future<void> setKv(String k, String v) async {
    await d.insert('kv', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<Map<String, Object?>?> planFor(int wd) async {
  final s = await DB.d.query('schedule', where: 'day=?', whereArgs: [wd]);
  if (s.isEmpty || (s.first['rid'] as int) == 0) return null;
  final rid = s.first['rid'] as int;
  final r = await DB.d.query('routines', where: 'id=?', whereArgs: [rid]);
  if (r.isEmpty) return null;
  final it = await DB.d.query('items', where: 'rid=?', whereArgs: [rid]);
  return {'id': rid, 'name': r.first['name'], 'items': it.toList()};
}

class St {
  final Rows ws, ss;
  final Set<String> lg;
  St(this.ws, this.ss, this.lg);
  static Future<St> load() async => St(
        await DB.d.query('workouts', orderBy: 'ts DESC'),
        await DB.d.rawQuery('SELECT s.wid, s.ex, s.reps, s.kg, s.muscle, w.day FROM sets s JOIN workouts w ON w.id=s.wid'),
        (await DB.d.query('logins')).map((e) => e['day'] as String).toSet(),
      );
  Set<String> get wdays => ws.map((e) => e['day'] as String).toSet();
  int streak(Set<String> s) {
    var d = DateTime.now();
    if (!s.contains(dk(d))) d = DateTime(d.year, d.month, d.day - 1);
    var n = 0;
    while (s.contains(dk(d))) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }

  List<DateTime> days(int n) {
    final t = DateTime.now();
    return [for (var k = n - 1; k >= 0; k--) DateTime(t.year, t.month, t.day - k)];
  }

  double mins(String d) => ws.where((e) => e['day'] == d).fold<double>(0, (a, e) => a + (e['secs'] as int) / 60);
  double reps(String d) => ss.where((e) => e['day'] == d).fold<double>(0, (a, e) => a + (e['reps'] as int));
  int get totalReps => ss.fold<int>(0, (a, e) => a + (e['reps'] as int));
  Map<String, int> byMuscle() {
    final m = <String, int>{};
    for (final s in ss) {
      final k = (s['muscle'] as String?) ?? guess(s['ex'] as String);
      m[k] = (m[k] ?? 0) + (s['reps'] as int);
    }
    return m;
  }
}

const bkTables = ['kv', 'routines', 'items', 'workouts', 'sets', 'logins', 'schedule'];

Future<String> exportBackup() async {
  final o = <String, Object?>{'app': 'fittrack', 'v': 2};
  for (final t in bkTables) {
    o[t] = await DB.d.query(t);
  }
  return jsonEncode(o);
}

Future<String?> importBackup(String s) async {
  try {
    final o = jsonDecode(s) as Map<String, dynamic>;
    if (o['app'] != 'fittrack') return 'That text is not a FitTrack backup.';
    await DB.d.transaction((tx) async {
      for (final t in bkTables) {
        await tx.delete(t);
        for (final r in (o[t] as List)) {
          await tx.insert(t, Map<String, Object?>.from(r as Map));
        }
      }
    });
    tick.value++;
    return null;
  } catch (e) {
    return 'Could not read that backup text. Copy it again and retry.';
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DB.init();
  await DB.d.insert('logins', {'day': dk(DateTime.now())}, conflictAlgorithm: ConflictAlgorithm.ignore);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: kBg));
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FitTrack',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kBg,
          colorScheme: const ColorScheme.dark(primary: kG1, secondary: kG2, surface: kCard),
        ),
        home: const Splash(),
      );
}

// ---------- shared widgets ----------
Widget bg(Widget child) => Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0B2A1B), kBg], stops: [0, .5])),
      child: child,
    );

Widget sub(String t, Widget w) => bg(Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(t, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: w,
    ));

Widget card(Widget child, {Gradient? g}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(gradient: g, color: g == null ? kCard : null, borderRadius: BorderRadius.circular(22), border: Border.all(color: kLine)),
      child: child,
    );

Widget gbtn(String t, VoidCallback f, {IconData? i}) => GestureDetector(
      onTap: f,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(gradient: kGrad, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Color(0x5500E676), blurRadius: 18, offset: Offset(0, 6))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (i != null) ...[Icon(i, color: Colors.black), const SizedBox(width: 8)],
          Text(t, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
      ),
    );

Widget tile(IconData i, String v, String l) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kLine)),
        child: Column(children: [
          Icon(i, color: kG1),
          const SizedBox(height: 6),
          Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(l, style: const TextStyle(color: kMu, fontSize: 12), textAlign: TextAlign.center),
        ]),
      ),
    );

Widget chips(Iterable<String> ms) => Wrap(spacing: 6, runSpacing: 6, children: [
      for (final m in ms)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: mc(m).withOpacity(.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: mc(m).withOpacity(.5))),
          child: Text(m, style: TextStyle(color: mc(m), fontSize: 12, fontWeight: FontWeight.w700)),
        ),
    ]);

Widget ttl(String t, [String? s]) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        if (s != null) Text(s, style: const TextStyle(color: kMu, fontSize: 12)),
      ]),
    );

class Async<T> extends StatelessWidget {
  final Future<T> Function() f;
  final Widget Function(BuildContext, T) b;
  const Async(this.f, this.b, {super.key});
  @override
  Widget build(BuildContext c) => ValueListenableBuilder<int>(
        valueListenable: tick,
        builder: (c, _, __) => FutureBuilder<T>(future: f(), builder: (c, s) => s.hasData ? b(c, s.data as T) : const Center(child: CircularProgressIndicator(color: kG1))),
      );
}

Future<String?> ask(BuildContext c, String t, {String hint = '', bool numeric = false}) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: c,
    builder: (d) => AlertDialog(
      backgroundColor: kCard,
      title: Text(t),
      content: TextField(controller: ctl, autofocus: true, keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Skip')),
        TextButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

Future<List<String>?> askItem(BuildContext c) {
  final n = TextEditingController(), s = TextEditingController(text: '3'), r = TextEditingController(text: '12');
  var m = 'Other';
  return showDialog<List<String>>(
    context: c,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Add exercise'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: n, autofocus: true, decoration: const InputDecoration(labelText: 'Exercise name')),
            TextField(controller: s, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sets')),
            TextField(controller: r, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Reps')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: m,
              dropdownColor: kCard,
              decoration: const InputDecoration(labelText: 'Muscle (Other = auto-detect)'),
              items: [for (final x in muscles) DropdownMenuItem(value: x, child: Text(x))],
              onChanged: (v) => set(() => m = v ?? 'Other'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, [n.text.trim(), s.text, r.text, m == 'Other' ? guess(n.text) : m]), child: const Text('Add')),
        ],
      ),
    ),
  );
}

// ---------- charts ----------
class BarsPainter extends CustomPainter {
  final List<double> v;
  final List<String> l;
  BarsPainter(this.v, this.l);
  @override
  void paint(Canvas c, Size s) {
    final mx = v.fold<double>(1, (a, b) => b > a ? b : a);
    final w = s.width / v.length;
    for (var i = 0; i < v.length; i++) {
      var h = (s.height - 22) * v[i] / mx;
      if (h < 4) h = v[i] == 0 ? 3 : 4;
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(i * w + w * .2, s.height - 22 - h, w * .6, h), const Radius.circular(8));
      final paint = Paint();
      if (v[i] > 0) {
        paint.shader = kGrad.createShader(r.outerRect);
      } else {
        paint.color = kLine;
      }
      c.drawRRect(r, paint);
      final tp = TextPainter(text: TextSpan(text: l[i], style: const TextStyle(color: kMu, fontSize: 11)), textDirection: TextDirection.ltr)..layout();
      tp.paint(c, Offset(i * w + (w - tp.width) / 2, s.height - 16));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}

class TrendPainter extends CustomPainter {
  final List<double> v;
  TrendPainter(this.v);
  @override
  void paint(Canvas c, Size s) {
    if (v.length < 2) return;
    final mx = v.fold<double>(1, (a, b) => b > a ? b : a);
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = i * s.width / (v.length - 1);
      final y = s.height - 8 - (s.height - 16) * v[i] / mx;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    c.drawPath(fill, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x6600E676), Color(0x0000E676)]).createShader(Rect.fromLTWH(0, 0, s.width, s.height)));
    c.drawPath(path, Paint()..color = kG1..style = PaintingStyle.stroke..strokeWidth = 3..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}

class PiePainter extends CustomPainter {
  final List<double> v;
  final List<Color> cols;
  PiePainter(this.v, this.cols);
  @override
  void paint(Canvas c, Size s) {
    final tot = v.fold<double>(0, (a, b) => a + b);
    if (tot == 0) return;
    final rect = Rect.fromCircle(center: s.center(Offset.zero), radius: s.shortestSide / 2 - 16);
    var a = -math.pi / 2;
    for (var i = 0; i < v.length; i++) {
      final sw = 2 * math.pi * v[i] / tot;
      c.drawArc(rect, a, sw > .04 ? sw - .03 : sw, false, Paint()..color = cols[i]..style = PaintingStyle.stroke..strokeWidth = 26);
      a += sw;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}

// ---------- splash + shell ----------
class Splash extends StatefulWidget {
  const Splash({super.key});
  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const Shell(), transitionsBuilder: (_, a, __, ch) => FadeTransition(opacity: a, child: ch)));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(fit: StackFit.expand, children: [
          Image.asset('${img}splash.jpg', fit: BoxFit.cover),
          Align(
            alignment: const Alignment(0, .72),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ShaderMask(shaderCallback: (r) => kGrad.createShader(r), child: const Text('FITTRACK', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: 6, color: Colors.white))),
              const SizedBox(height: 6),
              const Text('Train. Track. Transform.', style: TextStyle(color: kMu, letterSpacing: 1.5)),
            ]),
          ),
        ]),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;
  static const titles = ['FitTrack', 'Weekly plan', 'Progress', 'Transformation', 'Profile'];
  void go(int k) => setState(() => i = k);

  Widget nav(int k) {
    const ic = [Icons.home_rounded, Icons.calendar_month_rounded, Icons.insights_rounded, Icons.photo_camera_rounded, Icons.person_rounded];
    final on = i == k;
    return GestureDetector(
      onTap: () => go(k),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(gradient: on ? kGrad : null, shape: BoxShape.circle),
        child: Icon(ic[k], color: on ? Colors.black : kMu),
      ),
    );
  }

  Widget item(BuildContext c, IconData ic, String t, VoidCallback f) => ListTile(leading: Icon(ic, color: kG1), title: Text(t), onTap: () {
        Navigator.pop(c);
        f();
      });

  @override
  Widget build(BuildContext context) {
    const pages = [HomePage(), WeekPage(), StatsPage(), TransformPage(), ProfilePage()];
    return bg(Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, title: Text(titles[i], style: const TextStyle(fontWeight: FontWeight.w800))),
      drawer: Drawer(
        backgroundColor: kBg,
        child: ListView(padding: EdgeInsets.zero, children: [
          SizedBox(
            height: 170,
            child: Stack(fit: StackFit.expand, children: [
              Image.asset('${img}drawer_header.jpg', fit: BoxFit.cover),
              Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00040706), kBg]))),
              const Positioned(left: 16, bottom: 12, child: Text('FitTrack v1.2', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
            ]),
          ),
          item(context, Icons.home_rounded, 'Home', () => go(0)),
          item(context, Icons.calendar_month_rounded, 'Weekly plan', () => go(1)),
          item(context, Icons.list_alt_rounded, 'My routines', () => Navigator.push(context, MaterialPageRoute(builder: (_) => sub('My routines', const RoutinesPage())))),
          item(context, Icons.insights_rounded, 'Progress & results', () => go(2)),
          item(context, Icons.history_rounded, 'Workout history', () => Navigator.push(context, MaterialPageRoute(builder: (_) => sub('History', const HistoryPage())))),
          item(context, Icons.photo_camera_rounded, 'Transformation', () => go(3)),
          item(context, Icons.person_rounded, 'Profile', () => go(4)),
        ]),
      ),
      body: pages[i],
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Container(
          height: 70,
          decoration: BoxDecoration(color: const Color(0xF2111B16), borderRadius: BorderRadius.circular(35), border: Border.all(color: const Color(0x4000E676)), boxShadow: const [BoxShadow(color: Color(0x3000E676), blurRadius: 26)]),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [for (var k = 0; k < 5; k++) nav(k)]),
        ),
      ),
    ));
  }
}

// ---------- home ----------
Future<void> pickRoutine(BuildContext c) async {
  final rs = await DB.d.query('routines');
  if (!c.mounted) return;
  showModalBottomSheet(
    context: c,
    isScrollControlled: true,
    backgroundColor: kCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (b) => SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Choose routine', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final r in rs)
          ListTile(
            title: Text(r['name'] as String),
            trailing: const Icon(Icons.chevron_right, color: kG1),
            onTap: () async {
              final it = await DB.d.query('items', where: 'rid=?', whereArgs: [r['id']]);
              if (!c.mounted) return;
              Navigator.pop(b);
              Navigator.push(c, MaterialPageRoute(builder: (_) => WorkoutPage(r['name'] as String, it.toList())));
            },
          ),
        ListTile(
          title: const Text('Quick workout (add as you go)'),
          trailing: const Icon(Icons.bolt, color: kG1),
          onTap: () {
            Navigator.pop(b);
            Navigator.push(c, MaterialPageRoute(builder: (_) => const WorkoutPage('Quick workout', [])));
          },
        ),
      ]),
    ),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => Async<List<Object?>>(
        () async => [await St.load(), await DB.kv('name'), int.tryParse(await DB.kv('goal') ?? '') ?? 4, await planFor(DateTime.now().weekday)],
        (c, d) {
          final st = d[0] as St;
          final name = ((d[1] as String?) ?? '').trim();
          var goal = d[2] as int;
          if (goal < 1) goal = 1;
          final plan = d[3] as Map<String, Object?>?;
          final ds = st.days(7);
          const wd = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
          final week = ds.where((x) => st.wdays.contains(dk(x))).length;
          final secs = st.ws.fold<int>(0, (a, e) => a + (e['secs'] as int));
          final ws = st.streak(st.wdays);
          return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 120), children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 190,
                child: Stack(fit: StackFit.expand, children: [
                  Image.asset('${img}home_banner.jpg', fit: BoxFit.cover, alignment: Alignment.centerRight),
                  Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xEE040706), Color(0x00040706)]))),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Welcome back,', style: TextStyle(color: kMu)),
                      Text(name.isEmpty ? 'Athlete' : name, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            card(Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: Stack(children: [
                    Image.asset('${img}badge.jpg'),
                    Align(alignment: const Alignment(0, .44), child: Text('$ws DAY', style: const TextStyle(color: kG1, fontSize: 9, fontWeight: FontWeight.w900))),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(children: [
                Row(children: [
                  const Icon(Icons.local_fire_department_rounded, color: kG1),
                  const SizedBox(width: 8),
                  Text('$ws', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('workout streak', style: TextStyle(color: kMu))),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.event_available_rounded, color: kG1),
                  const SizedBox(width: 8),
                  Text('${st.streak(st.lg)}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('login streak', style: TextStyle(color: kMu))),
                ]),
              ])),
            ])),
            if (plan != null)
              card(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('TODAY · ${dn[DateTime.now().weekday - 1].toUpperCase()}', style: const TextStyle(color: kG1, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('${plan['name']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  chips(mlist(plan['items'] as Rows).toSet()),
                  const SizedBox(height: 14),
                  gbtn('Start ${plan['name']}', () => Navigator.push(c, MaterialPageRoute(builder: (_) => WorkoutPage(plan['name'] as String, plan['items'] as Rows))), i: Icons.play_arrow_rounded),
                  Center(child: TextButton(onPressed: () => pickRoutine(c), child: const Text('Pick another routine', style: TextStyle(color: kMu)))),
                ]),
              )
            else
              card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TODAY · ${dn[DateTime.now().weekday - 1].toUpperCase()}', style: const TextStyle(color: kG1, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 12)),
                const SizedBox(height: 4),
                const Text('Rest day', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                const Text('Recovery is part of the plan. Sleep, eat, stretch.', style: TextStyle(color: kMu)),
                const SizedBox(height: 14),
                gbtn('Train anyway', () => pickRoutine(c), i: Icons.bolt_rounded),
              ])),
            card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('This week', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('$week / $goal workouts', style: const TextStyle(color: kMu)),
              ]),
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: (week / goal).clamp(0.0, 1.0).toDouble(), minHeight: 8, backgroundColor: kLine, color: kG1)),
              const SizedBox(height: 18),
              const Text('Minutes per day', style: TextStyle(color: kMu, fontSize: 12)),
              const SizedBox(height: 8),
              SizedBox(height: 130, width: double.infinity, child: CustomPaint(painter: BarsPainter([for (final x in ds) st.mins(dk(x))], [for (final x in ds) wd[x.weekday - 1]]))),
            ])),
            Row(children: [
              tile(Icons.fitness_center, '${st.ws.length}', 'Workouts'),
              tile(Icons.repeat_rounded, '${st.totalReps}', 'Total reps'),
              tile(Icons.timer_outlined, '${(secs / 60).round()}m', 'Time'),
            ]),
          ]);
        },
      );
}

// ---------- weekly plan ----------
Future<void> setDay(int d, int rid) async {
  await DB.d.insert('schedule', {'day': d, 'rid': rid}, conflictAlgorithm: ConflictAlgorithm.replace);
  tick.value++;
}

Future<void> pickDay(BuildContext c, int d) async {
  final rs = await DB.d.query('routines');
  if (!c.mounted) return;
  showModalBottomSheet(
    context: c,
    isScrollControlled: true,
    backgroundColor: kCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (b) => SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${dn[d - 1]} workout', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.bedtime_rounded, color: kMu),
          title: const Text('Rest day'),
          onTap: () {
            setDay(d, 0);
            Navigator.pop(b);
          },
        ),
        for (final r in rs)
          ListTile(
            leading: const Icon(Icons.fitness_center, color: kG1),
            title: Text(r['name'] as String),
            onTap: () {
              setDay(d, r['id'] as int);
              Navigator.pop(b);
            },
          ),
      ]),
    ),
  );
}

class WeekPage extends StatelessWidget {
  const WeekPage({super.key});
  @override
  Widget build(BuildContext context) => Async<List<Map<String, Object?>?>>(
        () async => [for (var d = 1; d <= 7; d++) await planFor(d)],
        (c, pl) => ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 120), children: [
          const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Tap a day to choose what you train. Rest days are part of it.', style: TextStyle(color: kMu))),
          for (var d = 1; d <= 7; d++)
            GestureDetector(
              onTap: () => pickDay(c, d),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: d == DateTime.now().weekday ? kG1 : kLine, width: d == DateTime.now().weekday ? 1.6 : 1)),
                child: Row(children: [
                  Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(gradient: pl[d - 1] != null ? kGrad : null, color: pl[d - 1] == null ? const Color(0xFF16201B) : null, borderRadius: BorderRadius.circular(14)),
                    child: Text(dn[d - 1].substring(0, 3).toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: pl[d - 1] != null ? Colors.black : kMu)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: pl[d - 1] == null
                        ? const Text('Rest day', style: TextStyle(color: kMu, fontSize: 17, fontWeight: FontWeight.w700))
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${pl[d - 1]!['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            chips(mlist(pl[d - 1]!['items'] as Rows).toSet()),
                          ]),
                  ),
                  if (d == DateTime.now().weekday) const Text('TODAY ', style: TextStyle(color: kG1, fontSize: 11, fontWeight: FontWeight.w900)),
                  const Icon(Icons.edit_outlined, color: kMu, size: 18),
                ]),
              ),
            ),
          const SizedBox(height: 6),
          gbtn('Manage routines', () => Navigator.push(c, MaterialPageRoute(builder: (_) => sub('My routines', const RoutinesPage()))), i: Icons.list_alt_rounded),
        ]),
      );
}

// ---------- workout session ----------
class WorkoutPage extends StatefulWidget {
  final String name;
  final Rows items;
  const WorkoutPage(this.name, this.items, {super.key});
  @override
  State<WorkoutPage> createState() => _WS();
}

class _WS extends State<WorkoutPage> {
  late List<String> exs;
  final Map<String, int> target = {};
  final Map<String, String> mus = {};
  int ei = 0, reps = 0, restLeft = 0, rest = 60;
  bool paused = false;
  final sw = Stopwatch()..start();
  Timer? t;
  final logged = <Map<String, Object?>>[];
  final kg = TextEditingController();

  @override
  void initState() {
    super.initState();
    exs = [for (final i in widget.items) i['name'] as String];
    for (final i in widget.items) {
      target[i['name'] as String] = i['sets'] as int;
      mus[i['name'] as String] = (i['muscle'] as String?) ?? guess(i['name'] as String);
    }
    DB.kv('rest').then((v) {
      if (v != null) rest = int.tryParse(v) ?? 60;
    });
    t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (restLeft > 0) {
          restLeft--;
          if (restLeft == 0) HapticFeedback.heavyImpact();
        }
      });
    });
  }

  @override
  void dispose() {
    t?.cancel();
    kg.dispose();
    super.dispose();
  }

  Future<void> addEx() async {
    final v = await askItem(context);
    if (v != null && v[0].isNotEmpty) {
      setState(() {
        exs.add(v[0]);
        target[v[0]] = int.tryParse(v[1]) ?? 3;
        mus[v[0]] = v[3];
        ei = exs.length - 1;
        reps = 0;
      });
    }
  }

  Future<void> typeReps() async {
    final v = await ask(context, 'Total reps done', numeric: true);
    final n = int.tryParse(v ?? '');
    if (n != null) setState(() => reps = n);
  }

  void logSet() {
    if (exs.isEmpty || reps <= 0) return;
    setState(() {
      logged.add({'ex': exs[ei], 'reps': reps, 'kg': double.tryParse(kg.text) ?? 0.0, 'muscle': mus[exs[ei]] ?? 'Other'});
      reps = 0;
      restLeft = rest;
    });
    HapticFeedback.mediumImpact();
  }

  Future<void> finish() async {
    if (logged.isNotEmpty) {
      final now = DateTime.now();
      final secs = sw.elapsed.inSeconds;
      final id = await DB.d.insert('workouts', {'day': dk(now), 'ts': now.millisecondsSinceEpoch, 'routine': widget.name, 'secs': secs});
      final b = DB.d.batch();
      for (final s in logged) {
        b.insert('sets', {...s, 'wid': id});
      }
      await b.commit(noResult: true);
      tick.value++;
      if (!mounted) return;
      final tot = logged.fold<int>(0, (a, s) => a + (s['reps'] as int));
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('Workout complete 💪'),
          content: Text('${fmt(secs)}  ·  ${logged.length} sets  ·  $tot reps', style: const TextStyle(fontSize: 18)),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Nice'))],
        ),
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ex = exs.isEmpty ? null : exs[ei];
    final done = ex == null ? 0 : logged.where((s) => s['ex'] == ex).length;
    return bg(Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            Expanded(child: Text(widget.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            TextButton(onPressed: finish, child: const Text('FINISH', style: TextStyle(color: kG1, fontWeight: FontWeight.w900))),
          ]),
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: kGrad, boxShadow: [BoxShadow(color: Color(0x5500E676), blurRadius: 40)]),
              child: Center(
                child: Container(
                  width: 196,
                  height: 196,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: kBg),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(fmt(sw.elapsed.inSeconds), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900)),
                    Text(paused ? 'PAUSED' : 'WORKOUT TIME', style: const TextStyle(color: kG1, fontSize: 12, letterSpacing: 2)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: kG1, foregroundColor: Colors.black),
              onPressed: () => setState(() {
                paused = !paused;
                paused ? sw.stop() : sw.start();
              }),
              icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 30),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 46,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (var i = 0; i < exs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(exs[i]),
                    selected: i == ei,
                    showCheckmark: false,
                    selectedColor: kG1,
                    backgroundColor: kCard,
                    labelStyle: TextStyle(color: i == ei ? Colors.black : Colors.white, fontWeight: FontWeight.w700),
                    onSelected: (_) => setState(() {
                      ei = i;
                      reps = 0;
                    }),
                  ),
                ),
              ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Add'), backgroundColor: kCard, onPressed: addEx),
            ]),
          ),
          const SizedBox(height: 14),
          if (ex == null)
            card(const Text('Tap Add to choose your first exercise.', style: TextStyle(color: kMu)))
          else
            card(Column(children: [
              Text(ex, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              chips([mus[ex] ?? 'Other']),
              const SizedBox(height: 4),
              Text('Set ${done + 1}${target[ex] != null ? ' of ${target[ex]}' : ''}', style: const TextStyle(color: kMu)),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(iconSize: 38, onPressed: () => setState(() => reps = reps > 0 ? reps - 1 : 0), icon: const Icon(Icons.remove_circle_outline, color: kMu)),
                GestureDetector(
                  onTap: typeReps,
                  child: ShaderMask(
                    shaderCallback: (r) => kGrad.createShader(r),
                    child: SizedBox(width: 120, child: Text('$reps', textAlign: TextAlign.center, style: const TextStyle(fontSize: 76, fontWeight: FontWeight.w900, color: Colors.white))),
                  ),
                ),
                IconButton(iconSize: 38, onPressed: () => setState(() => reps++), icon: const Icon(Icons.add_circle, color: kG1)),
              ]),
              const Text('tap the number to type your total reps', style: TextStyle(color: kMu, fontSize: 11)),
              const SizedBox(height: 10),
              TextField(
                controller: kg,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Weight kg (optional)', filled: true, fillColor: kBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
              ),
              const SizedBox(height: 12),
              gbtn('Log set', logSet, i: Icons.check_rounded),
            ])),
          if (restLeft > 0)
            card(Row(children: [
              const Icon(Icons.hourglass_bottom_rounded, color: kG1),
              const SizedBox(width: 10),
              Text('Rest ${fmt(restLeft)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(onPressed: () => setState(() => restLeft += 15), child: const Text('+15s')),
              TextButton(onPressed: () => setState(() => restLeft = 0), child: const Text('Skip')),
            ])),
          if (logged.isNotEmpty)
            card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Logged sets', style: TextStyle(fontWeight: FontWeight.w800)),
              for (final s in logged.reversed)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${s['ex']}'),
                  trailing: Text('${s['reps']} reps${(s['kg'] as double) > 0 ? ' · ${s['kg']} kg' : ''}', style: const TextStyle(color: kG1)),
                ),
            ])),
        ]),
      ),
    ));
  }
}

// ---------- routines ----------
class RoutinesPage extends StatelessWidget {
  const RoutinesPage({super.key});
  @override
  Widget build(BuildContext context) => Async<Rows>(
        () async {
          final rs = await DB.d.query('routines');
          final out = <Map<String, Object?>>[];
          for (final r in rs) {
            final it = await DB.d.query('items', where: 'rid=?', whereArgs: [r['id']]);
            out.add({'id': r['id'], 'name': r['name'], 'n': it.length, 'm': mlist(it.toList())});
          }
          return out;
        },
        (c, rs) => ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
          gbtn('New routine', () => Navigator.push(c, MaterialPageRoute(builder: (_) => const RoutineEditor(null))), i: Icons.add_rounded),
          for (final r in rs)
            GestureDetector(
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => RoutineEditor(r['id'] as int))),
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(22), border: Border.all(color: kLine)),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(22)),
                    child: Image.asset('${img}cover_${cover(r['m'] as List<String>)}.jpg', width: 100, height: 100, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text('${r['n']} exercises', style: const TextStyle(color: kMu, fontSize: 13)),
                    const SizedBox(height: 6),
                    chips((r['m'] as List<String>).toSet()),
                  ])),
                  const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.edit_outlined, color: kMu)),
                ]),
              ),
            ),
        ]),
      );
}

class RoutineEditor extends StatefulWidget {
  final int? id;
  const RoutineEditor(this.id, {super.key});
  @override
  State<RoutineEditor> createState() => _RE();
}

class _RE extends State<RoutineEditor> {
  final name = TextEditingController();
  Rows items = [];

  @override
  void initState() {
    super.initState();
    if (widget.id != null) load();
  }

  Future<void> load() async {
    final r = await DB.d.query('routines', where: 'id=?', whereArgs: [widget.id]);
    final it = await DB.d.query('items', where: 'rid=?', whereArgs: [widget.id]);
    setState(() {
      name.text = r.first['name'] as String;
      items = [for (final e in it) Map<String, Object?>.from(e)];
    });
  }

  Future<void> add() async {
    final v = await askItem(context);
    if (v != null && v[0].isNotEmpty) {
      setState(() => items.add({'name': v[0], 'sets': int.tryParse(v[1]) ?? 3, 'reps': int.tryParse(v[2]) ?? 10, 'muscle': v[3]}));
    }
  }

  Future<void> save() async {
    final n = name.text.trim();
    if (n.isEmpty) return;
    int rid;
    if (widget.id == null) {
      rid = await DB.d.insert('routines', {'name': n});
    } else {
      rid = widget.id!;
      await DB.d.update('routines', {'name': n}, where: 'id=?', whereArgs: [rid]);
      await DB.d.delete('items', where: 'rid=?', whereArgs: [rid]);
    }
    for (final i in items) {
      await DB.d.insert('items', {'rid': rid, 'name': i['name'], 'sets': i['sets'], 'reps': i['reps'], 'muscle': i['muscle']});
    }
    tick.value++;
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> del() async {
    await DB.d.delete('items', where: 'rid=?', whereArgs: [widget.id]);
    await DB.d.delete('routines', where: 'id=?', whereArgs: [widget.id]);
    await DB.d.update('schedule', {'rid': 0}, where: 'rid=?', whereArgs: [widget.id]);
    tick.value++;
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => bg(Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Routine', style: TextStyle(fontWeight: FontWeight.w800)), actions: [
          if (widget.id != null) IconButton(onPressed: del, icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
        ]),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          TextField(controller: name, decoration: InputDecoration(labelText: 'Routine name', filled: true, fillColor: kCard, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
          const SizedBox(height: 16),
          for (var i = 0; i < items.length; i++)
            card(Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${items[i]['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('${items[i]['sets']} sets × ${items[i]['reps']} reps', style: const TextStyle(color: kMu)),
                const SizedBox(height: 6),
                chips([(items[i]['muscle'] as String?) ?? guess(items[i]['name'] as String)]),
              ])),
              IconButton(onPressed: () => setState(() => items.removeAt(i)), icon: const Icon(Icons.close, color: kMu)),
            ])),
          gbtn('Add exercise', add, i: Icons.add_rounded),
          gbtn('Save routine', save, i: Icons.check_rounded),
        ]),
      ));
}

// ---------- stats ----------
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});
  @override
  Widget build(BuildContext context) => Async<St>(St.load, (c, st) {
        final w7 = st.days(7), d30 = st.days(30), d28 = st.days(28);
        const wd = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
        final m = <String, int>{};
        final best = <String, List<num>>{};
        for (final s in st.ss) {
          final k = s['ex'] as String;
          final r = s['reps'] as int;
          final w = (s['kg'] as num?)?.toDouble() ?? 0.0;
          m[k] = (m[k] ?? 0) + r;
          final b = best.putIfAbsent(k, () => <num>[0, 0]);
          if (w > b[0]) b[0] = w;
          if (r > b[1]) b[1] = r;
        }
        final top = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final mx = top.isEmpty ? 1 : top.first.value;
        final bm = st.byMuscle();
        final pm = [for (final x in muscles) if ((bm[x] ?? 0) > 0) x];
        final pv = [for (final x in pm) bm[x]!.toDouble()];
        final ptot = pv.fold<double>(0, (a, b) => a + b);
        return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 120), children: [
          Row(children: [
            tile(Icons.fitness_center, '${st.ws.length}', 'Workouts'),
            tile(Icons.layers_rounded, '${st.ss.length}', 'Sets'),
            tile(Icons.repeat_rounded, '${st.totalReps}', 'Reps'),
          ]),
          const SizedBox(height: 14),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ttl('Reps per day', 'last 7 days'),
            SizedBox(height: 130, width: double.infinity, child: CustomPaint(painter: BarsPainter([for (final x in w7) st.reps(dk(x))], [for (final x in w7) wd[x.weekday - 1]]))),
          ])),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ttl('Reps trend', 'last 30 days'),
            SizedBox(height: 130, width: double.infinity, child: CustomPaint(painter: TrendPainter([for (final x in d30) st.reps(dk(x))]))),
          ])),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ttl('Muscles trained', 'share of total reps'),
            if (pv.isEmpty)
              const Text('Finish a workout to see your muscle split.', style: TextStyle(color: kMu))
            else ...[
              SizedBox(
                height: 200,
                width: double.infinity,
                child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(size: const Size(200, 200), painter: PiePainter(pv, [for (final x in pm) mc(x)])),
                  Column(mainAxisSize: MainAxisSize.min, children: [Text('${ptot.round()}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)), const Text('reps', style: TextStyle(color: kMu))]),
                ]),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 14, runSpacing: 8, children: [
                for (var i = 0; i < pm.length; i++)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: mc(pm[i]), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${pm[i]} ${(pv[i] * 100 / ptot).round()}%', style: const TextStyle(fontSize: 13)),
                  ]),
              ]),
            ],
          ])),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ttl('Top exercises', 'total reps'),
            if (top.isEmpty) const Text('Nothing logged yet.', style: TextStyle(color: kMu)),
            for (final e in top.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(e.key), Text('${e.value}', style: const TextStyle(color: kG1, fontWeight: FontWeight.w800))]),
                  const SizedBox(height: 4),
                  FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: e.value / mx, child: Container(height: 8, decoration: BoxDecoration(gradient: kGrad, borderRadius: BorderRadius.circular(6)))),
                ]),
              ),
          ])),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ttl('Personal bests', 'most reps in one set · heaviest weight'),
            if (top.isEmpty) const Text('Nothing logged yet.', style: TextStyle(color: kMu)),
            for (final e in top.take(6))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.emoji_events_rounded, color: kG1),
                title: Text(e.key),
                trailing: Text('${best[e.key]![1]} reps${best[e.key]![0] > 0 ? ' · ${best[e.key]![0].toDouble().toStringAsFixed(1)} kg' : ''}', style: const TextStyle(color: kG1, fontWeight: FontWeight.w700)),
              ),
          ])),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ttl('Streak calendar', 'bright = workout · dim = opened app'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final x in d28)
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: st.wdays.contains(dk(x)) ? kGrad : null,
                    color: st.wdays.contains(dk(x)) ? null : (st.lg.contains(dk(x)) ? const Color(0x3300E676) : const Color(0xFF16201B)),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text('${x.day}', style: TextStyle(fontSize: 11, color: st.wdays.contains(dk(x)) ? Colors.black : kMu)),
                ),
            ]),
          ])),
          gbtn('Full workout history', () => Navigator.push(c, MaterialPageRoute(builder: (_) => sub('History', const HistoryPage()))), i: Icons.history_rounded),
        ]);
      });
}

// ---------- history ----------
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});
  @override
  Widget build(BuildContext context) => Async<St>(St.load, (c, st) {
        if (st.ws.isEmpty) {
          return ListView(padding: const EdgeInsets.all(30), children: [
            Image.asset('${img}empty.jpg', height: 280),
            const SizedBox(height: 10),
            const Text('No workouts yet', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const Text('Finish your first workout and it will show up here.', textAlign: TextAlign.center, style: TextStyle(color: kMu)),
          ]);
        }
        final g = <int, Rows>{};
        for (final s in st.ss) {
          g.putIfAbsent(s['wid'] as int, () => []).add(s);
        }
        return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
          for (final w in st.ws)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kLine)),
              child: Theme(
                data: Theme.of(c).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: Text('${w['routine']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${w['day']} · ${fmt(w['secs'] as int)} · ${(g[w['id']] ?? []).length} sets', style: const TextStyle(color: kMu)),
                  children: [
                    for (final s in g[w['id']] ?? <Map<String, Object?>>[])
                      ListTile(
                        dense: true,
                        title: Text('${s['ex']}'),
                        trailing: Text('${s['reps']} reps${((s['kg'] as num?) ?? 0) > 0 ? ' · ${s['kg']} kg' : ''}', style: const TextStyle(color: kG1)),
                      ),
                    TextButton.icon(
                      onPressed: () async {
                        await DB.d.delete('sets', where: 'wid=?', whereArgs: [w['id']]);
                        await DB.d.delete('workouts', where: 'id=?', whereArgs: [w['id']]);
                        tick.value++;
                      },
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                      label: const Text('Delete workout', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              ),
            ),
        ]);
      });
}

// ---------- transformation ----------
Widget photo(Map<String, Object?>? ph) => ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ph == null
          ? Image.asset('${img}placeholder.jpg', fit: BoxFit.cover)
          : Image.file(File(ph['path'] as String), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Image.asset('${img}placeholder.jpg', fit: BoxFit.cover)),
    );

double kgOf(Map<String, Object?> p) => (p['kg'] as num?)?.toDouble() ?? 0.0;

Future<void> addPhoto(BuildContext c) async {
  final src = await showModalBottomSheet<ImageSource>(
    context: c,
    backgroundColor: kCard,
    builder: (b) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera, color: kG1), title: const Text('Take photo'), onTap: () => Navigator.pop(b, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library, color: kG1), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(b, ImageSource.gallery)),
      ]),
    ),
  );
  if (src == null) return;
  final x = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 85);
  if (x == null || !c.mounted) return;
  final kgS = await ask(c, 'Body weight in kg (optional)', numeric: true);
  final dir = Directory(p.join(await getDatabasesPath(), 'photos'));
  await dir.create(recursive: true);
  final now = DateTime.now();
  final path = p.join(dir.path, '${now.millisecondsSinceEpoch}.jpg');
  await File(x.path).copy(path);
  await DB.d.insert('photos', {'ts': now.millisecondsSinceEpoch, 'day': dk(now), 'path': path, 'kg': double.tryParse(kgS ?? '') ?? 0.0, 'note': ''});
  tick.value++;
}

void viewPhoto(BuildContext c, Map<String, Object?> ph) {
  showDialog<void>(
    context: c,
    builder: (d) => Dialog(
      backgroundColor: kCard,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: InteractiveViewer(child: Image.file(File(ph['path'] as String)))),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${ph['day']}${kgOf(ph) > 0 ? ' · ${kgOf(ph)} kg' : ''}'),
            TextButton.icon(
              onPressed: () async {
                await DB.d.delete('photos', where: 'id=?', whereArgs: [ph['id']]);
                try {
                  await File(ph['path'] as String).delete();
                } catch (_) {}
                tick.value++;
                if (d.mounted) Navigator.pop(d);
              },
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
              label: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ),
          ]),
        ),
      ]),
    ),
  );
}

class TransformPage extends StatelessWidget {
  const TransformPage({super.key});
  @override
  Widget build(BuildContext context) => Async<Rows>(() => DB.d.query('photos', orderBy: 'ts ASC'), (c, ps) {
        final first = ps.isNotEmpty ? ps.first : null;
        final last = ps.length > 1 ? ps.last : null;
        final kgs = [for (final x in ps) if (kgOf(x) > 0) kgOf(x)];
        final days = ps.length > 1 ? ((ps.last['ts'] as int) - (ps.first['ts'] as int)) ~/ 86400000 : 0;
        Widget slot(String l, Map<String, Object?>? ph) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(children: [
                  AspectRatio(aspectRatio: .75, child: GestureDetector(onTap: ph == null ? null : () => viewPhoto(c, ph), child: photo(ph))),
                  const SizedBox(height: 6),
                  Text(l, style: const TextStyle(color: kG1, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 12)),
                  Text(ph == null ? 'no photo yet' : '${ph['day']}${kgOf(ph) > 0 ? ' · ${kgOf(ph)} kg' : ''}', style: const TextStyle(color: kMu, fontSize: 12)),
                ]),
              ),
            );
        return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 120), children: [
          ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.asset('${img}transform_header.jpg', fit: BoxFit.cover)),
          const SizedBox(height: 14),
          Row(children: [slot('BEFORE', first), slot('LATEST', last)]),
          const SizedBox(height: 14),
          if (ps.length > 1)
            Row(children: [
              tile(Icons.calendar_today_rounded, '$days', 'Days in'),
              tile(Icons.photo_library_rounded, '${ps.length}', 'Photos'),
              if (kgs.length > 1) tile(Icons.monitor_weight_rounded, '${(kgs.last - kgs.first) > 0 ? '+' : ''}${(kgs.last - kgs.first).toStringAsFixed(1)}', 'kg change'),
            ]),
          if (ps.length > 1) const SizedBox(height: 14),
          gbtn('Add progress photo', () => addPhoto(c), i: Icons.add_a_photo_rounded),
          if (kgs.length > 1)
            card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ttl('Body weight', 'from your photo entries'),
              SizedBox(height: 120, width: double.infinity, child: CustomPaint(painter: TrendPainter(kgs))),
            ])),
          if (ps.isNotEmpty) ...[
            ttl('Timeline', 'tap a photo to open it'),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: .75,
              children: [for (final x in ps.reversed) GestureDetector(onTap: () => viewPhoto(c, x), child: photo(x))],
            ),
          ],
        ]);
      });
}

// ---------- profile ----------
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _PP();
}

class _PP extends State<ProfilePage> {
  final name = TextEditingController(), rest = TextEditingController(), goal = TextEditingController();
  St? st;
  String last = '';

  @override
  void initState() {
    super.initState();
    () async {
      last = await DB.kv('lastbackup') ?? '';
      name.text = await DB.kv('name') ?? '';
      rest.text = await DB.kv('rest') ?? '60';
      goal.text = await DB.kv('goal') ?? '4';
      st = await St.load();
      if (mounted) setState(() {});
    }();
  }

  Future<void> backup() async {
    final s = await exportBackup();
    await Clipboard.setData(ClipboardData(text: s));
    last = dk(DateTime.now());
    await DB.setKv('lastbackup', last);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup copied. Paste it into Notes or WhatsApp to keep it safe.')));
  }

  Future<void> restore() async {
    final clip = (await Clipboard.getData('text/plain'))?.text ?? '';
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Restore backup?'),
        content: const Text('This replaces your routines, weekly plan and workout history with the backup text you copied. Photos are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await importBackup(clip);
    final x = await St.load();
    if (!mounted) return;
    setState(() => st = x);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Backup restored ✔')));
  }

  Widget field(String l, TextEditingController c, String k, {bool n = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: n ? TextInputType.number : TextInputType.text,
          onChanged: (v) {
            DB.setKv(k, v);
            tick.value++;
          },
          decoration: InputDecoration(labelText: l, filled: true, fillColor: kBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = st;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 120), children: [
      card(Column(children: [
        field('Your name', name, 'name'),
        field('Rest between sets (seconds)', rest, 'rest', n: true),
        field('Weekly workout goal', goal, 'goal', n: true),
      ])),
      if (s != null)
        Row(children: [
          tile(Icons.local_fire_department_rounded, '${s.streak(s.wdays)}', 'Workout streak'),
          tile(Icons.event_available_rounded, '${s.lg.length}', 'Days logged in'),
          tile(Icons.emoji_events_rounded, '${s.ws.length}', 'Workouts'),
        ]),
      const SizedBox(height: 14),
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ttl('Backup & restore', last.isEmpty ? 'No backup yet' : 'Last backup: $last'),
        const Text('Copies your routines, weekly plan and full history as text. Paste it somewhere safe (Notes, WhatsApp). To restore, copy that text and tap Restore. Photos stay on this phone and are not in the backup.', style: TextStyle(color: kMu, fontSize: 12)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: gbtn('Copy backup', backup, i: Icons.copy_rounded)),
          const SizedBox(width: 10),
          Expanded(child: gbtn('Restore', restore, i: Icons.restore_rounded)),
        ]),
      ])),
      const Text('FitTrack v1.2 · all data is stored on this phone in a local SQLite database.', style: TextStyle(color: kMu, fontSize: 12), textAlign: TextAlign.center),
    ]);
  }
}
