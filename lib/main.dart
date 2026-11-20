import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const kBg = Color(0xFF040706);
const kCard = Color(0xFF0D1511);
const kG1 = Color(0xFF00E676);
const kG2 = Color(0xFF00A152);
const kMu = Color(0xFF86A194);
const kLine = Color(0x2200E676);
const kGrad = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kG1, kG2]);
final tick = ValueNotifier<int>(0);

String dk(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String fmt(int s) {
  String t(int n) => n.toString().padLeft(2, '0');
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, x = s % 60;
  return h > 0 ? '$h:${t(m)}:${t(x)}' : '${t(m)}:${t(x)}';
}

class DB {
  static late Database d;
  static Future<void> init() async {
    d = await openDatabase(p.join(await getDatabasesPath(), 'fittrack.db'), version: 1, onCreate: (db, v) async {
      await db.execute('CREATE TABLE kv(k TEXT PRIMARY KEY, v TEXT)');
      await db.execute('CREATE TABLE routines(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)');
      await db.execute('CREATE TABLE items(id INTEGER PRIMARY KEY AUTOINCREMENT, rid INTEGER, name TEXT, sets INTEGER, reps INTEGER)');
      await db.execute('CREATE TABLE workouts(id INTEGER PRIMARY KEY AUTOINCREMENT, day TEXT, ts INTEGER, routine TEXT, secs INTEGER)');
      await db.execute('CREATE TABLE sets(id INTEGER PRIMARY KEY AUTOINCREMENT, wid INTEGER, ex TEXT, reps INTEGER, kg REAL)');
      await db.execute('CREATE TABLE logins(day TEXT PRIMARY KEY)');
      final r = await db.insert('routines', {'name': 'Full Body'});
      for (final e in [['Push-ups', 3, 15], ['Squats', 3, 20], ['Lunges', 3, 12], ['Burpees', 3, 10]]) {
        await db.insert('items', {'rid': r, 'name': e[0], 'sets': e[1], 'reps': e[2]});
      }
    });
  }

  static Future<String?> kv(String k) async {
    final r = await d.query('kv', where: 'k=?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as String?;
  }

  static Future<void> setKv(String k, String v) async {
    await d.insert('kv', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

class St {
  final List<Map<String, Object?>> ws, ss;
  final Set<String> lg;
  St(this.ws, this.ss, this.lg);
  static Future<St> load() async => St(
        await DB.d.query('workouts'),
        await DB.d.rawQuery('SELECT s.ex, s.reps, s.kg, w.day FROM sets s JOIN workouts w ON w.id=s.wid'),
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
        home: const Shell(),
      );
}

// ---------- shared widgets ----------
Widget bg(Widget child) => Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0B2A1B), kBg], stops: [0, .5])),
      child: child,
    );

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
          Text(l, style: const TextStyle(color: kMu, fontSize: 12)),
        ]),
      ),
    );

Widget hs(IconData i, String v, String l) => Expanded(
      child: Column(children: [
        Icon(i, color: Colors.black, size: 30),
        Text(v, style: const TextStyle(color: Colors.black, fontSize: 34, fontWeight: FontWeight.w900)),
        Text(l, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
      ]),
    );

Widget h1(String t) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(t, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)));

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
      content: TextField(controller: ctl, autofocus: true, keyboardType: numeric ? TextInputType.number : TextInputType.text, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

Future<List<String>?> askItem(BuildContext c) {
  final n = TextEditingController(), s = TextEditingController(text: '3'), r = TextEditingController(text: '12');
  return showDialog<List<String>>(
    context: c,
    builder: (d) => AlertDialog(
      backgroundColor: kCard,
      title: const Text('Add exercise'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: n, autofocus: true, decoration: const InputDecoration(labelText: 'Exercise name')),
        TextField(controller: s, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sets')),
        TextField(controller: r, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Reps')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(d, [n.text.trim(), s.text, r.text]), child: const Text('Add')),
      ],
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
      final full = s.height - 22;
      var h = full * v[i] / mx;
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
    final rect = Rect.fromLTWH(0, 0, s.width, s.height);
    c.drawPath(fill, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x6600E676), Color(0x0000E676)]).createShader(rect));
    c.drawPath(path, Paint()..color = kG1..style = PaintingStyle.stroke..strokeWidth = 3..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}

// ---------- shell with floating nav ----------
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;
  Widget nav(int k) {
    const ic = [Icons.home_rounded, Icons.list_alt_rounded, Icons.insights_rounded, Icons.person_rounded];
    final on = i == k;
    return GestureDetector(
      onTap: () => setState(() => i = k),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(gradient: on ? kGrad : null, shape: BoxShape.circle),
        child: Icon(ic[k], color: on ? Colors.black : kMu),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const HomePage(), const RoutinesPage(), const StatsPage(), const ProfilePage()];
    return Scaffold(
      extendBody: true,
      body: bg(SafeArea(bottom: false, child: pages[i])),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
        child: Container(
          height: 70,
          decoration: BoxDecoration(color: const Color(0xF2111B16), borderRadius: BorderRadius.circular(35), border: Border.all(color: const Color(0x4000E676)), boxShadow: const [BoxShadow(color: Color(0x3000E676), blurRadius: 26)]),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [for (var k = 0; k < 4; k++) nav(k)]),
        ),
      ),
    );
  }
}

// ---------- home ----------
Future<void> pickRoutine(BuildContext c) async {
  final rs = await DB.d.query('routines');
  if (!c.mounted) return;
  showModalBottomSheet(
    context: c,
    backgroundColor: kCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (b) => Padding(
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
              Navigator.push(c, MaterialPageRoute(builder: (_) => WorkoutPage(r['name'] as String, it)));
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
        () async => [await St.load(), await DB.kv('name'), int.tryParse(await DB.kv('goal') ?? '') ?? 4],
        (c, d) {
          final st = d[0] as St;
          final name = ((d[1] as String?) ?? '').trim();
          var goal = d[2] as int;
          if (goal < 1) goal = 1;
          final ds = st.days(7);
          const wd = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
          final week = ds.where((x) => st.wdays.contains(dk(x))).length;
          final secs = st.ws.fold<int>(0, (a, e) => a + (e['secs'] as int));
          final reps = st.ss.fold<int>(0, (a, e) => a + (e['reps'] as int));
          return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 120), children: [
            const Text('Welcome back,', style: TextStyle(color: kMu)),
            Text(name.isEmpty ? 'Athlete' : name, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            card(Row(children: [
              hs(Icons.local_fire_department_rounded, '${st.streak(st.wdays)}', 'Workout streak'),
              Container(width: 1, height: 60, color: Colors.black26),
              hs(Icons.event_available_rounded, '${st.streak(st.lg)}', 'Login streak'),
            ]), g: kGrad),
            gbtn('Start workout', () => pickRoutine(c), i: Icons.play_arrow_rounded),
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
              tile(Icons.repeat_rounded, '$reps', 'Total reps'),
              tile(Icons.timer_outlined, '${(secs / 60).round()}m', 'Time'),
            ]),
          ]);
        },
      );
}

// ---------- workout session ----------
class WorkoutPage extends StatefulWidget {
  final String name;
  final List<Map<String, Object?>> items;
  const WorkoutPage(this.name, this.items, {super.key});
  @override
  State<WorkoutPage> createState() => _WS();
}

class _WS extends State<WorkoutPage> {
  late List<String> exs;
  final Map<String, int> target = {};
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
    final n = await ask(context, 'Exercise name', hint: 'e.g. Pull-ups');
    if (n != null && n.isNotEmpty) {
      setState(() {
        exs.add(n);
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
      logged.add({'ex': exs[ei], 'reps': reps, 'kg': double.tryParse(kg.text) ?? 0.0});
      reps = 0;
      restLeft = rest;
    });
    HapticFeedback.mediumImpact();
  }

  Future<void> finish() async {
    if (logged.isNotEmpty) {
      final now = DateTime.now();
      final id = await DB.d.insert('workouts', {'day': dk(now), 'ts': now.millisecondsSinceEpoch, 'routine': widget.name, 'secs': sw.elapsed.inSeconds});
      final b = DB.d.batch();
      for (final s in logged) {
        b.insert('sets', {...s, 'wid': id});
      }
      await b.commit(noResult: true);
      tick.value++;
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ex = exs.isEmpty ? null : exs[ei];
    final done = ex == null ? 0 : logged.where((s) => s['ex'] == ex).length;
    return Scaffold(
      body: bg(SafeArea(
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
      )),
    );
  }
}

// ---------- routines ----------
class RoutinesPage extends StatelessWidget {
  const RoutinesPage({super.key});
  @override
  Widget build(BuildContext context) => Async<List<Map<String, Object?>>>(
        () async {
          final rs = await DB.d.query('routines');
          final out = <Map<String, Object?>>[];
          for (final r in rs) {
            final it = await DB.d.query('items', where: 'rid=?', whereArgs: [r['id']]);
            out.add({'id': r['id'], 'name': r['name'], 'n': it.map((e) => e['name']).join(', ')});
          }
          return out;
        },
        (c, rs) => ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 120), children: [
          h1('Routines'),
          gbtn('New routine', () => Navigator.push(c, MaterialPageRoute(builder: (_) => const RoutineEditor(null))), i: Icons.add_rounded),
          for (final r in rs)
            GestureDetector(
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => RoutineEditor(r['id'] as int))),
              child: card(Row(children: [
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(gradient: kGrad, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.fitness_center, color: Colors.black)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(r['n'] == '' ? 'No exercises yet' : '${r['n']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMu, fontSize: 13)),
                ])),
                const Icon(Icons.edit_outlined, color: kMu),
              ])),
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
  List<Map<String, Object?>> items = [];

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
      setState(() => items.add({'name': v[0], 'sets': int.tryParse(v[1]) ?? 3, 'reps': int.tryParse(v[2]) ?? 10}));
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
      await DB.d.insert('items', {'rid': rid, 'name': i['name'], 'sets': i['sets'], 'reps': i['reps']});
    }
    tick.value++;
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> del() async {
    await DB.d.delete('items', where: 'rid=?', whereArgs: [widget.id]);
    await DB.d.delete('routines', where: 'id=?', whereArgs: [widget.id]);
    tick.value++;
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: bg(SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back)),
              const Expanded(child: Text('Routine', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
              if (widget.id != null) IconButton(onPressed: del, icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
            ]),
            const SizedBox(height: 10),
            TextField(controller: name, decoration: InputDecoration(labelText: 'Routine name', filled: true, fillColor: kCard, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
            const SizedBox(height: 16),
            for (var i = 0; i < items.length; i++)
              card(Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${items[i]['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text('${items[i]['sets']} sets × ${items[i]['reps']} reps', style: const TextStyle(color: kMu)),
                ])),
                IconButton(onPressed: () => setState(() => items.removeAt(i)), icon: const Icon(Icons.close, color: kMu)),
              ])),
            gbtn('Add exercise', add, i: Icons.add_rounded),
            gbtn('Save routine', save, i: Icons.check_rounded),
          ]),
        )),
      );
}

// ---------- stats ----------
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});
  @override
  Widget build(BuildContext context) => Async<St>(St.load, (c, st) {
        final w7 = st.days(7), d30 = st.days(30), d28 = st.days(28);
        const wd = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
        final m = <String, int>{};
        for (final s in st.ss) {
          final k = s['ex'] as String;
          m[k] = (m[k] ?? 0) + (s['reps'] as int);
        }
        final top = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final mx = top.isEmpty ? 1 : top.first.value;
        return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 120), children: [
          h1('Progress'),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Reps per day · last 7 days', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SizedBox(height: 130, width: double.infinity, child: CustomPaint(painter: BarsPainter([for (final x in w7) st.reps(dk(x))], [for (final x in w7) wd[x.weekday - 1]]))),
          ])),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Reps trend · last 30 days', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SizedBox(height: 130, width: double.infinity, child: CustomPaint(painter: TrendPainter([for (final x in d30) st.reps(dk(x))]))),
          ])),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Top exercises · total reps', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (top.isEmpty) const Text('Finish a workout to see charts.', style: TextStyle(color: kMu)),
            for (final e in top.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(e.key), Text('${e.value}', style: const TextStyle(color: kG1, fontWeight: FontWeight.w800))]),
                  const SizedBox(height: 4),
                  FractionallySizedBox(widthFactor: e.value / mx, child: Container(height: 8, decoration: BoxDecoration(gradient: kGrad, borderRadius: BorderRadius.circular(6)))),
                ]),
              ),
          ])),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Streak calendar · last 28 days', style: TextStyle(fontWeight: FontWeight.w800)),
            const Text('bright = workout, dim = opened app', style: TextStyle(color: kMu, fontSize: 11)),
            const SizedBox(height: 12),
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

  @override
  void initState() {
    super.initState();
    () async {
      name.text = await DB.kv('name') ?? '';
      rest.text = await DB.kv('rest') ?? '60';
      goal.text = await DB.kv('goal') ?? '4';
      st = await St.load();
      if (mounted) setState(() {});
    }();
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
    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 120), children: [
      h1('Profile'),
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
      const Text('All data is stored on this phone in a local SQLite database.', style: TextStyle(color: kMu, fontSize: 12), textAlign: TextAlign.center),
    ]);
  }
}
