import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show FlutterLocalNotificationsPlugin, InitializationSettings, AndroidInitializationSettings, AndroidFlutterLocalNotificationsPlugin, NotificationDetails, AndroidNotificationDetails, Importance, Priority, AndroidScheduleMode, DateTimeComponents;
import 'package:google_mobile_ads/google_mobile_ads.dart' show MobileAds, InterstitialAd, InterstitialAdLoadCallback, AdRequest, FullScreenContentCallback;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' show YoutubePlayer, YoutubePlayerController, YoutubePlayerParams;
import 'exercise_data.dart';

// ---------- theme / palette ----------
class P {
  static bool dark = true;
  static bool vy = false; // Vytron Gold look
  static const gold = Color(0xFFD6B66C);
  static const emerald = Color(0xFF00D878);
  static Color get goldx => (vy || dark) ? gold : const Color(0xFF9A7418);
  static Color get bg => vy ? const Color(0xFF050807) : dark ? const Color(0xFF040706) : const Color(0xFFF1F7F3);
  static Color get card => vy ? const Color(0xFF0A100D) : dark ? const Color(0xFF0D1511) : Colors.white;
  static Color get soft => vy ? const Color(0xFF131B17) : dark ? const Color(0xFF16201B) : const Color(0xFFE4EEE8);
  static Color get mu => vy ? const Color(0xFF9BA7A1) : dark ? const Color(0xFF86A194) : const Color(0xFF55705F);
  static Color get ac => vy ? emerald : dark ? const Color(0xFF00E676) : const Color(0xFF008F4A);
  static Color get line => vy ? const Color(0x33D6B66C) : dark ? const Color(0x2200E676) : const Color(0x3300A152);
  static Color get hdr => vy ? const Color(0xFF07130D) : dark ? const Color(0xFF0B2A1B) : const Color(0xFFCDEFDC);
  static Color get nav => vy ? const Color(0xF20A100D) : dark ? const Color(0xF2111B16) : const Color(0xF2FFFFFF);
  static LinearGradient get hero => vy
      ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0C2A1D), Color(0xFF0A100D)])
      : dark
          ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF14432C), Color(0xFF0D1511)])
          : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFD3F4E1), Colors.white]);
  static LinearGradient get grad => vy ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF00E58A), Color(0xFF00A862)]) : kGrad;
  static LinearGradient get igrad => vy ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF0D894), Color(0xFFC9A55A)]) : kGrad;
}

const kG1 = Color(0xFF00E676);
const kG2 = Color(0xFF00A152);
const kGrad = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kG1, kG2]);
const img = 'assets/images/';
const dn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const muscles = ['Chest', 'Back', 'Shoulders', 'Arms', 'Legs', 'Core', 'Cardio', 'Combat', 'Mobility', 'Other'];
const mColors = [Color(0xFF00E676), Color(0xFF00BFA5), Color(0xFFB2FF59), Color(0xFF64FFDA), Color(0xFF69F0AE), Color(0xFF76FF03), Color(0xFF1DE9B6), Color(0xFFFFB300), Color(0xFF40C4FF), Color(0xFF86A194)];
final tick = ValueNotifier<int>(0);
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);
final styleMode = ValueNotifier<int>(0); // 0 = Classic, 1 = Vytron Gold

typedef Rows = List<Map<String, Object?>>;

TextStyle ts(double s, {FontWeight w = FontWeight.w400, Color? c, double? ls}) => TextStyle(fontSize: s, fontWeight: w, color: c, letterSpacing: ls);

void applyMode(ThemeMode m) {
  P.dark = P.vy || m == ThemeMode.dark || (m == ThemeMode.system && WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: P.dark ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: P.bg,
    systemNavigationBarIconBrightness: P.dark ? Brightness.light : Brightness.dark,
  ));
}

Future<void> setTheme(ThemeMode m, {bool save = true}) async {
  applyMode(m);
  themeMode.value = m;
  if (save) await DB.setKv('theme', m == ThemeMode.light ? 'light' : m == ThemeMode.system ? 'system' : 'dark');
}

Future<void> setStyle(int v, {bool save = true}) async {
  P.vy = v == 1;
  styleMode.value = v;
  applyMode(themeMode.value);
  if (save) await DB.setKv('ui', v == 1 ? 'vytron' : 'classic');
}

Future<void> loadTheme() async {
  P.vy = (await DB.kv('ui')) == 'vytron';
  styleMode.value = P.vy ? 1 : 0;
  final v = await DB.kv('theme');
  await setTheme(v == 'light' ? ThemeMode.light : v == 'system' ? ThemeMode.system : ThemeMode.dark, save: false);
}

// ---------- voice coach (v1.6.3): the app speaks, it never listens ----------
class Voice {
  static final FlutterTts _t = FlutterTts();
  static bool on = true;
  static bool _ready = false;

  static Future<void> load() async {
    on = (await DB.kv('voice')) != '0';
  }

  static Future<void> setOn(bool v) async {
    on = v;
    await DB.setKv('voice', v ? '1' : '0');
    if (!v) await stop();
  }

  static Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    try {
      await _t.setLanguage('en-US');
      await _t.setPitch(0.5);
      await _t.setSpeechRate(0.42);
      await _t.setVolume(1.0);
      try {
        await _t.setAudioAttributesForNavigation();
      } catch (_) {}
      final vs = await _t.getVoices;
      if (vs is List) {
        final all = <Map<String, String>>[];
        for (final v in vs) {
          if (v is Map) {
            all.add({'name': '${v['name']}', 'locale': '${v['locale']}'});
          }
        }
        const best = ['en-us-x-iom-local', 'en-us-x-iol-local', 'en-us-x-tpd-local', 'en-gb-x-rjs-local', 'en-gb-x-gbb-local', 'en-gb-x-gbd-local'];
        Map<String, String>? pick;
        for (final b in best) {
          for (final v in all) {
            if (v['name']!.toLowerCase() == b) pick = v;
          }
          if (pick != null) break;
        }
        if (pick == null) {
          for (final v in all) {
            final n = v['name']!.toLowerCase();
            if (n.contains('male') && !n.contains('female') && (v['locale'] ?? '').toLowerCase().startsWith('en')) {
              pick = v;
              break;
            }
          }
        }
        if (pick != null) await _t.setVoice(pick);
      }
    } catch (_) {}
  }

  static Future<void> say(String text) async {
    if (!on) return;
    try {
      await _init();
      await _t.stop();
      await _t.speak(text, focus: true);
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _t.stop();
    } catch (_) {}
  }
}

String dk(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String fmt(int s) {
  String t(int n) => n.toString().padLeft(2, '0');
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, x = s % 60;
  return h > 0 ? '$h:${t(m)}:${t(x)}' : '${t(m)}:${t(x)}';
}

bool timedName(String n) {
  final s = n.toLowerCase();
  if (s.endsWith(' round')) return true;
  return ['plank', 'wall sit', 'dead hang', 'l-sit', 'hold', 'stretch', 'isometric', 'pose', 'rounds', 'shadow', 'heavy bag', 'sparring', 'splits', 'foam roll'].any((x) => s.contains(x));
}

String tf(int s) => s >= 60 ? '${s ~/ 60}m ${s % 60}s' : '${s}s';
String amtOf(Map<String, Object?> s) => s['kind'] == 'time' ? tf(s['reps'] as int) : '${s['reps']} reps';
String perSet(Map<String, Object?> m) => m['kind'] == 'time' ? tf(m['reps'] as int) : '${m['reps']} reps';

Color mc(String m) {
  final i = muscles.indexOf(m);
  final c = mColors[i < 0 ? mColors.length - 1 : i];
  return P.dark ? c : HSLColor.fromColor(c).withLightness(.3).toColor();
}

String guess(String n) {
  final s = n.toLowerCase();
  bool h(List<String> k) => k.any((x) => s.contains(x));
  if (h(['stretch', 'mobility', 'yoga', 'flexib', 'pigeon', 'foam roll', 'splits', ' pose', 'cat-cow', 'cat cow', 'child pose', 'hip circles', 'leg swing'])) return 'Mobility';
  if (!s.contains('kickback') && (h(['punch', 'jab', 'hook', 'uppercut', 'kick', 'shadow', 'boxing', 'sparring', 'guard', 'defen', 'parry', 'slip', 'bob &', 'bob and', 'weave', 'sprawl', 'elbow strike', 'knee strike', 'teep', 'heavy bag', 'pad work', 'mitt', 'muay', 'clinch']) || s == 'cross' || s.startsWith('cross '))) return 'Combat';
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
  return top == 'Legs' ? 'legs' : (top == 'Core' || top == 'Mobility') ? 'core' : (top == 'Cardio' || top == 'Combat') ? 'cardio' : 'upper';
}

// ---------- database ----------
class DB {
  static late Database d;
  static const schedSql = 'CREATE TABLE schedule(day INTEGER, slot INTEGER, rid INTEGER, PRIMARY KEY(day, slot))';
  static const warmSql = 'CREATE TABLE warmups(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, amt INTEGER, kind TEXT, pos INTEGER)';
  static const flexSql = 'CREATE TABLE flex(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, url TEXT, amt INTEGER, kind TEXT, note TEXT)';
  static const linkSql = 'CREATE TABLE exlinks(name TEXT PRIMARY KEY, url TEXT)';
  static const photoSql = 'CREATE TABLE photos(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER, day TEXT, path TEXT, kg REAL, note TEXT)';

  static Future<void> init() async {
    d = await openDatabase(
      p.join(await getDatabasesPath(), 'fittrack.db'),
      version: 7,
      onCreate: (db, v) async {
        await db.execute('CREATE TABLE kv(k TEXT PRIMARY KEY, v TEXT)');
        await db.execute('CREATE TABLE routines(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, flex_when TEXT, flex_ids TEXT, music TEXT)');
        await db.execute('CREATE TABLE items(id INTEGER PRIMARY KEY AUTOINCREMENT, rid INTEGER, name TEXT, sets INTEGER, reps INTEGER, muscle TEXT, kind TEXT, sec TEXT)');
        await db.execute('CREATE TABLE workouts(id INTEGER PRIMARY KEY AUTOINCREMENT, day TEXT, ts INTEGER, routine TEXT, secs INTEGER)');
        await db.execute('CREATE TABLE sets(id INTEGER PRIMARY KEY AUTOINCREMENT, wid INTEGER, ex TEXT, reps INTEGER, kg REAL, muscle TEXT, kind TEXT)');
        await db.execute('CREATE TABLE logins(day TEXT PRIMARY KEY)');
        await db.execute(schedSql);
        await db.execute(photoSql);
        await db.execute(warmSql);
        await seedWarm(db);
        await db.execute(flexSql);
        await db.execute(linkSql);
        await seedFlex(db);
        await seed(db, fresh: true);
      },
      onUpgrade: (db, o, n) async {
        if (o < 2) {
          await db.execute('ALTER TABLE items ADD COLUMN muscle TEXT');
          await db.execute('ALTER TABLE sets ADD COLUMN muscle TEXT');
          await db.execute(schedSql);
          await db.execute(photoSql);
          for (final r in await db.query('items')) {
            await db.update('items', {'muscle': guess(r['name'] as String)}, where: 'id=?', whereArgs: [r['id']]);
          }
          for (final r in await db.query('sets')) {
            await db.update('sets', {'muscle': guess(r['ex'] as String)}, where: 'id=?', whereArgs: [r['id']]);
          }
        } else if (o < 3) {
          await db.execute('ALTER TABLE schedule RENAME TO schedule_old');
          await db.execute(schedSql);
          await db.execute('INSERT INTO schedule(day, slot, rid) SELECT day, 0, rid FROM schedule_old');
          await db.execute('DROP TABLE schedule_old');
        }
        if (o < 4) {
          await db.execute('ALTER TABLE items ADD COLUMN kind TEXT');
          await db.execute('ALTER TABLE sets ADD COLUMN kind TEXT');
          await db.execute("UPDATE items SET kind='time' WHERE lower(name) LIKE '%plank%'");
          if (o >= 2) {
            final rs = await db.query('routines', where: 'name=?', whereArgs: ['Core & Cardio']);
            for (final r in rs) {
              final has = await db.query('items', where: "rid=? AND lower(name) LIKE '%plank%'", whereArgs: [r['id']]);
              if (has.isEmpty) await db.insert('items', {'rid': r['id'], 'name': 'Plank', 'sets': 3, 'reps': 45, 'muscle': 'Core', 'kind': 'time'});
            }
          }
        }
        if (o < 5) {
          await db.execute(warmSql);
          await seedWarm(db);
        }
        if (o < 7 && o >= 6) await db.execute('ALTER TABLE routines ADD COLUMN music TEXT');
        if (o < 6) {
          await db.execute('ALTER TABLE items ADD COLUMN sec TEXT');
          await db.execute('ALTER TABLE routines ADD COLUMN flex_when TEXT');
          await db.execute('ALTER TABLE routines ADD COLUMN flex_ids TEXT');
          await db.execute('ALTER TABLE routines ADD COLUMN music TEXT');
          await db.execute(flexSql);
          await db.execute(linkSql);
          await seedFlex(db);
          for (final r in await db.query('items', where: "muscle IS NULL OR muscle='Other'")) {
            final g = guess(r['name'] as String);
            if (g != 'Other') await db.update('items', {'muscle': g}, where: 'id=?', whereArgs: [r['id']]);
          }
          for (final r in await db.query('sets', where: "muscle IS NULL OR muscle='Other'")) {
            final g = guess(r['ex'] as String);
            if (g != 'Other') await db.update('sets', {'muscle': g}, where: 'id=?', whereArgs: [r['id']]);
          }
        }
        if (o < 2) await seed(db, fresh: false);
      },
    );
  }

  static Future<void> seedWarm(Database db) async {
    const w = [
      ['Jumping jacks', 30, 'time'],
      ['Arm circles', 30, 'time'],
      ['High knees', 30, 'time'],
      ['Hip rotations', 20, 'time'],
      ['Bodyweight squats', 10, 'reps'],
    ];
    for (var i = 0; i < w.length; i++) {
      await db.insert('warmups', {'name': w[i][0], 'amt': w[i][1], 'kind': w[i][2], 'pos': i});
    }
  }

  static Future<void> seedFlex(Database db) async {
    if ((await db.query('flex')).isNotEmpty) return;
    const w = [
      ['Hamstring stretch', 30],
      ['Quad stretch', 30],
      ['Hip flexor stretch', 30],
      ['Butterfly stretch', 30],
      ['Pigeon pose', 40],
      ['Cossack stretch', 30],
      ['Calf stretch', 30],
      ['Cross-body shoulder stretch', 30],
      ['Doorway chest stretch', 30],
      ['Thoracic rotation', 30],
      ['Cat-cow', 30],
      ['Child pose', 40],
      ['Leg swings front', 20],
      ['Leg swings side', 20],
      ['Hip circles', 20],
    ];
    for (final e in w) {
      await db.insert('flex', {'name': e[0], 'url': '', 'amt': e[1], 'kind': 'time', 'note': ''});
    }
  }

  static Future<void> seed(Database db, {required bool fresh}) async {
    Future<void> mk(String n, List<List<Object>> it) async {
      final r = await db.insert('routines', {'name': n});
      for (final e in it) {
        await db.insert('items', {'rid': r, 'name': e[0], 'sets': e[1], 'reps': e[2], 'muscle': e[3], 'kind': e.length > 4 ? e[4] : 'reps'});
      }
    }

    if (fresh) await mk('Full Body', [['Push-ups', 3, 15, 'Chest'], ['Squats', 3, 20, 'Legs'], ['Lunges', 3, 12, 'Legs'], ['Burpees', 3, 10, 'Cardio']]);
    await mk('Chest & Triceps', [['Bench Press', 4, 10, 'Chest'], ['Push-ups', 3, 15, 'Chest'], ['Shoulder Press', 3, 10, 'Shoulders'], ['Tricep Dips', 3, 12, 'Arms']]);
    await mk('Back & Biceps', [['Pull-ups', 3, 8, 'Back'], ['Barbell Row', 4, 10, 'Back'], ['Deadlift', 3, 6, 'Back'], ['Bicep Curls', 3, 12, 'Arms']]);
    await mk('Leg Day', [['Squats', 4, 12, 'Legs'], ['Lunges', 3, 12, 'Legs'], ['Leg Press', 3, 12, 'Legs'], ['Calf Raises', 4, 15, 'Legs']]);
    await mk('Core & Cardio', [['Crunches', 3, 20, 'Core'], ['Plank', 3, 45, 'Core', 'time'], ['Leg Raises', 3, 15, 'Core'], ['Burpees', 3, 10, 'Cardio'], ['Mountain Climbers', 3, 30, 'Cardio']]);
    final ids = {for (final r in await db.query('routines')) r['name'] as String: r['id'] as int};
    const plan = {1: 'Chest & Triceps', 2: 'Back & Biceps', 3: 'Leg Day', 4: 'Core & Cardio', 5: 'Full Body'};
    for (var d = 1; d <= 7; d++) {
      await db.insert('schedule', {'day': d, 'slot': 0, 'rid': ids[plan[d]] ?? 0}, conflictAlgorithm: ConflictAlgorithm.replace);
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

Future<Rows> warmList() async => (await DB.d.query('warmups', orderBy: 'pos, id')).toList();

Future<Rows> flexAll() async => (await DB.d.query('flex', orderBy: 'id')).toList();

Future<Map<String, Object?>> flexPlan(int? rid) async {
  final none = <String, Object?>{'when': 'none', 'rows': <Map<String, Object?>>[]};
  if (rid == null) return none;
  final r = await DB.d.query('routines', where: 'id=?', whereArgs: [rid]);
  if (r.isEmpty) return none;
  final w = (r.first['flex_when'] as String?) ?? 'none';
  final ids = <int>[];
  for (final x in ((r.first['flex_ids'] as String?) ?? '').split(',')) {
    final n = int.tryParse(x);
    if (n != null) ids.add(n);
  }
  final all = await flexAll();
  final rows = <Map<String, Object?>>[];
  for (final i in ids) {
    for (final f in all) {
      if (f['id'] == i) rows.add(f);
    }
  }
  return {'when': w, 'rows': rows};
}

Future<void> runSession(BuildContext c, String name, Rows items, {int? rid}) async {
  final fx = await flexPlan(rid);
  final rows = fx['rows'] as Rows;
  final when = fx['when'] as String;
  if (!c.mounted) return;
  if (when == 'before' && rows.isNotEmpty) {
    await Navigator.push<bool>(c, MaterialPageRoute<bool>(builder: (_) => FlexSessionPage('Flexibility · before', rows)));
    if (!c.mounted) return;
  }
  var music = '';
  if (rid != null) {
    final mr = await DB.d.query('routines', columns: ['music'], where: 'id=?', whereArgs: [rid]);
    if (mr.isNotEmpty) music = (mr.first['music'] as String?) ?? '';
  }
  if (!c.mounted) return;
  final done = await Navigator.push<bool>(c, MaterialPageRoute<bool>(builder: (_) => WorkoutPage(name, items, music: music)));
  if (done == true && when == 'after' && rows.isNotEmpty && c.mounted) {
    await Navigator.push<bool>(c, MaterialPageRoute<bool>(builder: (_) => FlexSessionPage('Flexibility · after', rows)));
  }
}

String? ytId(String url) {
  final m = RegExp(r'(?:youtu\.be/|youtube(?:-nocookie)?\.com/(?:watch\?(?:.*&)?v=|embed/|shorts/|live/|v/))([A-Za-z0-9_-]{11})').firstMatch(url);
  return m?.group(1);
}

Future<void> openLink(BuildContext c, String url, {bool workout = false}) async {
  var u = url.trim();
  if (u.isEmpty) return;
  if (!u.startsWith('http')) u = 'https://$u';
  final id = ytId(u);
  if (id != null && (await DB.kv('embed')) != '0') {
    if (!c.mounted) return;
    await Navigator.push<void>(c, MaterialPageRoute<void>(builder: (_) => VideoPage(url: u, id: id, workout: workout)));
    return;
  }
  await openExternal(c, u);
}

Future<void> openExternal(BuildContext c, String u) async {
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && c.mounted) {
    await Clipboard.setData(ClipboardData(text: u));
    if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Could not open the link. It was copied instead.')));
  }
}

Future<void> saveLink(String name, String url) async {
  if (url.trim().isEmpty) {
    await DB.d.delete('exlinks', where: 'name=?', whereArgs: [name]);
  } else {
    await DB.d.insert('exlinks', {'name': name, 'url': url.trim()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<String?> askLink(BuildContext c, String title, String cur) {
  final ctl = TextEditingController(text: cur);
  return showDialog<String>(
    context: c,
    builder: (d) => AlertDialog(
      backgroundColor: P.card,
      title: Text(title),
      content: TextField(controller: ctl, keyboardType: TextInputType.url, decoration: fld('YouTube link')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        if (cur.isNotEmpty) TextButton(onPressed: () => Navigator.pop(d, ''), child: const Text('Remove')),
        TextButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}

Future<Map<String, Object?>?> planFor(int wd, int slot) async {
  final s = await DB.d.query('schedule', where: 'day=? AND slot=?', whereArgs: [wd, slot]);
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
        await DB.d.rawQuery('SELECT s.wid, s.ex, s.reps, s.kg, s.muscle, s.kind, w.day FROM sets s JOIN workouts w ON w.id=s.wid'),
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
  double reps(String d) => ss.where((e) => e['day'] == d && e['kind'] != 'time').fold<double>(0, (a, e) => a + (e['reps'] as int));
  int get totalReps => ss.where((e) => e['kind'] != 'time').fold<int>(0, (a, e) => a + (e['reps'] as int));
  Map<String, int> byMuscle() {
    final m = <String, int>{};
    for (final s in ss) {
      final k = (s['muscle'] as String?) ?? guess(s['ex'] as String);
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }
}

// ---------- backup (data + photos in one file) ----------
const bkTables = ['kv', 'routines', 'items', 'workouts', 'sets', 'logins', 'schedule', 'warmups', 'flex', 'exlinks'];

Future<String> buildBackup() async {
  final o = <String, Object?>{'app': 'fittrack', 'v': 5};
  for (final t in bkTables) {
    o[t] = await DB.d.query(t);
  }
  final ph = <Map<String, Object?>>[];
  for (final r in await DB.d.query('photos')) {
    final m = Map<String, Object?>.from(r);
    try {
      m['b64'] = base64Encode(await File(m['path'] as String).readAsBytes());
    } catch (_) {
      continue;
    }
    m.remove('path');
    m.remove('id');
    ph.add(m);
  }
  o['photos'] = ph;
  return jsonEncode(o);
}

Future<String?> importBackup(String s) async {
  try {
    final o = jsonDecode(s) as Map<String, dynamic>;
    if (o['app'] != 'fittrack') return 'That is not a Vytron Fit backup.';
    final dir = Directory(p.join(await getDatabasesPath(), 'photos'));
    await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final rows = <Map<String, Object?>>[];
    var n = 0;
    for (final r in (o['photos'] as List? ?? [])) {
      final m = Map<String, Object?>.from(r as Map);
      final path = p.join(dir.path, 'r${stamp}_${n++}.jpg');
      await File(path).writeAsBytes(base64Decode(m.remove('b64') as String));
      m['path'] = path;
      rows.add(m);
    }
    final old = await DB.d.query('photos');
    await DB.d.transaction((tx) async {
      for (final t in bkTables) {
        final list = o[t] as List?;
        if (list == null && (t == 'warmups' || t == 'flex' || t == 'exlinks')) continue;
        await tx.delete(t);
        final cols = (await tx.rawQuery('PRAGMA table_info($t)')).map((c) => c['name'] as String).toSet();
        for (final r in (list ?? [])) {
          final m = Map<String, Object?>.from(r as Map);
          if (t == 'schedule') m.putIfAbsent('slot', () => 0);
          m.removeWhere((k, _) => !cols.contains(k));
          await tx.insert(t, m);
        }
      }
      await tx.delete('photos');
      for (final m in rows) {
        await tx.insert('photos', m);
      }
    });
    for (final r in old) {
      try {
        await File(r['path'] as String).delete();
      } catch (_) {}
    }
    await loadTheme();
    tick.value++;
    return null;
  } catch (e) {
    return 'Could not read that backup file.';
  }
}

// ---------- AI workout builder (v1.6.2) ----------
const aiPrompt = r"""You are a strength, boxing and flexibility coach building workouts for my app "Vytron Fit".
Reply with ONLY one JSON object inside a single code block and no other text, in exactly this format:
{"app":"vytron-fit-ai","routines":[{"name":"Routine name","items":[{"name":"Exercise name","sets":3,"reps":12,"kind":"reps","muscle":"Chest","section":"Strength","url":"https://www.youtube.com/watch?v=VIDEOID"}]}]}
Rules:
- kind is "reps" or "time". For "time" (planks, holds, stretches) reps means seconds.
- muscle must be one of: Chest, Back, Shoulders, Arms, Legs, Core, Cardio, Combat, Mobility, Other.
- section groups exercises inside one workout (for example Strength, then Defence). Keep exercises of the same section together, in the order I do them.
- url must be a real YouTube tutorial link for that exercise that allows embedding (a normal youtube.com/watch?v= link). If you are not sure a link is real, leave url empty. Never invent a video id.
- Reuse my exercise names and links from the list below when it is the same exercise.
- Keep my current routines unless I ask you to change them.
MY REQUEST: (write here what you want, for example: a 4-day plan with boxing defence after strength)
MY CURRENT ROUTINES:
""";

Future<String> aiExport() async {
  final links = {for (final x in await DB.d.query('exlinks')) x['name'] as String: (x['url'] as String?) ?? ''};
  final out = <Map<String, Object?>>[];
  for (final r in await DB.d.query('routines')) {
    final it = await DB.d.query('items', where: 'rid=?', whereArgs: [r['id']], orderBy: 'id');
    final list = <Map<String, Object?>>[];
    for (final i in it) {
      final n = i['name'] as String;
      list.add({
        'name': n,
        'sets': i['sets'],
        'reps': i['reps'],
        'kind': i['kind'] ?? 'reps',
        'muscle': i['muscle'] ?? guess(n),
        'section': i['sec'] ?? '',
        if ((links[n] ?? '').isNotEmpty) 'url': links[n],
      });
    }
    out.add({'name': r['name'], 'items': list});
  }
  return jsonEncode({'app': 'vytron-fit-ai', 'routines': out});
}

Future<String> aiImport(String text) async {
  try {
    final t = text.trim();
    final a = t.indexOf('{'), b = t.lastIndexOf('}');
    if (a < 0 || b <= a) return 'No workout found in that text.';
    final o = jsonDecode(t.substring(a, b + 1));
    if (o is! Map || o['routines'] is! List) return 'No routines found in that text.';
    final have = {for (final r in await DB.d.query('routines')) (r['name'] as String).toLowerCase()};
    var nr = 0, ne = 0, nl = 0;
    Future<void> link(String n, String u) async {
      if (n.isEmpty || u.trim().isEmpty) return;
      await saveLink(n, u);
      nl++;
    }

    for (final r in (o['routines'] as List)) {
      if (r is! Map) continue;
      var name = '${r['name'] ?? 'AI workout'}'.trim();
      if (name.isEmpty) name = 'AI workout';
      while (have.contains(name.toLowerCase())) {
        name = '$name (AI)';
      }
      have.add(name.toLowerCase());
      final rid = await DB.d.insert('routines', {'name': name});
      nr++;
      for (final i in ((r['items'] as List?) ?? const [])) {
        if (i is! Map) continue;
        final n = '${i['name'] ?? ''}'.trim();
        if (n.isEmpty) continue;
        final k = '${i['kind'] ?? ''}'.toLowerCase();
        final timed = k == 'time' || k == 'seconds' || (k.isEmpty && timedName(n));
        final mu = '${i['muscle'] ?? ''}';
        await DB.d.insert('items', {
          'rid': rid,
          'name': n,
          'sets': int.tryParse('${i['sets']}') ?? 3,
          'reps': int.tryParse('${i['reps']}') ?? (timed ? 45 : 12),
          'muscle': muscles.contains(mu) ? mu : guess(n),
          'kind': timed ? 'time' : 'reps',
          'sec': '${i['section'] ?? i['sec'] ?? ''}'.trim(),
        });
        ne++;
        await link(n, '${i['url'] ?? ''}');
      }
    }
    final lk = o['links'];
    if (lk is Map) {
      for (final e in lk.entries) {
        await link('${e.key}', '${e.value}');
      }
    }
    tick.value++;
    return nr == 0 ? 'No routines found in that text.' : 'Added $nr routine${nr == 1 ? '' : 's'}, $ne exercises, $nl video links.';
  } catch (e) {
    return 'Could not read that. Ask the AI to reply in the exact format.';
  }
}

// ---------- app ----------
class ErrorApp extends StatelessWidget {
  final String msg;
  const ErrorApp(this.msg, {super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF040706),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SelectableText('Vytron Fit could not start. Please send this text to Claude:\n\n$msg', style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ),
        ),
      );
}

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await DB.init();
      await DB.d.insert('logins', {'day': dk(DateTime.now())}, conflictAlgorithm: ConflictAlgorithm.ignore);
      await loadTheme();
      try {
        await Voice.load();
      } catch (_) {}
    } catch (e, st) {
      runApp(ErrorApp('$e\n\n$st'));
      return;
    }
    runApp(const App());
    Future.delayed(const Duration(seconds: 4), () {
      Remind.init();
      Ads.init();
    });
  }, (e, st) {});
}

ThemeData mkTheme(bool d) => ThemeData(
      useMaterial3: true,
      brightness: d ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: P.vy ? const Color(0xFF050807) : d ? const Color(0xFF040706) : const Color(0xFFF1F7F3),
      colorScheme: P.vy ? const ColorScheme.dark(primary: P.emerald, secondary: P.gold, surface: Color(0xFF0A100D)) : d ? const ColorScheme.dark(primary: kG1, secondary: kG2, surface: Color(0xFF0D1511)) : const ColorScheme.light(primary: Color(0xFF008F4A), secondary: kG2, surface: Colors.white),
    );

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: styleMode,
        builder: (_, __s, ___s) => ValueListenableBuilder<ThemeMode>(
          valueListenable: themeMode,
          builder: (_, m, __) => MaterialApp(title: 'Vytron Fit', debugShowCheckedModeBanner: false, themeMode: P.vy ? ThemeMode.dark : m, theme: mkTheme(false), darkTheme: mkTheme(true), home: const Splash()),
        ),
      );
}

// ---------- shared widgets ----------
Widget bg(Widget child) => Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [P.hdr, P.bg], stops: const [0, .5])),
      child: child,
    );

Widget sub(String t, Widget w) => bg(Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(t, style: ts(20, w: FontWeight.w800))),
      body: w,
    ));

Widget card(Widget child, {Gradient? g}) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        gradient: P.vy
            ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0x99D6B66C), Color(0x1A00D878), Color(0x66D6B66C)])
            : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0x9900E676), Color(0x1A00E676), Color(0x5500A152)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: P.dark ? null : const [BoxShadow(color: Color(0x1A00A152), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: g, color: g == null ? P.card : null, borderRadius: BorderRadius.circular(23)),
        child: child,
      ),
    );

Widget gbtn(String t, VoidCallback f, {IconData? i}) => GestureDetector(
      onTap: f,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(gradient: P.grad, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Color(0x5500E676), blurRadius: 18, offset: Offset(0, 6))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (i != null) ...[Icon(i, color: Colors.black), const SizedBox(width: 8)],
          Text(t, style: ts(16, w: FontWeight.w800, c: Colors.black)),
        ]),
      ),
    );

Widget sbtn(String t, VoidCallback f, {IconData? i}) => GestureDetector(
      onTap: f,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: P.soft, borderRadius: BorderRadius.circular(18), border: Border.all(color: kG1.withOpacity(.6))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (i != null) ...[Icon(i, color: P.ac), const SizedBox(width: 8)],
          Text(t, style: ts(16, w: FontWeight.w800, c: P.ac)),
        ]),
      ),
    );

Widget goldBtn(String t, VoidCallback f, {IconData? i}) => GestureDetector(
      onTap: f,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        margin: const EdgeInsets.only(top: 6, bottom: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFEBD9A4), P.gold, Color(0xFFB8963F)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x44D6B66C), blurRadius: 16, offset: Offset(0, 5))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (i != null) ...[Icon(i, color: Colors.black), const SizedBox(width: 8)],
          Text(t, style: ts(16, w: FontWeight.w800, c: Colors.black)),
        ]),
      ),
    );

Widget pbtn(String t, VoidCallback f, {IconData? i, bool fill = true}) => GestureDetector(
      onTap: f,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: fill ? P.grad : null,
          color: fill ? null : P.soft,
          borderRadius: BorderRadius.circular(14),
          border: fill ? null : Border.all(color: kG1.withOpacity(.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (i != null) ...[Icon(i, size: 20, color: fill ? Colors.black : P.ac), const SizedBox(width: 6)],
          Flexible(child: Text(t, overflow: TextOverflow.ellipsis, style: ts(14, w: FontWeight.w800, c: fill ? Colors.black : P.ac))),
        ]),
      ),
    );

Widget gicon(IconData i, {double size = 24}) => ShaderMask(shaderCallback: (r) => P.igrad.createShader(r), child: Icon(i, size: size, color: Colors.white));

Widget gbar(double v, {double h = 8}) => ClipRRect(
      borderRadius: BorderRadius.circular(h),
      child: Container(
        height: h,
        color: P.soft,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(widthFactor: v.clamp(0.0, 1.0).toDouble(), child: Container(decoration: BoxDecoration(gradient: P.grad))),
      ),
    );

Widget tile(IconData i, String v, String l) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: P.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: P.line), boxShadow: P.dark ? null : const [BoxShadow(color: Color(0x1A00A152), blurRadius: 14, offset: Offset(0, 5))]),
        child: Column(children: [
          gicon(i),
          const SizedBox(height: 6),
          Text(v, style: ts(20, w: FontWeight.w800)),
          Text(l, style: ts(12, c: P.mu), textAlign: TextAlign.center),
        ]),
      ),
    );

Widget chips(Iterable<String> ms) => Wrap(spacing: 6, runSpacing: 6, children: [
      for (final m in ms)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: mc(m).withOpacity(.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: mc(m).withOpacity(.5))),
          child: Text(m, style: ts(12, w: FontWeight.w700, c: mc(m))),
        ),
    ]);

Widget ttl(String t, [String? s]) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(width: 4, height: s == null ? 18 : 32, decoration: BoxDecoration(gradient: P.vy ? P.igrad : kGrad, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: ts(16, w: FontWeight.w800)),
            if (s != null) Text(s, style: ts(12, c: P.mu)),
          ]),
        ),
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

InputDecoration fld(String l) => InputDecoration(labelText: l, filled: true, fillColor: P.soft, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none));

Future<String?> ask(BuildContext c, String t, {String hint = '', bool numeric = false}) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: c,
    builder: (d) => AlertDialog(
      backgroundColor: P.card,
      title: Text(t),
      content: TextField(controller: ctl, autofocus: true, keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Skip')),
        TextButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

// ---------- ads (test ids: replace with your own AdMob ids before a public release) ----------
const adUnitId = 'ca-app-pub-3940256099942544/1033173712';
const noAdsCode = 'fittrack111';

class Ads {
  static InterstitialAd? ad;
  static bool loading = false;

  static Future<void> init() async {
    try {
      await MobileAds.instance.initialize();
      load();
    } catch (_) {}
  }

  static void load() {
    if (loading || ad != null) return;
    loading = true;
    try {
      InterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (a) {
            ad = a;
            loading = false;
          },
          onAdFailedToLoad: (e) {
            loading = false;
          },
        ),
      );
    } catch (_) {
      loading = false;
    }
  }

  static Future<bool> enabled() async => (await DB.kv('noads')) != '1';

  static Future<void> maybeShow() async {
    try {
      if (!await enabled()) return;
      final a = ad;
      if (a == null) {
        load();
        return;
      }
      ad = null;
      a.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (x) {
          x.dispose();
          load();
        },
        onAdFailedToShowFullScreenContent: (x, e) {
          x.dispose();
          load();
        },
      );
      await a.show();
    } catch (_) {}
  }
}

// ---------- reminders ----------
final notif = FlutterLocalNotificationsPlugin();

class Remind {
  static bool ready = false;

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      await notif.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      ready = true;
      await reschedule();
    } catch (_) {}
  }

  static Future<bool> ask() async {
    try {
      final a = notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return (await a?.requestNotificationsPermission()) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> reschedule() async {
    if (!ready) return;
    try {
      await notif.cancelAll();
      if (await DB.kv('rem_on') != '1') return;
      final tm = ((await DB.kv('rem_time')) ?? '18:00').split(':');
      final h = int.tryParse(tm[0]) ?? 18;
      final m = int.tryParse(tm.length > 1 ? tm[1] : '0') ?? 0;
      final days = ((await DB.kv('rem_days')) ?? '1,2,3,4,5,6,7').split(',').map(int.tryParse).whereType<int>().toList();
      final now = DateTime.now();
      for (final d in days) {
        var t = DateTime(now.year, now.month, now.day, h, m);
        while (t.weekday != d || !t.isAfter(now)) {
          t = t.add(const Duration(days: 1));
        }
        await notif.zonedSchedule(
          d,
          'Time to train 💪',
          'Your workout is waiting. Warm up and get moving.',
          tz.TZDateTime.from(t, tz.UTC),
          const NotificationDetails(android: AndroidNotificationDetails('fittrack_reminders', 'Workout reminders', channelDescription: 'Daily workout reminders', importance: Importance.high, priority: Priority.high)),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
    } catch (_) {}
  }
}

class ReminderCard extends StatefulWidget {
  const ReminderCard({super.key});
  @override
  State<ReminderCard> createState() => _RC();
}

class _RC extends State<ReminderCard> {
  bool on = false;
  TimeOfDay tm = const TimeOfDay(hour: 18, minute: 0);
  Set<int> days = {1, 2, 3, 4, 5, 6, 7};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final o = await DB.kv('rem_on') == '1';
    final t = ((await DB.kv('rem_time')) ?? '18:00').split(':');
    final d = ((await DB.kv('rem_days')) ?? '1,2,3,4,5,6,7').split(',').map(int.tryParse).whereType<int>().toSet();
    if (!mounted) return;
    setState(() {
      on = o;
      tm = TimeOfDay(hour: int.tryParse(t[0]) ?? 18, minute: int.tryParse(t.length > 1 ? t[1] : '0') ?? 0);
      days = d.isEmpty ? {1, 2, 3, 4, 5, 6, 7} : d;
    });
  }

  Future<void> save() async {
    await DB.setKv('rem_on', on ? '1' : '0');
    await DB.setKv('rem_time', '${tm.hour}:${tm.minute}');
    final l = days.toList()..sort();
    await DB.setKv('rem_days', l.join(','));
    await Remind.reschedule();
  }

  @override
  Widget build(BuildContext context) => card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: ttl('Workout reminders', on ? 'Daily at ${tm.format(context)}' : 'Get a nudge when it is time to train')),
          Switch(
            value: on,
            onChanged: (v) async {
              if (v) await Remind.ask();
              setState(() => on = v);
              await save();
            },
          ),
        ]),
        if (on) ...[
          const SizedBox(height: 4),
          sbtn('Time: ${tm.format(context)}', () async {
            final r = await showTimePicker(context: context, initialTime: tm);
            if (r == null) return;
            setState(() => tm = r);
            await save();
          }, i: Icons.schedule_rounded),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Text(dn[d - 1].substring(0, 3)),
                selected: days.contains(d),
                showCheckmark: false,
                selectedColor: kG1,
                backgroundColor: P.soft,
                labelStyle: ts(13, w: FontWeight.w700, c: days.contains(d) ? Colors.black : null),
                onSelected: (v) async {
                  setState(() {
                    if (v) {
                      days.add(d);
                    } else if (days.length > 1) {
                      days.remove(d);
                    }
                  });
                  await save();
                },
              ),
          ]),
        ],
      ]));
}

class AdCodeCard extends StatefulWidget {
  const AdCodeCard({super.key});
  @override
  State<AdCodeCard> createState() => _AC();
}

class _AC extends State<AdCodeCard> {
  final ctl = TextEditingController();
  bool off = false;

  @override
  void initState() {
    super.initState();
    Ads.enabled().then((e) {
      if (mounted) setState(() => off = !e);
    });
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> apply() async {
    final v = ctl.text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (v == noAdsCode) {
      off = !off;
      await DB.setKv('noads', off ? '1' : '0');
      ctl.clear();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(off ? 'Code accepted. Ads are off.' : 'Ads are back on.')));
    } else if (v.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That code is not valid.')));
    }
  }

  @override
  Widget build(BuildContext context) => card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ttl('Ads', off ? 'Ads are off' : 'One short ad after each finished workout'),
        Row(children: [
          Expanded(child: TextField(controller: ctl, decoration: fld('Have a code?'))),
          const SizedBox(width: 10),
          SizedBox(width: 100, child: pbtn('Apply', apply)),
        ]),
      ]));
}

// ---------- exercise library + full-screen add / edit ----------

Future<List<String>?> askItem(BuildContext c) => Navigator.push<List<String>>(c, MaterialPageRoute(builder: (_) => const AddExercisePage()));

Future<List<String>?> askWarm(BuildContext c, {String name = '', int amt = 30, String kind = 'time'}) =>
    Navigator.push<List<String>>(c, MaterialPageRoute(builder: (_) => AddExercisePage(warm: true, name: name, amt: amt, kind: kind)));

Widget stepper(String label, int v, void Function(int) set, {int step = 1, String unit = ''}) => card(Row(children: [
      Expanded(child: Text(label, style: ts(15, w: FontWeight.w700))),
      IconButton(onPressed: () => set(math.max(1, v - step)), icon: Icon(Icons.remove_circle_outline, color: P.mu)),
      SizedBox(width: 64, child: Text('$v$unit', textAlign: TextAlign.center, style: ts(22, w: FontWeight.w900))),
      IconButton(onPressed: () => set(v + step), icon: Icon(Icons.add_circle, color: P.ac)),
    ]));

class AddExercisePage extends StatefulWidget {
  final bool warm;
  final String name;
  final int amt;
  final String kind;
  const AddExercisePage({super.key, this.warm = false, this.name = '', this.amt = 0, this.kind = ''});
  @override
  State<AddExercisePage> createState() => _AEP();
}

class _AEP extends State<AddExercisePage> {
  late final TextEditingController n;
  int sets = 3;
  late int amt;
  late bool timed;
  String muscle = 'Other';
  bool touched = false;
  String lib = 'All';
  List<List<String>> known = [];

  @override
  void initState() {
    super.initState();
    n = TextEditingController(text: widget.name);
    timed = widget.kind == 'time';
    amt = widget.amt > 0 ? widget.amt : (timed ? 45 : 12);
    if (widget.name.isNotEmpty) muscle = guess(widget.name);
    load();
  }

  @override
  void dispose() {
    n.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final seen = <String>{};
    final out = <List<String>>[];
    void add(String name, String? m) {
      if (seen.add(name.toLowerCase())) out.add([name, m ?? guess(name)]);
    }

    for (final r in await DB.d.query('items')) {
      add(r['name'] as String, r['muscle'] as String?);
    }
    for (final r in await DB.d.query('sets')) {
      add(r['ex'] as String, r['muscle'] as String?);
    }
    for (final e in exLib) {
      add(e[0], e[1]);
    }
    if (!mounted) return;
    setState(() => known = out);
  }

  void choose(List<String> e) {
    setState(() {
      n.text = e[0];
      n.selection = TextSelection.collapsed(offset: e[0].length);
      if (!touched) {
        muscle = e[1];
        timed = timedName(e[0]);
        amt = widget.warm ? (timed ? 30 : 10) : (timed ? 45 : 12);
      }
    });
  }

  void save() {
    final name = n.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter an exercise name.')));
      return;
    }
    if (widget.warm) {
      Navigator.pop(context, [name, '$amt', timed ? 'time' : 'reps']);
    } else {
      Navigator.pop(context, [name, '$sets', '$amt', muscle == 'Other' ? guess(name) : muscle, timed ? 'time' : 'reps']);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = n.text.trim().toLowerCase();
    final sugg = known.where((e) => (lib == 'All' || e[1] == lib) && (q.isEmpty || e[0].toLowerCase().contains(q))).take(60).toList();
    return bg(Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(widget.warm ? 'Warm-up exercise' : 'Add exercise', style: ts(20, w: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
        TextField(
          controller: n,
          textCapitalization: TextCapitalization.words,
          decoration: fld('Exercise name'),
          onChanged: (v) {
            setState(() {
              if (!touched) {
                muscle = guess(v);
                timed = timedName(v);
                amt = widget.warm ? (timed ? 30 : 10) : (timed ? 45 : 12);
              }
            });
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 42,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final m in ['All', ...muscles.where((x) => x != 'Other')])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(m),
                  selected: lib == m,
                  showCheckmark: false,
                  selectedColor: kG1,
                  backgroundColor: P.card,
                  labelStyle: ts(12, w: FontWeight.w700, c: lib == m ? Colors.black : null),
                  onSelected: (_) => setState(() => lib = m),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        if (sugg.isNotEmpty) ...[
          Text(q.isEmpty ? 'QUICK PICK' : 'SUGGESTIONS', style: ts(11, w: FontWeight.w800, c: P.ac, ls: 1.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final e in sugg) ActionChip(label: Text(e[0]), backgroundColor: P.card, labelStyle: ts(13, w: FontWeight.w600), onPressed: () => choose(e)),
          ]),
          const SizedBox(height: 16),
        ],
        if (!widget.warm) stepper('Sets', sets, (v) => setState(() => sets = v)),
        card(SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Timed hold (plank, wall sit…)'),
          value: timed,
          onChanged: (v) => setState(() {
            touched = true;
            timed = v;
            amt = widget.warm ? (v ? 30 : 10) : (v ? 45 : 12);
          }),
        )),
        stepper(timed ? 'Seconds per set' : 'Reps per set', amt, (v) => setState(() => amt = v), step: timed ? 5 : 1),
        if (!widget.warm) ...[
          ttl('Muscle group', 'Other = auto-detect from the name'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in muscles)
              ChoiceChip(
                label: Text(m),
                selected: muscle == m,
                showCheckmark: false,
                selectedColor: kG1,
                backgroundColor: P.card,
                labelStyle: ts(13, w: FontWeight.w700, c: muscle == m ? Colors.black : null),
                onSelected: (_) => setState(() {
                  touched = true;
                  muscle = m;
                }),
              ),
          ]),
          const SizedBox(height: 20),
        ],
        gbtn('Save', save, i: Icons.check_rounded),
      ]),
    ));
  }
}

Future<Rows> allExercises() async {
  final m = <String, String>{};
  final cnt = <String, int>{};
  for (final r in await DB.d.query('items')) {
    final n = r['name'] as String;
    m[n] = (r['muscle'] as String?) ?? guess(n);
  }
  for (final r in await DB.d.query('sets')) {
    final n = r['ex'] as String;
    m.putIfAbsent(n, () => (r['muscle'] as String?) ?? guess(n));
    cnt[n] = (cnt[n] ?? 0) + 1;
  }
  final Rows out = [
    for (final e in m.entries) <String, Object?>{'name': e.key, 'muscle': e.value, 'n': cnt[e.key] ?? 0},
  ];
  out.sort((a, b) {
    final x = muscles.indexOf(a['muscle'] as String), y = muscles.indexOf(b['muscle'] as String);
    if (x != y) return x.compareTo(y);
    return (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
  });
  return out;
}

class ExercisesPage extends StatelessWidget {
  const ExercisesPage({super.key});
  @override
  Widget build(BuildContext context) => Async<Rows>(
        allExercises,
        (c, rows) => ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
          Padding(padding: const EdgeInsets.only(bottom: 14), child: Text('Tap an exercise to rename it or change its muscle group. Your history and routines update everywhere.', style: ts(14, c: P.mu))),
          if (rows.isEmpty) Text('No exercises yet. Add some in a routine.', style: ts(14, c: P.mu)),
          for (final r in rows)
            GestureDetector(
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => EditExercisePage(r['name'] as String, r['muscle'] as String))),
              child: card(Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['name']}', style: ts(16, w: FontWeight.w800)),
                  const SizedBox(height: 6),
                  chips([r['muscle'] as String]),
                ])),
                Text('${r['n']} sets', style: ts(12, c: P.mu)),
                const SizedBox(width: 8),
                Icon(Icons.edit_outlined, color: P.mu, size: 18),
              ])),
            ),
        ]),
      );
}

class EditExercisePage extends StatefulWidget {
  final String name, muscle;
  const EditExercisePage(this.name, this.muscle, {super.key});
  @override
  State<EditExercisePage> createState() => _EEP();
}

class _EEP extends State<EditExercisePage> {
  late final TextEditingController n;
  late String muscle;

  @override
  void initState() {
    super.initState();
    n = TextEditingController(text: widget.name);
    muscle = muscles.contains(widget.muscle) ? widget.muscle : 'Other';
  }

  @override
  void dispose() {
    n.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final nn = n.text.trim();
    if (nn.isEmpty) return;
    await DB.d.update('items', {'name': nn, 'muscle': muscle}, where: 'name=?', whereArgs: [widget.name]);
    await DB.d.update('sets', {'ex': nn, 'muscle': muscle}, where: 'ex=?', whereArgs: [widget.name]);
    tick.value++;
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => bg(Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent, title: Text('Edit exercise', style: ts(20, w: FontWeight.w800))),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
          TextField(controller: n, textCapitalization: TextCapitalization.words, decoration: fld('Exercise name')),
          const SizedBox(height: 18),
          ttl('Muscle group'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in muscles)
              ChoiceChip(
                label: Text(m),
                selected: muscle == m,
                showCheckmark: false,
                selectedColor: kG1,
                backgroundColor: P.card,
                labelStyle: ts(13, w: FontWeight.w700, c: muscle == m ? Colors.black : null),
                onSelected: (_) => setState(() => muscle = m),
              ),
          ]),
          const SizedBox(height: 24),
          gbtn('Save changes', save, i: Icons.check_rounded),
        ]),
      ));
}

// ---------- best exercises ----------
double e1rm(double kg, int reps) => kg <= 0 ? 0 : kg * (1 + reps / 30);

class ExBest {
  double rm = 0, kg = 0, vol = 0;
  int reps = 0, hold = 0, sets = 0;
  String muscle = 'Other', last = '';
}

class BestPage extends StatelessWidget {
  const BestPage({super.key});
  @override
  Widget build(BuildContext context) => Async<St>(St.load, (c, st) {
        final b = <String, ExBest>{};
        for (final s in st.ss) {
          final ex = s['ex'] as String;
          final e = b.putIfAbsent(ex, () => ExBest());
          final r = s['reps'] as int;
          final w = kgOf(s);
          e.muscle = (s['muscle'] as String?) ?? guess(ex);
          e.sets++;
          final day = (s['day'] as String?) ?? '';
          if (day.compareTo(e.last) > 0) e.last = day;
          if (s['kind'] == 'time') {
            e.hold = math.max(e.hold, r);
          } else {
            e.reps = math.max(e.reps, r);
            e.kg = math.max(e.kg, w);
            e.rm = math.max(e.rm, e1rm(w, r));
            e.vol += w * r;
          }
        }
        final list = b.entries.toList()
          ..sort((x, y) {
            final d = y.value.rm.compareTo(x.value.rm);
            if (d != 0) return d;
            final r = y.value.reps.compareTo(x.value.reps);
            return r != 0 ? r : y.value.hold.compareTo(x.value.hold);
          });
        if (list.isEmpty) {
          return ListView(padding: const EdgeInsets.all(30), children: [
            const SizedBox(height: 40),
            Center(child: gicon(Icons.emoji_events_rounded, size: 70)),
            const SizedBox(height: 12),
            Text('No records yet', textAlign: TextAlign.center, style: ts(22, w: FontWeight.w800)),
            Text('Finish a workout and your best lifts show up here.', textAlign: TextAlign.center, style: ts(14, c: P.mu)),
          ]);
        }
        final top = list.first;
        return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
          card(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [gicon(Icons.emoji_events_rounded, size: 20), const SizedBox(width: 8), Text('STRONGEST EXERCISE', style: ts(12, w: FontWeight.w800, c: P.ac, ls: 1.5))]),
              const SizedBox(height: 8),
              Text(top.key, style: ts(26, w: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                top.value.rm > 0
                    ? 'Estimated 1-rep max ${numTxt(top.value.rm)} kg · best set ${numTxt(top.value.kg)} kg × ${top.value.reps}'
                    : top.value.reps > 0
                        ? 'Most reps in one set: ${top.value.reps}'
                        : 'Longest hold: ${tf(top.value.hold)}',
                style: ts(14, c: P.mu),
              ),
            ]),
            g: P.hero,
          ),
          for (var i = 0; i < list.length; i++)
            card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: i < 3 ? kGrad : null, color: i < 3 ? null : P.soft, borderRadius: BorderRadius.circular(10)),
                  child: Text('${i + 1}', style: ts(14, w: FontWeight.w900, c: i < 3 ? Colors.black : P.mu)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(list[i].key, style: ts(16, w: FontWeight.w800))),
                chips([list[i].value.muscle]),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 18, runSpacing: 6, children: [
                if (list[i].value.rm > 0) bestStat('Est. 1RM', '${numTxt(list[i].value.rm)} kg'),
                if (list[i].value.kg > 0) bestStat('Heaviest', '${numTxt(list[i].value.kg)} kg'),
                if (list[i].value.reps > 0) bestStat('Most reps', '${list[i].value.reps}'),
                if (list[i].value.hold > 0) bestStat('Longest hold', tf(list[i].value.hold)),
                if (list[i].value.vol > 0) bestStat('Volume', '${list[i].value.vol.round()} kg'),
                bestStat('Sets done', '${list[i].value.sets}'),
              ]),
              if (list[i].value.last.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Last done ${list[i].value.last}', style: ts(12, c: P.mu))),
            ])),
        ]);
      });
}

Widget bestStat(String l, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(l, style: ts(11, c: P.mu)),
      Text(v, style: ts(15, w: FontWeight.w800, c: P.ac)),
    ]);

// ---------- plate calculator ----------
class PlatePage extends StatefulWidget {
  const PlatePage({super.key});
  @override
  State<PlatePage> createState() => _PL();
}

class _PL extends State<PlatePage> {
  final target = TextEditingController(text: '60'), bar = TextEditingController(text: '20');

  @override
  void dispose() {
    target.dispose();
    bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = double.tryParse(target.text) ?? 0, b = double.tryParse(bar.text) ?? 0;
    var rem = (t - b) / 2;
    final out = <MapEntry<double, int>>[];
    if (rem > 0) {
      for (final pl in const [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25]) {
        final k = (rem / pl + 1e-9).floor();
        if (k > 0) {
          out.add(MapEntry(pl, k));
          rem -= k * pl;
        }
      }
    }
    final loadable = t - 2 * (rem > 0.001 ? rem : 0);
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
      Row(children: [
        Expanded(child: TextField(controller: target, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fld('Target weight (kg)'), onChanged: (_) => setState(() {}))),
        const SizedBox(width: 12),
        Expanded(child: TextField(controller: bar, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fld('Bar (kg)'), onChanged: (_) => setState(() {}))),
      ]),
      const SizedBox(height: 16),
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ttl('Plates on each side'),
        if (t <= b) Text('Target must be heavier than the bar.', style: ts(14, c: P.mu)),
        for (final e in out)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(gradient: kGrad, borderRadius: BorderRadius.circular(10)),
                child: Text('${e.value} ×', style: ts(15, w: FontWeight.w900, c: Colors.black)),
              ),
              const SizedBox(width: 12),
              Text('${numTxt(e.key)} kg', style: ts(18, w: FontWeight.w800)),
            ]),
          ),
        if (t > b && rem > 0.001) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Closest loadable weight: ${numTxt(loadable)} kg', style: ts(13, c: P.mu))),
        if (t > b && out.isNotEmpty && rem <= 0.001) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Total ${numTxt(t)} kg', style: ts(13, c: P.mu))),
      ])),
    ]);
  }
}

// ---------- csv export ----------
Future<void> exportCsv(BuildContext c) async {
  try {
    final rows = await DB.d.rawQuery('SELECT w.day, w.routine, s.ex, s.muscle, s.reps, s.kg, s.kind FROM sets s JOIN workouts w ON w.id=s.wid ORDER BY w.ts, s.id');
    String q(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    final b = StringBuffer('date,routine,exercise,muscle,reps_or_seconds,kg,type\n');
    for (final r in rows) {
      b.writeln([r['day'], r['routine'], r['ex'], r['muscle'], r['reps'], r['kg'], r['kind'] == 'time' ? 'seconds' : 'reps'].map(q).join(','));
    }
    final f = File(p.join(Directory.systemTemp.path, 'fittrack_export_${dk(DateTime.now())}.csv'));
    await f.writeAsString(b.toString());
    await Share.shareXFiles([XFile(f.path)], text: 'Vytron Fit export');
  } catch (_) {
    if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Export failed. Try again.')));
  }
}

// ---------- charts ----------
double niceMax(List<double> v) {
  final m = v.fold<double>(0, (a, b) => b > a ? b : a);
  if (m <= 0) return 1;
  final pw = math.pow(10, (math.log(m) / math.ln10).floor()).toDouble();
  final n = m / pw;
  final k = n <= 1 ? 1 : n <= 2 ? 2 : n <= 3 ? 3 : n <= 5 ? 5 : 10;
  return k * pw;
}

String numTxt(double x) => x == x.roundToDouble() ? x.round().toString() : x.toStringAsFixed(1);

void txt(Canvas c, String t, Offset o, {double size = 10, Color? col, FontWeight w = FontWeight.w400, bool center = false, bool right = false}) {
  final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(color: col ?? P.mu, fontSize: size, fontWeight: w)), textDirection: TextDirection.ltr)..layout();
  final dx = center ? o.dx - tp.width / 2 : right ? o.dx - tp.width : o.dx;
  tp.paint(c, Offset(dx, o.dy));
}

class BarsPainter extends CustomPainter {
  final List<double> v;
  final List<String> l;
  BarsPainter(this.v, this.l);
  @override
  void paint(Canvas c, Size s) {
    if (v.isEmpty) return;
    final mx = niceMax(v);
    const top = 18.0, bot = 22.0;
    final ch = s.height - top - bot;
    final grid = Paint()
      ..color = P.line
      ..strokeWidth = 1;
    for (var g = 0; g <= 2; g++) {
      final y = top + ch * g / 2;
      c.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }
    txt(c, numTxt(mx), const Offset(0, 3), size: 10);
    txt(c, numTxt(mx / 2), Offset(0, top + ch / 2 - 13), size: 10);
    final w = s.width / v.length;
    for (var i = 0; i < v.length; i++) {
      final last = i == v.length - 1;
      var h = ch * v[i] / mx;
      if (v[i] > 0 && h < 5) h = 5;
      if (v[i] <= 0) h = 3;
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(i * w + w * .2, top + ch - h, w * .6, h), const Radius.circular(7));
      final paint = Paint();
      if (v[i] > 0) {
        paint.shader = kGrad.createShader(r.outerRect);
      } else {
        paint.color = P.line;
      }
      c.drawRRect(r, paint);
      if (v[i] > 0 && v.length <= 10) {
        txt(c, numTxt(v[i]), Offset(i * w + w / 2, top + ch - h - 13), size: 10, col: P.ac, w: FontWeight.w700, center: true);
      }
      txt(c, l[i], Offset(i * w + w / 2, s.height - 16), size: 11, col: last ? P.ac : P.mu, w: last ? FontWeight.w800 : FontWeight.w400, center: true);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}

class TrendPainter extends CustomPainter {
  final List<double> v;
  final List<String> l;
  TrendPainter(this.v, {this.l = const []});
  @override
  void paint(Canvas c, Size s) {
    if (v.length < 2) return;
    final mx = niceMax(v);
    const top = 18.0, bot = 20.0;
    final ch = s.height - top - bot;
    final grid = Paint()
      ..color = P.line
      ..strokeWidth = 1;
    for (var g = 0; g <= 2; g++) {
      final y = top + ch * g / 2;
      c.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }
    txt(c, numTxt(mx), const Offset(0, 3), size: 10);
    txt(c, numTxt(mx / 2), Offset(0, top + ch / 2 - 13), size: 10);
    final pts = <Offset>[for (var i = 0; i < v.length; i++) Offset(i * s.width / (v.length - 1), top + ch - ch * v[i] / mx)];
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      final m = Offset((pts[i - 1].dx + pts[i].dx) / 2, (pts[i - 1].dy + pts[i].dy) / 2);
      path.quadraticBezierTo(pts[i - 1].dx, pts[i - 1].dy, m.dx, m.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    final fill = Path.from(path)
      ..lineTo(s.width, top + ch)
      ..lineTo(0, top + ch)
      ..close();
    c.drawPath(fill, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x5500E676), Color(0x0000E676)]).createShader(Rect.fromLTWH(0, top, s.width, ch)));
    c.drawPath(
      path,
      Paint()
        ..shader = kGrad.createShader(Rect.fromLTWH(0, 0, s.width, s.height))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < pts.length; i++) {
      if (v[i] > 0 && i != pts.length - 1) {
        c.drawCircle(pts[i], 3, Paint()..color = P.ac);
      }
    }
    final e = pts.last;
    c.drawCircle(e, 9, Paint()..color = kG1.withOpacity(.25));
    c.drawCircle(e, 5, Paint()..color = kG1);
    if (v.last > 0) {
      txt(c, numTxt(v.last), Offset(e.dx - 4, e.dy - 18), size: 11, col: P.ac, w: FontWeight.w800, right: true);
    }
    if (l.length == 3) {
      txt(c, l[0], Offset(0, s.height - 14), size: 10);
      txt(c, l[1], Offset(s.width / 2, s.height - 14), size: 10, center: true);
      txt(c, l[2], Offset(s.width, s.height - 14), size: 10, right: true);
    }
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
    final rect = Rect.fromCircle(center: s.center(Offset.zero), radius: s.shortestSide / 2 - 18);
    c.drawArc(rect, 0, 2 * math.pi, false, Paint()..color = P.soft..style = PaintingStyle.stroke..strokeWidth = 24);
    var a = -math.pi / 2;
    for (var i = 0; i < v.length; i++) {
      final sw = 2 * math.pi * v[i] / tot;
      c.drawArc(rect, a, sw > .06 ? sw - .05 : sw, false, Paint()..color = cols[i]..style = PaintingStyle.stroke..strokeWidth = 24..strokeCap = sw > .06 ? StrokeCap.round : StrokeCap.butt);
      a += sw;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}

class RingPainter extends CustomPainter {
  final double f;
  final double w;
  RingPainter(this.f, {this.w = 10});
  @override
  void paint(Canvas c, Size s) {
    final r = Rect.fromCircle(center: s.center(Offset.zero), radius: s.shortestSide / 2 - w / 2);
    c.drawArc(r, 0, 2 * math.pi, false, Paint()..color = P.soft..style = PaintingStyle.stroke..strokeWidth = w);
    final x = f.clamp(0.0, 1.0).toDouble();
    if (x > 0) {
      c.drawArc(r, -math.pi / 2, 2 * math.pi * x, false, Paint()..shader = kGrad.createShader(r)..style = PaintingStyle.stroke..strokeWidth = w..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}

// ---------- warm-up ----------
String warmAmt(Map<String, Object?> w) => w['kind'] == 'time' ? tf(w['amt'] as int) : '${w['amt']} reps';

int warmSecs(Rows w) => w.fold<int>(0, (a, e) => a + (e['kind'] == 'time' ? (e['amt'] as int) : 20));

Future<void> moveWarm(Rows rows, int i, int d) async {
  final j = i + d;
  if (j < 0 || j >= rows.length) return;
  final ids = [for (final r in rows) r['id'] as int];
  final x = ids.removeAt(i);
  ids.insert(j, x);
  for (var k = 0; k < ids.length; k++) {
    await DB.d.update('warmups', {'pos': k}, where: 'id=?', whereArgs: [ids[k]]);
  }
  tick.value++;
}

class WarmupEditor extends StatelessWidget {
  const WarmupEditor({super.key});

  Future<void> add(BuildContext c, int n) async {
    final v = await askWarm(c);
    if (v == null || v[0].isEmpty) return;
    await DB.d.insert('warmups', {'name': v[0], 'amt': math.max(1, int.tryParse(v[1]) ?? 30), 'kind': v[2], 'pos': n});
    tick.value++;
  }

  Future<void> edit(BuildContext c, Map<String, Object?> r) async {
    final v = await askWarm(c, name: r['name'] as String, amt: r['amt'] as int, kind: (r['kind'] as String?) ?? 'time');
    if (v == null || v[0].isEmpty) return;
    await DB.d.update('warmups', {'name': v[0], 'amt': math.max(1, int.tryParse(v[1]) ?? 30), 'kind': v[2]}, where: 'id=?', whereArgs: [r['id']]);
    tick.value++;
  }

  @override
  Widget build(BuildContext context) => Async<Rows>(
        warmList,
        (c, rows) => ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text('These exercises run in order before your workout. Tap one to edit it, use the arrows to reorder.', style: ts(14, c: P.mu)),
          ),
          if (rows.isNotEmpty) gbtn('Start warm-up (about ${(warmSecs(rows) / 60).ceil()} min)', () => Navigator.push(c, MaterialPageRoute(builder: (_) => const WarmupPage())), i: Icons.play_arrow_rounded),
          for (var i = 0; i < rows.length; i++)
            GestureDetector(
              onTap: () => edit(c, rows[i]),
              child: card(Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: kGrad, borderRadius: BorderRadius.circular(12)),
                  child: Text('${i + 1}', style: ts(15, w: FontWeight.w900, c: Colors.black)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${rows[i]['name']}', style: ts(16, w: FontWeight.w800)),
                  Text(warmAmt(rows[i]), style: ts(13, c: P.mu)),
                ])),
                IconButton(visualDensity: VisualDensity.compact, onPressed: i == 0 ? null : () => moveWarm(rows, i, -1), icon: Icon(Icons.keyboard_arrow_up_rounded, color: P.mu)),
                IconButton(visualDensity: VisualDensity.compact, onPressed: i == rows.length - 1 ? null : () => moveWarm(rows, i, 1), icon: Icon(Icons.keyboard_arrow_down_rounded, color: P.mu)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await DB.d.delete('warmups', where: 'id=?', whereArgs: [rows[i]['id']]);
                    tick.value++;
                  },
                  icon: const Icon(Icons.close, color: Colors.redAccent),
                ),
              ])),
            ),
          if (rows.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('No warm-up exercises yet. Add your first one.', textAlign: TextAlign.center, style: ts(14, c: P.mu))),
          gbtn('Add warm-up exercise', () => add(c, rows.length), i: Icons.add_rounded),
        ]),
      );
}

class WarmupPage extends StatefulWidget {
  final String? name;
  final Rows items;
  const WarmupPage({super.key, this.name, this.items = const []});
  @override
  State<WarmupPage> createState() => _WU();
}

class _WU extends State<WarmupPage> {
  Rows ex = [];
  bool ready = false, running = true;
  int i = 0, left = 0;
  Timer? t;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    final w = await warmList();
    if (!mounted) return;
    ex = w;
    ready = true;
    begin();
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  bool get timed => i < ex.length && ex[i]['kind'] == 'time';

  void begin() {
    t?.cancel();
    running = true;
    if (i < ex.length) {
      left = ex[i]['amt'] as int;
      if (timed) {
        t = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!running || !mounted) return;
          left--;
          if (left <= 0) {
            HapticFeedback.mediumImpact();
            next();
          } else {
            setState(() {});
          }
        });
      }
    }
    setState(() {});
  }

  void next() {
    i++;
    begin();
  }

  void finish() {
    Navigator.pop(context, widget.name != null);
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (!ready) {
      body = const Center(child: CircularProgressIndicator(color: kG1));
    } else if (ex.isEmpty) {
      body = ListView(children: [
        const SizedBox(height: 40),
        Center(child: gicon(Icons.self_improvement_rounded, size: 64)),
        const SizedBox(height: 14),
        Text('Your warm-up is empty', textAlign: TextAlign.center, style: ts(22, w: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Add the exercises you want to do before training.', textAlign: TextAlign.center, style: ts(14, c: P.mu)),
        const SizedBox(height: 24),
        gbtn('Edit warm-up', () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => sub('Warm-up', const WarmupEditor()))), i: Icons.edit_rounded),
        if (widget.name != null) sbtn('Skip to workout', finish, i: Icons.arrow_forward_rounded),
      ]);
    } else if (i >= ex.length) {
      body = ListView(children: [
        const SizedBox(height: 40),
        Center(child: gicon(Icons.check_circle_rounded, size: 84)),
        const SizedBox(height: 14),
        Text('Warm-up complete', textAlign: TextAlign.center, style: ts(26, w: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(widget.name != null ? 'You are ready for ${widget.name}.' : 'Nice work. Your body is ready.', textAlign: TextAlign.center, style: ts(14, c: P.mu)),
        const SizedBox(height: 28),
        gbtn(widget.name != null ? 'Start ${widget.name}' : 'Done', finish, i: widget.name != null ? Icons.play_arrow_rounded : Icons.check_rounded),
        sbtn('Repeat warm-up', () {
          i = 0;
          begin();
        }, i: Icons.replay_rounded),
      ]);
    } else {
      final cur = ex[i];
      final amt = cur['amt'] as int;
      body = ListView(children: [
        Text('EXERCISE ${i + 1} OF ${ex.length}', style: ts(12, w: FontWeight.w800, c: P.ac, ls: 1.5)),
        const SizedBox(height: 8),
        gbar(i / ex.length, h: 8),
        const SizedBox(height: 28),
        Center(
          child: SizedBox(
            width: 250,
            height: 250,
            child: Stack(alignment: Alignment.center, children: [
              CustomPaint(size: const Size(250, 250), painter: RingPainter(timed ? left / amt : 1.0, w: 14)),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(timed ? fmt(left) : '$amt', style: ts(timed ? 58 : 72, w: FontWeight.w900)),
                Text(timed ? (running ? 'seconds left' : 'paused') : 'reps', style: ts(14, c: P.mu)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        Text('${cur['name']}', textAlign: TextAlign.center, style: ts(28, w: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(i + 1 < ex.length ? 'Next: ${ex[i + 1]['name']}' : 'Last exercise', textAlign: TextAlign.center, style: ts(14, c: P.mu)),
        const SizedBox(height: 28),
        Row(children: [
          Expanded(child: sbtn('Skip', next, i: Icons.skip_next_rounded)),
          const SizedBox(width: 12),
          Expanded(
            child: timed
                ? gbtn(running ? 'Pause' : 'Resume', () => setState(() => running = !running), i: running ? Icons.pause_rounded : Icons.play_arrow_rounded)
                : gbtn('Done', next, i: Icons.check_rounded),
          ),
        ]),
      ]);
    }
    return bg(Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text('Warm-up', style: ts(20, w: FontWeight.w800))),
      body: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), child: body),
    ));
  }
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
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          Image.asset('${img}splash.jpg', fit: BoxFit.cover),
          Align(
            alignment: const Alignment(0, .72),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ShaderMask(shaderCallback: (r) => P.igrad.createShader(r), child: Text('VYTRON FIT', style: ts(38, w: FontWeight.w900, c: Colors.white, ls: 6))),
              const SizedBox(height: 6),
              Text('Train. Track. Transform.', style: ts(14, c: const Color(0xFF86A194), ls: 1.5)),
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
  static const titles = ['Vytron Fit', 'Weekly plan', 'Progress', 'Transformation', 'Profile', 'Goals & records'];
  final sk = GlobalKey<ScaffoldState>();
  void go(int k) => setState(() => i = k);

  PreferredSizeWidget vyBar() => AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 66,
        iconTheme: const IconThemeData(color: P.gold),
        titleSpacing: 0,
        title: Row(children: [
          ShaderMask(shaderCallback: (r) => P.igrad.createShader(r), child: const Icon(Icons.fitness_center_rounded, size: 30, color: Colors.white)),
          const SizedBox(width: 10),
          Container(width: 1, height: 34, color: P.gold.withOpacity(.45)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            ShaderMask(shaderCallback: (r) => P.igrad.createShader(r), child: Text('VYTRON', style: ts(22, w: FontWeight.w900, c: Colors.white, ls: 1).copyWith(fontStyle: FontStyle.italic, height: 1))),
            Text('Fit', style: ts(15, w: FontWeight.w800, c: P.emerald).copyWith(fontStyle: FontStyle.italic, height: 1.1)),
          ]),
        ]),
        actions: [
          GestureDetector(
            onTap: () => go(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: P.gold, width: 1.2)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.workspace_premium_rounded, size: 16, color: P.gold),
                Text('PRO', style: ts(10, w: FontWeight.w900, c: P.gold)),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => go(4),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: P.gold, width: 1.4)),
              child: const Icon(Icons.person_rounded, color: P.gold),
            ),
          ),
          const SizedBox(width: 14),
        ],
      );

  Widget vyNav() {
    const ic = [Icons.home_rounded, Icons.fitness_center_rounded, Icons.bar_chart_rounded, Icons.emoji_events_rounded, Icons.more_horiz_rounded];
    const lb = ['Home', 'Workout', 'Progress', 'Goals', 'More'];
    const ix = [0, 1, 2, 5, -1];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Container(
        height: 72,
        decoration: BoxDecoration(color: P.nav, borderRadius: BorderRadius.circular(36), border: Border.all(color: P.gold.withOpacity(.35)), boxShadow: const [BoxShadow(color: Color(0x3300D878), blurRadius: 24)]),
        child: Row(children: [
          for (var k = 0; k < 5; k++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (ix[k] < 0) {
                    sk.currentState?.openDrawer();
                  } else {
                    go(ix[k]);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: i == ix[k] ? P.emerald.withOpacity(.12) : null,
                    borderRadius: BorderRadius.circular(30),
                    border: i == ix[k] ? Border.all(color: P.emerald.withOpacity(.7)) : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(ic[k], size: 26, color: i == ix[k] ? P.emerald : P.mu),
                    const SizedBox(height: 2),
                    Text(lb[k], style: ts(11, w: FontWeight.w700, c: i == ix[k] ? P.emerald : P.mu)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget nav(int k) {
    const ic = [Icons.home_rounded, Icons.calendar_month_rounded, Icons.insights_rounded, Icons.photo_camera_rounded, Icons.person_rounded];
    final on = i == k;
    return GestureDetector(
      onTap: () => go(k),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(gradient: on ? kGrad : null, shape: BoxShape.circle, boxShadow: on ? const [BoxShadow(color: Color(0x6600E676), blurRadius: 14)] : null),
        child: Icon(ic[k], color: on ? Colors.black : P.mu),
      ),
    );
  }

  Widget item(BuildContext c, IconData ic, String t, VoidCallback f) => ListTile(
        leading: gicon(ic),
        title: Text(t),
        onTap: () {
          Navigator.pop(c);
          f();
        },
      );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
      valueListenable: styleMode,
      builder: (context, _s, __s) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (context, _, __) {
          final pages = [HomePage(onBackup: () => go(4), onGo: go), const WeekPage(), const StatsPage(), const TransformPage(), const ProfilePage(), const BestPage()];
          return bg(Scaffold(
            key: sk,
            backgroundColor: Colors.transparent,
            extendBody: true,
            appBar: P.vy ? vyBar() : AppBar(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, title: Text(titles[i], style: ts(20, w: FontWeight.w800))),
            drawer: Drawer(
              backgroundColor: P.bg,
              child: ListView(padding: EdgeInsets.zero, children: [
                SizedBox(
                  height: 170,
                  child: Stack(fit: StackFit.expand, children: [
                    Image.asset('${img}drawer_header.jpg', fit: BoxFit.cover),
                    Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, P.bg]))),
                    Positioned(left: 16, bottom: 12, child: Text('Vytron Fit v1.6.3', style: ts(20, w: FontWeight.w900))),
                  ]),
                ),
                item(context, Icons.home_rounded, 'Home', () => go(0)),
                item(context, Icons.calendar_month_rounded, 'Weekly plan', () => go(1)),
                item(context, Icons.self_improvement_rounded, 'Warm-up', () => Navigator.push(context, MaterialPageRoute(builder: (_) => sub('Warm-up', const WarmupEditor())))),
                item(context, Icons.spa_rounded, 'Flexibility', () => Navigator.push(context, MaterialPageRoute(builder: (_) => sub('Flexibility', const FlexPage())))),
                item(context, Icons.menu_book_rounded, 'Exercise library', () => Navigator.push(context, MaterialPageRoute(builder: (_) => sub('Exercise library', const LibraryPage())))),
                item(context, Icons.list_alt_rounded, 'My routines', () => Navigator.push(context, MaterialPageRoute(builder: (_) => sub('My routines', const RoutinesPage())))),
                item(context, Icons.insights_rounded, 'Progress & results', () => go(2)),
                item(context, Icons.history_rounded, 'Workout history', () => Navigator.push(context, MaterialPageRoute(builder: (_) => sub('History', const HistoryPage())))),
                item(context, Icons.emoji_events_rounded, 'Best exercises', () => Navigator.push(context, MaterialPageRoute(builder: (_) => sub('Best exercises', const BestPage())))),
                item(context, Icons.edit_note_rounded, 'Edit exercises', () => Navigator.push(context, MaterialPageRoute(builder: (_) => sub('Exercises', const ExercisesPage())))),
                item(context, Icons.calculate_rounded, 'Plate calculator', () => Navigator.push(context, MaterialPageRoute(builder: (_) => sub('Plate calculator', const PlatePage())))),
                item(context, Icons.photo_camera_rounded, 'Transformation', () => go(3)),
                item(context, Icons.person_rounded, 'Profile & backup', () => go(4)),
              ]),
            ),
            body: KeyedSubtree(key: ValueKey('${P.vy}${P.dark}'), child: pages[i]),
            bottomNavigationBar: P.vy ? vyNav() : Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Container(
                height: 70,
                decoration: BoxDecoration(color: P.nav, borderRadius: BorderRadius.circular(35), border: Border.all(color: const Color(0x5500E676)), boxShadow: const [BoxShadow(color: Color(0x3300E676), blurRadius: 26)]),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [for (var k = 0; k < 5; k++) nav(k)]),
              ),
            ),
          ));
        },
      ));
}

// ---------- home ----------
Future<void> pickRoutine(BuildContext c) async {
  final rs = await DB.d.query('routines');
  if (!c.mounted) return;
  showModalBottomSheet(
    context: c,
    isScrollControlled: true,
    backgroundColor: P.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (b) => SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Choose routine', style: ts(20, w: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final r in rs)
          ListTile(
            title: Text(r['name'] as String),
            trailing: gicon(Icons.chevron_right),
            onTap: () async {
              final it = await DB.d.query('items', where: 'rid=?', whereArgs: [r['id']]);
              if (!c.mounted) return;
              Navigator.pop(b);
              runSession(c, r['name'] as String, it.toList(), rid: r['id'] as int);
            },
          ),
        ListTile(
          title: const Text('Quick workout (add as you go)'),
          trailing: gicon(Icons.bolt),
          onTap: () {
            Navigator.pop(b);
            Navigator.push(c, MaterialPageRoute(builder: (_) => const WorkoutPage('Quick workout', [])));
          },
        ),
      ]),
    ),
  );
}

Widget sessionCard(BuildContext c, int s, Map<String, Object?> plan, Set<Object?> done) {
  final nm = plan['name'] as String;
  final isDone = done.contains(nm);
  final it = plan['items'] as Rows;
  final nSets = it.fold<int>(0, (a, e) => a + (e['sets'] as int));
  return card(
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        gicon(s == 0 ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded, size: 18),
        const SizedBox(width: 8),
        Text('${s == 0 ? 'MORNING' : 'EVENING'} SESSION', style: ts(12, w: FontWeight.w800, c: P.ac, ls: 1.5)),
        const Spacer(),
        if (isDone)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(gradient: kGrad, borderRadius: BorderRadius.circular(20)),
            child: Text('DONE ✓', style: ts(11, w: FontWeight.w900, c: Colors.black)),
          ),
      ]),
      const SizedBox(height: 8),
      Text(nm, style: ts(26, w: FontWeight.w900)),
      const SizedBox(height: 2),
      Text('${it.length} exercises · $nSets sets', style: ts(13, c: P.mu)),
      const SizedBox(height: 12),
      chips(mlist(it).toSet()),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: pbtn('Warm up', () async {
          final ok = await Navigator.push<bool>(c, MaterialPageRoute<bool>(builder: (_) => WarmupPage(name: nm, items: it)));
          if (ok == true && c.mounted) runSession(c, nm, it, rid: plan['id'] as int?);
        }, i: Icons.self_improvement_rounded, fill: false)),
        const SizedBox(width: 10),
        Expanded(child: pbtn(isDone ? 'Train again' : 'Start', () => runSession(c, nm, it, rid: plan['id'] as int?), i: Icons.play_arrow_rounded)),
      ]),
    ]),
    g: P.hero,
  );
}

Widget weekDot(DateTime d, St st, DateTime now) {
  final done = st.wdays.contains(dk(d));
  final today = dk(d) == dk(now);
  return Expanded(
    child: Column(children: [
      Text(['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1], style: ts(11, c: P.mu)),
      const SizedBox(height: 6),
      Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(gradient: done ? kGrad : null, color: done ? null : P.soft, shape: BoxShape.circle, border: today ? Border.all(color: kG1, width: 2) : null),
        child: done ? const Icon(Icons.check_rounded, size: 20, color: Colors.black) : Text('${d.day}', style: ts(12, c: P.mu)),
      ),
    ]),
  );
}

class HomePage extends StatelessWidget {
  final VoidCallback onBackup;
  final void Function(int)? onGo;
  const HomePage({super.key, required this.onBackup, this.onGo});

  Widget streakPill(IconData ic, int n, String l) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: P.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: P.line)),
          child: Row(children: [
            gicon(ic, size: 26),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$n ${n == 1 ? 'day' : 'days'}', style: ts(18, w: FontWeight.w900)),
              Text(l, style: ts(12, c: P.mu)),
            ])),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Async<List<Object?>>(
        () async {
          final wd = DateTime.now().weekday;
          return [await St.load(), await DB.kv('name'), int.tryParse(await DB.kv('goal') ?? '') ?? 4, [await planFor(wd, 0), await planFor(wd, 1)], await DB.kv('lastbackup'), await warmList()];
        },
        (c, d) {
          final st = d[0] as St;
          final name = ((d[1] as String?) ?? '').trim();
          var goal = d[2] as int;
          if (goal < 1) goal = 1;
          final plans = d[3] as List<Map<String, Object?>?>;
          final last = DateTime.tryParse((d[4] as String?) ?? '');
          final warm = d[5] as Rows;
          final now = DateTime.now();
          final mon = DateTime(now.year, now.month, now.day - (now.weekday - 1));
          final ds = st.days(7);
          const wd = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
          const mn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
          final week = [for (var k = 0; k < 7; k++) DateTime(mon.year, mon.month, mon.day + k)].where((x) => st.wdays.contains(dk(x))).length;
          final secs = st.ws.fold<int>(0, (a, e) => a + (e['secs'] as int));
          final ws = st.streak(st.wdays);
          final doneToday = st.ws.where((w) => w['day'] == dk(now)).map((w) => w['routine']).toSet();
          final needBackup = st.ws.length >= 3 && (last == null || now.difference(last).inDays >= 7);
          final greet = now.hour < 12 ? 'Good morning' : now.hour < 17 ? 'Good afternoon' : 'Good evening';
          final left = goal - week;
          return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 120), children: [
            if (P.vy)
              ...vyTop(c, name: name, greet: greet, total: st.ws.length, week: week, streak: ws, secs: secs, go: onGo)
            else
            ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: SizedBox(
                height: 170,
                child: Stack(fit: StackFit.expand, children: [
                  Image.asset('${img}home_banner.jpg', fit: BoxFit.cover, alignment: Alignment.centerRight),
                  Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xF2040706), Color(0x99040706), Color(0x00040706)]))),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${dn[now.weekday - 1]}, ${now.day} ${mn[now.month - 1]}'.toUpperCase(), style: ts(11, w: FontWeight.w800, c: kG1, ls: 1.5)),
                      const SizedBox(height: 4),
                      Text(greet, style: ts(14, c: const Color(0xFFB7CFC2))),
                      Text(name.isEmpty ? 'Athlete' : name, style: ts(30, w: FontWeight.w900, c: Colors.white)),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            if (plans[0] == null && plans[1] == null)
              card(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('TODAY · ${dn[now.weekday - 1].toUpperCase()}', style: ts(12, w: FontWeight.w800, c: P.ac, ls: 1.5)),
                  const SizedBox(height: 6),
                  Text('Rest day', style: ts(26, w: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text('Recovery is part of the plan. Sleep, eat, stretch.', style: ts(14, c: P.mu)),
                  const SizedBox(height: 16),
                  pbtn('Train anyway', () => pickRoutine(c), i: Icons.bolt_rounded),
                ]),
                g: P.hero,
              )
            else ...[
              for (var s = 0; s < 2; s++)
                if (plans[s] != null) sessionCard(c, s, plans[s]!, doneToday),
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Center(child: TextButton(onPressed: () => pickRoutine(c), child: Text('Pick a different routine', style: ts(14, c: P.mu))))),
            ],
            card(Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: P.soft, borderRadius: BorderRadius.circular(16)),
                child: Center(child: gicon(Icons.self_improvement_rounded, size: 28)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Warm-up', style: ts(16, w: FontWeight.w800)),
                Text(warm.isEmpty ? 'Add exercises to build your warm-up' : '${warm.length} exercises · about ${(warmSecs(warm) / 60).ceil()} min', style: ts(12, c: P.mu)),
              ])),
              if (warm.isNotEmpty)
                IconButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const WarmupPage())), icon: gicon(Icons.play_circle_fill_rounded, size: 36)),
              IconButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => sub('Warm-up', const WarmupEditor()))), icon: Icon(Icons.edit_outlined, color: P.mu)),
            ])),
            card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: Stack(alignment: Alignment.center, children: [
                    CustomPaint(size: const Size(96, 96), painter: RingPainter(week / goal, w: 10)),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('$week', style: ts(28, w: FontWeight.w900)),
                      Text('of $goal', style: ts(11, c: P.mu)),
                    ]),
                  ]),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Weekly goal', style: ts(12, w: FontWeight.w800, c: P.ac, ls: 1.5)),
                  const SizedBox(height: 4),
                  Text(left <= 0 ? 'Goal reached' : '$left more to go', style: ts(20, w: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(left <= 0 ? 'Great week. Keep the momentum.' : 'Workouts completed this week', style: ts(12, c: P.mu)),
                ])),
              ]),
              const SizedBox(height: 16),
              Row(children: [for (var i = 0; i < 7; i++) weekDot(DateTime(mon.year, mon.month, mon.day + i), st, now)]),
            ])),
            Row(children: [
              streakPill(Icons.local_fire_department_rounded, ws, 'workout streak'),
              const SizedBox(width: 10),
              streakPill(Icons.event_available_rounded, st.streak(st.lg), 'login streak'),
            ]),
            if (needBackup)
              card(Row(children: [
                gicon(Icons.cloud_upload_rounded, size: 30),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Save a backup', style: ts(15, w: FontWeight.w800)),
                  Text(last == null ? 'You have not backed up yet.' : 'Last backup was ${now.difference(last).inDays} days ago.', style: ts(12, c: P.mu)),
                ])),
                TextButton(onPressed: onBackup, child: Text('Open', style: ts(14, w: FontWeight.w800, c: P.ac))),
              ])),
            Row(children: [
              tile(Icons.fitness_center, '${st.ws.length}', 'Workouts'),
              tile(Icons.repeat_rounded, '${st.totalReps}', 'Total reps'),
              tile(Icons.timer_outlined, '${(secs / 60).round()}m', 'Time'),
            ]),
            const SizedBox(height: 14),
            card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ttl('Minutes per day', 'last 7 days'),
              SizedBox(height: 150, width: double.infinity, child: CustomPaint(painter: BarsPainter([for (final x in ds) double.parse(st.mins(dk(x)).toStringAsFixed(1))], [for (final x in ds) wd[x.weekday - 1]]))),
            ])),
            if (P.vy) vyBanner(),
          ]);
        },
      );
}

// ---------- weekly plan (2 sessions a day) ----------
Future<void> setSlot(int d, int slot, int rid) async {
  await DB.d.insert('schedule', {'day': d, 'slot': slot, 'rid': rid}, conflictAlgorithm: ConflictAlgorithm.replace);
  tick.value++;
}

Future<void> pickSlot(BuildContext c, int d, int slot) async {
  final rs = await DB.d.query('routines');
  if (!c.mounted) return;
  showModalBottomSheet(
    context: c,
    isScrollControlled: true,
    backgroundColor: P.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (b) => SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${dn[d - 1]} · ${slot == 0 ? 'Morning' : 'Evening'}', style: ts(20, w: FontWeight.w800)),
        const SizedBox(height: 8),
        ListTile(
          leading: Icon(Icons.bedtime_rounded, color: P.mu),
          title: const Text('Rest / nothing'),
          onTap: () {
            setSlot(d, slot, 0);
            Navigator.pop(b);
          },
        ),
        for (final r in rs)
          ListTile(
            leading: gicon(Icons.fitness_center),
            title: Text(r['name'] as String),
            onTap: () {
              setSlot(d, slot, r['id'] as int);
              Navigator.pop(b);
            },
          ),
      ]),
    ),
  );
}

Widget slotRow(BuildContext c, int d, int k, Map<String, Object?>? pl) => GestureDetector(
      onTap: () => pickSlot(c, d, k),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: P.soft, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          gicon(k == 0 ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded, size: 20),
          const SizedBox(width: 8),
          SizedBox(width: 56, child: Text(k == 0 ? 'Morning' : 'Evening', style: ts(12, c: P.mu))),
          Expanded(
            child: pl == null
                ? Text('Rest / none', style: ts(14, c: P.mu))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${pl['name']}', style: ts(15, w: FontWeight.w700)),
                    const SizedBox(height: 4),
                    chips(mlist(pl['items'] as Rows).toSet()),
                  ]),
          ),
          Icon(Icons.edit_outlined, size: 16, color: P.mu),
        ]),
      ),
    );

class WeekPage extends StatelessWidget {
  const WeekPage({super.key});
  @override
  Widget build(BuildContext context) => Async<List<List<Map<String, Object?>?>>>(
        () async => [for (var d = 1; d <= 7; d++) [await planFor(d, 0), await planFor(d, 1)]],
        (c, pl) => ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 120), children: [
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Train up to twice a day. Tap a slot to choose its routine.', style: ts(14, c: P.mu))),
          for (var d = 1; d <= 7; d++)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: P.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: d == DateTime.now().weekday ? kG1 : P.line, width: d == DateTime.now().weekday ? 1.6 : 1)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(gradient: (pl[d - 1][0] != null || pl[d - 1][1] != null) ? kGrad : null, color: (pl[d - 1][0] != null || pl[d - 1][1] != null) ? null : P.soft, borderRadius: BorderRadius.circular(14)),
                    child: Text(dn[d - 1].substring(0, 3).toUpperCase(), style: ts(13, w: FontWeight.w900, c: (pl[d - 1][0] != null || pl[d - 1][1] != null) ? Colors.black : P.mu)),
                  ),
                  const SizedBox(width: 12),
                  Text(dn[d - 1], style: ts(17, w: FontWeight.w800)),
                  const Spacer(),
                  if (d == DateTime.now().weekday) Text('TODAY', style: ts(11, w: FontWeight.w900, c: P.ac, ls: 1.5)),
                ]),
                slotRow(c, d, 0, pl[d - 1][0]),
                slotRow(c, d, 1, pl[d - 1][1]),
              ]),
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
  final String music;
  const WorkoutPage(this.name, this.items, {this.music = '', super.key});
  @override
  State<WorkoutPage> createState() => _WS();
}

class _WS extends State<WorkoutPage> {
  late List<String> exs;
  final Map<String, int> tSets = {}, tReps = {};
  final Map<String, String> mus = {}, kinds = {};
  int ei = 0, reps = 0, hold = 0, restLeft = 0, restTot = 60, rest = 60;
  bool paused = false, holding = false, videoOpen = false;
  final sw = Stopwatch()..start();
  Timer? t;
  final logged = <Map<String, Object?>>[];
  final kg = TextEditingController();
  final Map<String, Rows> prev = {};
  final Map<String, List<double>> hb = {};
  String? prMsg;
  String? secMsg;
  final Map<String, String> secs = {}, links = {};
  int prs = 0;

  @override
  void initState() {
    super.initState();
    loadHist();
    loadLinks();
    exs = [for (final i in widget.items) i['name'] as String];
    for (final i in widget.items) {
      final n = i['name'] as String;
      tSets[n] = i['sets'] as int;
      tReps[n] = i['reps'] as int;
      mus[n] = (i['muscle'] as String?) ?? guess(n);
      kinds[n] = (i['kind'] as String?) ?? (timedName(n) ? 'time' : 'reps');
      secs[n] = (i['sec'] as String?) ?? '';
    }
    DB.kv('rest').then((v) {
      if (v != null) rest = int.tryParse(v) ?? 60;
    });
    if (exs.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted && exs.isNotEmpty) Voice.say('Let\'s go. First exercise: ${exs[0]}.');
      });
    }
    t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (restLeft > 0 && !videoOpen) {
          restLeft--;
          if (restLeft == 0) {
            HapticFeedback.heavyImpact();
            Voice.say(restOverMsg());
          }
        }
        if (holding && !videoOpen && exs.isNotEmpty) {
          hold++;
          if (hold == tReps[exs[ei]]) HapticFeedback.heavyImpact();
        }
      });
    });
  }

  Future<void> loadLinks() async {
    for (final r in await DB.d.query('exlinks')) {
      links[r['name'] as String] = (r['url'] as String?) ?? '';
    }
    if (mounted) setState(() {});
  }

  Future<void> watch(String url) async {
    final wasPaused = paused;
    setState(() {
      videoOpen = true;
      holding = false;
    });
    if (!wasPaused) sw.stop();
    await openLink(context, url, workout: true);
    if (!mounted) return;
    setState(() => videoOpen = false);
    if (!wasPaused) sw.start();
  }

  Future<void> setLink(String ex) async {
    final v = await askLink(context, ex, links[ex] ?? '');
    if (v == null) return;
    await saveLink(ex, v);
    if (!mounted) return;
    setState(() {
      if (v.trim().isEmpty) {
        links.remove(ex);
      } else {
        links[ex] = v.trim();
      }
    });
  }

  Future<void> loadHist() async {
    final r = await DB.d.rawQuery('SELECT ex, reps, kg, kind, wid FROM sets ORDER BY wid DESC, id ASC');
    final lastW = <String, int>{};
    for (final x in r) {
      final ex = x['ex'] as String;
      final wid = x['wid'] as int;
      lastW.putIfAbsent(ex, () => wid);
      if (lastW[ex] == wid) prev.putIfAbsent(ex, () => []).add(x);
      final b = hb.putIfAbsent(ex, () => [0, 0, 0, 0]);
      final reps = x['reps'] as int;
      final w = kgOf(x);
      if (x['kind'] == 'time') {
        b[3] = math.max(b[3], reps.toDouble());
      } else {
        b[0] = math.max(b[0], reps.toDouble());
        b[1] = math.max(b[1], w);
        b[2] = math.max(b[2], e1rm(w, reps));
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    t?.cancel();
    Voice.stop();
    kg.dispose();
    super.dispose();
  }

  bool isT(String ex) => kinds[ex] == 'time';
  Rows setsOf(String ex) => logged.where((s) => s['ex'] == ex).toList();
  bool doneEx(String ex) => tSets[ex] != null && setsOf(ex).length >= tSets[ex]!;
  String amt(String ex, int v) => isT(ex) ? tf(v) : '$v';

  String restOverMsg() {
    if (exs.isEmpty) return 'Rest over.';
    final e = exs[ei];
    return 'Rest over. $e, set ${setsOf(e).length + 1}.';
  }

  void pick(int i) {
    setState(() {
      ei = i;
      reps = 0;
      hold = 0;
      holding = false;
    });
    if (i >= 0 && i < exs.length) Voice.say(exs[i]);
  }

  Future<void> addEx() async {
    final v = await askItem(context);
    if (v != null && v[0].isNotEmpty) {
      setState(() {
        exs.add(v[0]);
        tSets[v[0]] = int.tryParse(v[1]) ?? 3;
        tReps[v[0]] = int.tryParse(v[2]) ?? (v[4] == 'time' ? 45 : 10);
        mus[v[0]] = v[3];
        kinds[v[0]] = v[4];
        secs[v[0]] = exs.length > 1 ? (secs[exs[exs.length - 2]] ?? '') : '';
        ei = exs.length - 1;
        reps = 0;
        hold = 0;
        holding = false;
      });
    }
  }

  Future<void> typeReps() async {
    final timed = exs.isNotEmpty && isT(exs[ei]);
    final v = await ask(context, timed ? 'Seconds held' : 'Total reps done', numeric: true);
    final n = int.tryParse(v ?? '');
    if (n != null) {
      setState(() {
        if (timed) {
          hold = n;
          holding = false;
        } else {
          reps = n;
        }
      });
    }
  }

  void logSet() {
    if (exs.isEmpty) return;
    final ex = exs[ei];
    final timed = isT(ex);
    final v = timed ? hold : reps;
    if (v <= 0) return;
    var moved = false;
    final w = timed ? 0.0 : (double.tryParse(kg.text) ?? 0.0);
    final b = hb.putIfAbsent(ex, () => [0, 0, 0, 0]);
    final hadHist = b[0] + b[3] > 0;
    String? pr;
    if (timed) {
      if (hadHist && v > b[3]) pr = '$ex: ${tf(v)} hold';
      b[3] = math.max(b[3], v.toDouble());
    } else {
      final rm = e1rm(w, v);
      if (hadHist && (w > 0 ? rm > b[2] + 0.01 : (b[2] == 0 && v > b[0]))) {
        pr = w > 0 ? '$ex: ${numTxt(w)} kg × $v' : '$ex: $v reps';
      }
      b[0] = math.max(b[0], v.toDouble());
      b[1] = math.max(b[1], w);
      b[2] = math.max(b[2], rm);
    }
    if (pr != null) {
      prs++;
      prMsg = pr;
      HapticFeedback.heavyImpact();
      final shown = pr;
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted && prMsg == shown) setState(() => prMsg = null);
      });
    }
    String? newSec;
    setState(() {
      logged.add({'ex': ex, 'reps': v, 'kg': w, 'muscle': mus[ex] ?? 'Other', 'kind': timed ? 'time' : 'reps'});
      reps = 0;
      hold = 0;
      holding = false;
      restLeft = rest;
      restTot = rest;
      if (doneEx(ex) && ei < exs.length - 1) {
        ei++;
        moved = true;
        final ns = secs[exs[ei]] ?? '';
        if (ns.isNotEmpty && ns != (secs[ex] ?? '')) newSec = ns;
      }
    });
    HapticFeedback.mediumImpact();
    if (rest > 0) {
      final nx = (moved && exs.isNotEmpty) ? ' Next up, ${exs[ei]}.' : '';
      final sc = newSec != null ? ' New section, $newSec.' : '';
      Voice.say('Rest. $rest seconds.$nx$sc');
    }
    if (newSec != null) {
      final shown = newSec;
      HapticFeedback.heavyImpact();
      setState(() => secMsg = shown);
      Future.delayed(const Duration(seconds: 7), () {
        if (mounted && secMsg == shown) setState(() => secMsg = null);
      });
    }
    if (moved && newSec == null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$ex done · next: ${exs[ei]}')));
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
      final tot = logged.where((s) => s['kind'] != 'time').fold<int>(0, (a, s) => a + (s['reps'] as int));
      final held = logged.where((s) => s['kind'] == 'time').fold<int>(0, (a, s) => a + (s['reps'] as int));
      Voice.say('Workout complete. Good work.');
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          backgroundColor: P.card,
          title: const Text('Workout complete 💪'),
          content: Text('${fmt(secs)}  ·  ${logged.length} sets${tot > 0 ? '  ·  $tot reps' : ''}${held > 0 ? '  ·  ${tf(held)} held' : ''}${prs > 0 ? '\n🏆 $prs new personal record${prs == 1 ? '' : 's'}' : ''}', style: ts(18)),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Nice'))],
        ),
      );
    }
    final had = logged.isNotEmpty;
    if (!mounted) return;
    Navigator.pop(context, had);
    if (had) Ads.maybeShow();
  }

  @override
  Widget build(BuildContext context) {
    final ex = exs.isEmpty ? null : exs[ei];
    final mine = ex == null ? <Map<String, Object?>>[] : setsOf(ex);
    final tS = ex == null ? null : tSets[ex];
    final tR = ex == null ? null : tReps[ex];
    final timed = ex != null && isT(ex);
    final cur = timed ? hold : reps;
    final planned = tSets.values.fold<int>(0, (a, b) => a + b);
    var doneInPlan = 0;
    for (final e in exs) {
      doneInPlan += math.min(setsOf(e).length, tSets[e] ?? 0);
    }
    final nPills = tS == null ? mine.length + 1 : math.max(tS, mine.length);
    final left = tR == null ? null : tR - cur;
    final setsLeft = tS == null ? null : math.max(0, tS - mine.length);
    return bg(Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            Expanded(child: Text(widget.name, style: ts(20, w: FontWeight.w800))),
            IconButton(
              tooltip: 'Voice coach',
              onPressed: () async {
                await Voice.setOn(!Voice.on);
                if (mounted) setState(() {});
              },
              icon: Icon(Voice.on ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: P.gold),
            ),
            TextButton(onPressed: finish, child: Text('FINISH', style: ts(14, w: FontWeight.w900, c: P.ac))),
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
                  decoration: BoxDecoration(shape: BoxShape.circle, color: P.bg),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(fmt(sw.elapsed.inSeconds), style: ts(48, w: FontWeight.w900)),
                    Text(paused ? 'PAUSED' : 'WORKOUT TIME', style: ts(12, c: P.ac, ls: 2)),
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
                if (paused) {
                  sw.stop();
                  holding = false;
                } else {
                  sw.start();
                }
              }),
              icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 30),
            ),
          ),
          if (planned > 0) ...[
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Workout progress', style: ts(13, c: P.mu)),
              Text('$doneInPlan / $planned sets', style: ts(13, w: FontWeight.w800, c: P.ac)),
            ]),
            const SizedBox(height: 6),
            gbar(doneInPlan / planned, h: 10),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 46,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (var i = 0; i < exs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: doneEx(exs[i]) ? Icon(Icons.check_circle, size: 18, color: i == ei ? Colors.black : P.ac) : (isT(exs[i]) ? Icon(Icons.timer_rounded, size: 16, color: i == ei ? Colors.black : P.mu) : null),
                    label: Text(exs[i]),
                    selected: i == ei,
                    showCheckmark: false,
                    selectedColor: kG1,
                    backgroundColor: P.card,
                    labelStyle: ts(14, w: FontWeight.w700, c: i == ei ? Colors.black : null),
                    onSelected: (_) => pick(i),
                  ),
                ),
              ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Add'), backgroundColor: P.card, onPressed: addEx),
            ]),
          ),
          const SizedBox(height: 14),
          if (prMsg != null)
            card(
              Row(children: [
                gicon(Icons.emoji_events_rounded, size: 34),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('NEW PERSONAL RECORD', style: ts(11, w: FontWeight.w900, c: P.ac, ls: 1.5)),
                  Text(prMsg!, style: ts(17, w: FontWeight.w800)),
                ])),
              ]),
              g: P.hero,
            ),
          if (widget.music.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(onPressed: () => openLink(context, widget.music), icon: const Icon(Icons.music_note_rounded, size: 18), label: const Text('Music')),
            ),
          if (secMsg != null)
            card(
              Row(children: [
                gicon(Icons.swap_horiz_rounded, size: 34),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('NEW SECTION', style: ts(11, w: FontWeight.w900, c: P.ac, ls: 1.5)),
                  Text(secMsg!, style: ts(20, w: FontWeight.w900)),
                  Text('Next up: ${ex ?? ''}', style: ts(13, c: P.mu)),
                ])),
              ]),
              g: P.hero,
            ),
          if (ex == null)
            card(Text('Tap Add to choose your first exercise.', style: ts(14, c: P.mu)))
          else
            card(Column(children: [
              if ((secs[ex] ?? '').isNotEmpty) Text('SECTION · ${secs[ex]!.toUpperCase()}', style: ts(11, w: FontWeight.w900, c: P.ac, ls: 1.5)),
              Text(ex, style: ts(22, w: FontWeight.w800)),
              const SizedBox(height: 6),
              chips([mus[ex] ?? 'Other']),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if ((links[ex] ?? '').isNotEmpty) TextButton.icon(onPressed: () => watch(links[ex]!), icon: const Icon(Icons.play_circle_fill_rounded, size: 20), label: const Text('Play video (pauses timers)')),
                TextButton(onPressed: () => setLink(ex), child: Text((links[ex] ?? '').isEmpty ? 'Add video link' : 'Edit link')),
              ]),
              if (tS != null) ...[
                const SizedBox(height: 4),
                Text('Target: $tS sets × ${amt(ex, tR ?? 0)}${timed ? '' : ' reps'}', style: ts(13, c: P.mu)),
              ],
              if ((prev[ex] ?? []).isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: P.soft, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('LAST TIME', style: ts(10, w: FontWeight.w800, c: P.ac, ls: 1.5)),
                    const SizedBox(height: 2),
                    Text(prev[ex]!.map((x) => x['kind'] == 'time' ? tf(x['reps'] as int) : '${x['reps']}${kgOf(x) > 0 ? ' × ${numTxt(kgOf(x))}kg' : ''}').join('  ·  '), style: ts(13, w: FontWeight.w700)),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                for (var i = 0; i < nPills; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: i < mine.length ? kGrad : null,
                      color: i < mine.length ? null : P.soft,
                      borderRadius: BorderRadius.circular(14),
                      border: i == mine.length ? Border.all(color: kG1, width: 1.8) : null,
                    ),
                    child: Column(children: [
                      Text('SET ${i + 1}', style: ts(10, w: FontWeight.w700, c: i < mine.length ? Colors.black87 : P.mu)),
                      Text(i < mine.length ? '${amt(ex, mine[i]['reps'] as int)} ✓' : (tR != null ? amt(ex, tR) : '–'), style: ts(17, w: FontWeight.w900, c: i < mine.length ? Colors.black : null)),
                    ]),
                  ),
              ]),
              const SizedBox(height: 8),
              if (timed) ...[
                const SizedBox(height: 6),
                ShaderMask(shaderCallback: (r) => kGrad.createShader(r), child: Text(fmt(hold), style: ts(64, w: FontWeight.w900, c: Colors.white))),
                if (tR != null) ...[
                  gbar(hold / (tR < 1 ? 1 : tR), h: 10),
                  const SizedBox(height: 6),
                ],
              ] else
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(iconSize: 40, onPressed: () => setState(() => reps = reps > 0 ? reps - 1 : 0), icon: Icon(Icons.remove_circle_outline, color: P.mu)),
                  GestureDetector(
                    onTap: typeReps,
                    child: ShaderMask(
                      shaderCallback: (r) => kGrad.createShader(r),
                      child: SizedBox(width: 120, child: Text('$reps', textAlign: TextAlign.center, style: ts(76, w: FontWeight.w900, c: Colors.white))),
                    ),
                  ),
                  IconButton(iconSize: 40, onPressed: () => setState(() => reps++), icon: Icon(Icons.add_circle, color: P.ac)),
                ]),
              if (left != null)
                Text(
                  timed ? (left > 0 ? '${left}s left' : left == 0 ? 'Target reached ✓' : '+${-left}s over target') : (left > 0 ? '$left reps left' : left == 0 ? 'Target reached ✓' : '+${-left} over target'),
                  style: ts(16, w: FontWeight.w800, c: left <= 0 ? P.ac : P.mu),
                ),
              if (setsLeft != null) Text(setsLeft > 0 ? '$setsLeft ${setsLeft == 1 ? 'set' : 'sets'} left for this exercise' : 'All sets done for this exercise', style: ts(13, c: P.mu)),
              const SizedBox(height: 8),
              if (timed) ...[
                gbtn(holding ? 'Pause hold' : (hold > 0 ? 'Resume hold' : 'Start hold'), () => setState(() => holding = !holding), i: holding ? Icons.pause_rounded : Icons.timer_rounded),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  TextButton(onPressed: () => setState(() {
                        hold = 0;
                        holding = false;
                      }), child: const Text('Reset')),
                  TextButton(onPressed: typeReps, child: const Text('Type seconds')),
                  if (tR != null) TextButton(onPressed: () => setState(() => hold = tR), child: Text('Set to ${tR}s')),
                ]),
              ] else ...[
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  TextButton(onPressed: typeReps, child: const Text('Type total')),
                  if (tR != null) TextButton(onPressed: () => setState(() => reps = tR), child: Text('Set to $tR')),
                ]),
                TextField(controller: kg, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fld('Weight kg (optional)')),
                const SizedBox(height: 12),
              ],
              gbtn('Log set', logSet, i: Icons.check_rounded),
            ])),
          if (restLeft > 0)
            card(Row(children: [
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(size: const Size(76, 76), painter: RingPainter(restLeft / (restTot < 1 ? 1 : restTot), w: 8)),
                  Text(fmt(restLeft), style: ts(16, w: FontWeight.w900)),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Rest', style: ts(20, w: FontWeight.w800)),
                Text(ex != null && !doneEx(ex) ? 'Next: $ex, set ${mine.length + 1}' : 'Get ready for the next exercise', style: ts(13, c: P.mu)),
              ])),
              Column(children: [
                TextButton(onPressed: () => setState(() {
                      restLeft += 15;
                      restTot += 15;
                    }), child: const Text('+15s')),
                TextButton(onPressed: () => setState(() => restLeft = 0), child: const Text('Skip')),
              ]),
            ])),
          if (logged.isNotEmpty)
            card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ttl('Logged sets'),
              for (final s in logged.reversed)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${s['ex']}'),
                  trailing: Text('${amtOf(s)}${(s['kg'] as double) > 0 ? ' · ${s['kg']} kg' : ''}', style: ts(14, c: P.ac)),
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
                decoration: BoxDecoration(color: P.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: P.line)),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(22)),
                    child: Image.asset('${img}cover_${cover(r['m'] as List<String>)}.jpg', width: 100, height: 100, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r['name']}', style: ts(17, w: FontWeight.w800)),
                    Text('${r['n']} exercises', style: ts(13, c: P.mu)),
                    const SizedBox(height: 6),
                    chips((r['m'] as List<String>).toSet()),
                  ])),
                  Padding(padding: const EdgeInsets.all(12), child: Icon(Icons.edit_outlined, color: P.mu)),
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
  String curSec = '';
  String flexWhen = 'none';
  final music = TextEditingController();
  List<int> flexIds = [];
  Rows flexRows = [];

  @override
  void initState() {
    super.initState();
    loadFlex();
    if (widget.id != null) load();
  }

  Future<void> loadFlex() async {
    final f = await flexAll();
    if (mounted) setState(() => flexRows = f);
  }

  Future<void> load() async {
    final r = await DB.d.query('routines', where: 'id=?', whereArgs: [widget.id]);
    final it = await DB.d.query('items', where: 'rid=?', whereArgs: [widget.id], orderBy: 'id');
    final ids = <int>[];
    for (final x in ((r.first['flex_ids'] as String?) ?? '').split(',')) {
      final n = int.tryParse(x);
      if (n != null) ids.add(n);
    }
    setState(() {
      name.text = r.first['name'] as String;
      flexWhen = (r.first['flex_when'] as String?) ?? 'none';
      music.text = (r.first['music'] as String?) ?? '';
      flexIds = ids;
      items = [for (final e in it) Map<String, Object?>.from(e)];
      if (items.isNotEmpty) curSec = (items.last['sec'] as String?) ?? '';
    });
  }

  String sx(int k) => (items[k]['sec'] as String?) ?? '';

  List<String> get secNames {
    final out = <String>[];
    for (var k = 0; k < items.length; k++) {
      final x = sx(k);
      if (x.isNotEmpty && !out.contains(x)) out.add(x);
    }
    return out;
  }

  String fname(int id) {
    for (final f in flexRows) {
      if (f['id'] == id) return f['name'] as String;
    }
    return 'Removed stretch';
  }

  Future<void> add() async {
    final v = await askItem(context);
    if (v != null && v[0].isNotEmpty) {
      setState(() => items.add({'name': v[0], 'sets': int.tryParse(v[1]) ?? 3, 'reps': int.tryParse(v[2]) ?? 10, 'muscle': v[3], 'kind': v[4], 'sec': curSec}));
    }
  }

  Future<void> newSection() async {
    final v = await ask(context, 'Section name', hint: 'e.g. Defence, Strength, Conditioning');
    final t = (v ?? '').trim();
    if (t.isNotEmpty) setState(() => curSec = t);
  }

  void move(int i, int d) {
    final j = i + d;
    if (j < 0 || j >= items.length) return;
    setState(() {
      final x = items.removeAt(i);
      items.insert(j, x);
    });
  }

  Future<void> pickFlex() async {
    await loadFlex();
    if (!mounted) return;
    final sel = [...flexIds];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: P.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheet) => StatefulBuilder(
        builder: (sheet2, st) => SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
            Text('Choose stretches', style: ts(20, w: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('They run in the order you tick them.', style: ts(13, c: P.mu)),
            if (flexRows.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text('No stretches yet. Add some from Flexibility in the menu.', style: ts(14, c: P.mu))),
            for (final f in flexRows)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: kG1,
                value: sel.contains(f['id'] as int),
                title: Text(f['name'] as String),
                subtitle: Text(tf(f['amt'] as int)),
                onChanged: (v) => st(() {
                  final id = f['id'] as int;
                  if (v == true) {
                    if (!sel.contains(id)) sel.add(id);
                  } else {
                    sel.remove(id);
                  }
                }),
              ),
            const SizedBox(height: 8),
            gbtn('Done', () => Navigator.pop(sheet2), i: Icons.check_rounded),
          ]),
        ),
      ),
    );
    if (mounted) setState(() => flexIds = sel);
  }

  Future<void> save() async {
    final n = name.text.trim();
    if (n.isEmpty) return;
    int rid;
    final fx = {'name': n, 'flex_when': flexWhen, 'flex_ids': flexIds.join(','), 'music': music.text.trim()};
    if (widget.id == null) {
      rid = await DB.d.insert('routines', fx);
    } else {
      rid = widget.id!;
      await DB.d.update('routines', fx, where: 'id=?', whereArgs: [rid]);
      await DB.d.delete('items', where: 'rid=?', whereArgs: [rid]);
    }
    for (final i in items) {
      await DB.d.insert('items', {'rid': rid, 'name': i['name'], 'sets': i['sets'], 'reps': i['reps'], 'muscle': i['muscle'], 'kind': i['kind'], 'sec': (i['sec'] as String?) ?? ''});
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

  Widget secChip(String label, bool sel, VoidCallback f) => ChoiceChip(
        label: Text(label),
        selected: sel,
        showCheckmark: false,
        selectedColor: kG1,
        backgroundColor: P.soft,
        labelStyle: ts(13, w: FontWeight.w700, c: sel ? Colors.black : null),
        onSelected: (_) => f(),
      );

  @override
  Widget build(BuildContext context) {
    final names = secNames;
    return bg(Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text('Routine', style: ts(20, w: FontWeight.w800)), actions: [
        if (widget.id != null) IconButton(onPressed: del, icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
      ]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(controller: name, decoration: fld('Routine name')),
        const SizedBox(height: 12),
        TextField(controller: music, keyboardType: TextInputType.url, decoration: fld('Music link (Spotify playlist, optional)')),
        const SizedBox(height: 16),
        for (var i = 0; i < items.length; i++) ...[
          if (sx(i).isNotEmpty && (i == 0 || sx(i - 1) != sx(i)))
            Padding(padding: const EdgeInsets.only(top: 6, bottom: 8), child: Text('SECTION · ${sx(i).toUpperCase()}', style: ts(12, w: FontWeight.w900, c: P.ac, ls: 1.5))),
          card(Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${items[i]['name']}', style: ts(16, w: FontWeight.w800)),
              Text('${items[i]['sets']} sets × ${perSet(items[i])}', style: ts(14, c: P.mu)),
              const SizedBox(height: 6),
              chips([(items[i]['muscle'] as String?) ?? guess(items[i]['name'] as String)]),
            ])),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: P.mu),
              onSelected: (v) {
                if (v == 'up') {
                  move(i, -1);
                } else if (v == 'down') {
                  move(i, 1);
                } else if (v == 'sec') {
                  setState(() => items[i]['sec'] = curSec);
                } else {
                  setState(() => items.removeAt(i));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'up', child: Text('Move up')),
                const PopupMenuItem(value: 'down', child: Text('Move down')),
                PopupMenuItem(value: 'sec', child: Text(curSec.isEmpty ? 'Remove from section' : 'Put in "$curSec"')),
                const PopupMenuItem(value: 'del', child: Text('Delete')),
              ],
            ),
          ])),
        ],
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ADD TO SECTION', style: ts(11, w: FontWeight.w900, c: P.ac, ls: 1.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            secChip('No section', curSec.isEmpty, () => setState(() => curSec = '')),
            for (final x in names) secChip(x, curSec == x, () => setState(() => curSec = x)),
            if (curSec.isNotEmpty && !names.contains(curSec)) secChip(curSec, true, () {}),
            ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('New section'), backgroundColor: P.soft, onPressed: newSection),
          ]),
          const SizedBox(height: 8),
          Text('Exercises run top to bottom. When a section ends, the workout switches to the next one by itself.', style: ts(12, c: P.mu)),
        ])),
        gbtn('Add exercise', add, i: Icons.add_rounded),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('FLEXIBILITY FOR THIS SESSION', style: ts(11, w: FontWeight.w900, c: P.ac, ls: 1.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            secChip('None', flexWhen == 'none', () => setState(() => flexWhen = 'none')),
            secChip('Before workout', flexWhen == 'before', () => setState(() => flexWhen = 'before')),
            secChip('After workout', flexWhen == 'after', () => setState(() => flexWhen = 'after')),
          ]),
          if (flexWhen != 'none') ...[
            const SizedBox(height: 8),
            for (final id in flexIds)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(fname(id)),
                trailing: IconButton(onPressed: () => setState(() => flexIds.remove(id)), icon: Icon(Icons.close, color: P.mu)),
              ),
            TextButton.icon(onPressed: pickFlex, icon: const Icon(Icons.add), label: const Text('Choose stretches')),
          ],
        ])),
        gbtn('Save routine', save, i: Icons.check_rounded),
      ]),
    ));
  }
}

// ---------- stats ----------
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});
  @override
  Widget build(BuildContext context) => Async<St>(St.load, (c, st) {
        final w7 = st.days(7), d30 = st.days(30), d28 = st.days(28);
        final nw = DateTime.now();
        final mon0 = DateTime(nw.year, nw.month, nw.day - (nw.weekday - 1));
        final weeks = [for (var k = 7; k >= 0; k--) DateTime(mon0.year, mon0.month, mon0.day - 7 * k)];
        double wcount(DateTime a) {
          var n = 0;
          for (var k = 0; k < 7; k++) {
            if (st.wdays.contains(dk(DateTime(a.year, a.month, a.day + k)))) n++;
          }
          return n.toDouble();
        }

        const wd = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
        final m = <String, int>{};
        final best = <String, List<num>>{};
        final bt = <String, int>{};
        for (final s in st.ss) {
          final k = s['ex'] as String;
          final r = s['reps'] as int;
          if (s['kind'] == 'time') {
            bt[k] = math.max(bt[k] ?? 0, r);
            continue;
          }
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
            SizedBox(height: 160, width: double.infinity, child: CustomPaint(painter: BarsPainter([for (final x in w7) st.reps(dk(x))], [for (final x in w7) wd[x.weekday - 1]]))),
          ])),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ttl('Reps trend', 'last 30 days'),
            SizedBox(height: 170, width: double.infinity, child: CustomPaint(painter: TrendPainter([for (final x in d30) st.reps(dk(x))], l: ['${d30.first.day}/${d30.first.month}', '${d30[15].day}/${d30[15].month}', 'Today']))),
          ])),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ttl('Workout days per week', 'last 8 weeks'),
            SizedBox(height: 160, width: double.infinity, child: CustomPaint(painter: BarsPainter([for (final a in weeks) wcount(a)], [for (final a in weeks) '${a.day}/${a.month}']))),
          ])),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ttl('Muscles trained', 'share of total sets'),
            if (pv.isEmpty)
              Text('Finish a workout to see your muscle split.', style: ts(14, c: P.mu))
            else ...[
              SizedBox(
                height: 200,
                width: double.infinity,
                child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(size: const Size(200, 200), painter: PiePainter(pv, [for (final x in pm) mc(x)])),
                  Column(mainAxisSize: MainAxisSize.min, children: [Text('${ptot.round()}', style: ts(28, w: FontWeight.w900)), Text('sets', style: ts(14, c: P.mu))]),
                ]),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 14, runSpacing: 8, children: [
                for (var i = 0; i < pm.length; i++)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: mc(pm[i]), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${pm[i]} ${(pv[i] * 100 / ptot).round()}%', style: ts(13)),
                  ]),
              ]),
            ],
          ])),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ttl('Top exercises', 'total reps'),
            if (top.isEmpty) Text('Nothing logged yet.', style: ts(14, c: P.mu)),
            for (final e in top.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(e.key), Text('${e.value}', style: ts(14, w: FontWeight.w800, c: P.ac))]),
                  const SizedBox(height: 4),
                  gbar(e.value / mx),
                ]),
              ),
          ])),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ttl('Personal bests', 'most reps in one set · heaviest weight · longest hold'),
            if (top.isEmpty && bt.isEmpty) Text('Nothing logged yet.', style: ts(14, c: P.mu)),
            for (final e in bt.entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: gicon(Icons.timer_rounded),
                title: Text(e.key),
                trailing: Text('best hold ${tf(e.value)}', style: ts(14, w: FontWeight.w700, c: P.ac)),
              ),
            for (final e in top.take(6))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: gicon(Icons.emoji_events_rounded),
                title: Text(e.key),
                trailing: Text('${best[e.key]![1]} reps${best[e.key]![0] > 0 ? ' · ${best[e.key]![0].toDouble().toStringAsFixed(1)} kg' : ''}', style: ts(14, w: FontWeight.w700, c: P.ac)),
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
                    color: st.wdays.contains(dk(x)) ? null : (st.lg.contains(dk(x)) ? const Color(0x3300E676) : P.soft),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text('${x.day}', style: ts(11, c: st.wdays.contains(dk(x)) ? Colors.black : P.mu)),
                ),
            ]),
          ])),
          sbtn('Best exercises', () => Navigator.push(c, MaterialPageRoute(builder: (_) => sub('Best exercises', const BestPage()))), i: Icons.emoji_events_rounded),
          sbtn('Export data (CSV)', () => exportCsv(c), i: Icons.table_chart_rounded),
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
            ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.asset('${img}empty.jpg', height: 280, fit: BoxFit.cover)),
            const SizedBox(height: 14),
            Text('No workouts yet', textAlign: TextAlign.center, style: ts(22, w: FontWeight.w800)),
            Text('Finish your first workout and it will show up here.', textAlign: TextAlign.center, style: ts(14, c: P.mu)),
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
              decoration: BoxDecoration(color: P.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: P.line)),
              child: Theme(
                data: Theme.of(c).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: Text('${w['routine']}', style: ts(16, w: FontWeight.w800)),
                  subtitle: Text('${w['day']} · ${fmt(w['secs'] as int)} · ${(g[w['id']] ?? []).length} sets', style: ts(13, c: P.mu)),
                  children: [
                    for (final s in g[w['id']] ?? <Map<String, Object?>>[])
                      ListTile(
                        dense: true,
                        title: Text('${s['ex']}'),
                        trailing: Text('${amtOf(s)}${((s['kg'] as num?) ?? 0) > 0 ? ' · ${s['kg']} kg' : ''}', style: ts(14, c: P.ac)),
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

double kgOf(Map<String, Object?> r) => (r['kg'] as num?)?.toDouble() ?? 0.0;

Future<void> addPhoto(BuildContext c) async {
  final src = await showModalBottomSheet<ImageSource>(
    context: c,
    backgroundColor: P.card,
    builder: (b) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: gicon(Icons.photo_camera), title: const Text('Take photo'), onTap: () => Navigator.pop(b, ImageSource.camera)),
        ListTile(leading: gicon(Icons.photo_library), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(b, ImageSource.gallery)),
      ]),
    ),
  );
  if (src == null) return;
  final x = await ImagePicker().pickImage(source: src, maxWidth: 1280, imageQuality: 78);
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
      backgroundColor: P.card,
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
                  Text(l, style: ts(12, w: FontWeight.w900, c: P.ac, ls: 1.5)),
                  Text(ph == null ? 'no photo yet' : '${ph['day']}${kgOf(ph) > 0 ? ' · ${kgOf(ph)} kg' : ''}', style: ts(12, c: P.mu)),
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
  bool busy = false;
  bool embed = true;
  bool voiceOn = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    embed = (await DB.kv('embed')) != '0';
    voiceOn = Voice.on;
    last = await DB.kv('lastbackup') ?? '';
    name.text = await DB.kv('name') ?? '';
    rest.text = await DB.kv('rest') ?? '60';
    goal.text = await DB.kv('goal') ?? '4';
    st = await St.load();
    if (mounted) setState(() {});
  }

  void msg(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> backup() async {
    setState(() => busy = true);
    try {
      final s = await buildBackup();
      final f = File(p.join(Directory.systemTemp.path, 'fittrack_backup_${dk(DateTime.now())}.json'));
      await f.writeAsString(s);
      last = dk(DateTime.now());
      await DB.setKv('lastbackup', last);
      await Share.shareXFiles([XFile(f.path)], text: 'Vytron Fit backup');
      tick.value++;
    } catch (e) {
      if (mounted) msg('Backup failed. Try again.');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<bool> sure() async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          backgroundColor: P.card,
          title: const Text('Restore backup?'),
          content: const Text('This replaces your routines, weekly plan, history and photos with the backup.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Restore')),
          ],
        ),
      ) ??
      false;

  Future<void> after(String? err) async {
    await load();
    if (mounted) msg(err ?? 'Backup restored ✔');
  }

  Future<void> restore() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = r?.files.single.path;
    if (path == null || !mounted || !await sure()) return;
    setState(() => busy = true);
    final err = await importBackup(await File(path).readAsString());
    if (mounted) setState(() => busy = false);
    await after(err);
  }

  Future<void> restoreText() async {
    final clip = (await Clipboard.getData('text/plain'))?.text ?? '';
    if (!mounted || !await sure()) return;
    await after(await importBackup(clip));
  }

  Future<void> aiCopy() async {
    final data = await aiExport();
    await Clipboard.setData(ClipboardData(text: aiPrompt + data));
    if (mounted) msg('Copied. Paste it into your AI chat.');
  }

  Future<void> aiPaste() async {
    final clip = (await Clipboard.getData('text/plain'))?.text ?? '';
    final r = await aiImport(clip);
    if (mounted) msg(r);
  }

  Future<void> aiFile() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = r?.files.single.path;
    if (path == null) return;
    final res = await aiImport(await File(path).readAsString());
    if (mounted) msg(res);
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
          decoration: fld(l),
        ),
      );

  Widget lookChip(String l, String sub, IconData ic, int v) {
    final on = (P.vy ? 1 : 0) == v;
    return Expanded(
      child: GestureDetector(
        onTap: () => switchLook(context, v),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            gradient: on ? P.grad : null,
            color: on ? null : P.soft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? Colors.transparent : P.line),
          ),
          child: Column(children: [
            Icon(ic, color: on ? Colors.black : P.mu),
            const SizedBox(height: 4),
            Text(l, style: ts(13, w: FontWeight.w900, c: on ? Colors.black : null)),
            Text(sub, textAlign: TextAlign.center, style: ts(10, c: on ? Colors.black87 : P.mu)),
          ]),
        ),
      ),
    );
  }

  Widget themeChip(String l, IconData ic, ThemeMode m) {
    final on = themeMode.value == m;
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          await setTheme(m);
          if (mounted) setState(() {});
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(gradient: on ? kGrad : null, color: on ? null : P.soft, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Icon(ic, color: on ? Colors.black : P.mu),
            const SizedBox(height: 4),
            Text(l, style: ts(12, w: FontWeight.w800, c: on ? Colors.black : P.mu)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = st;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 120), children: [
      card(Column(children: [
        field('Your name', name, 'name'),
        field('Rest between sets (seconds)', rest, 'rest', n: true),
        field('Weekly workout goal', goal, 'goal', n: true),
      ])),
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ttl('App look', 'Switch the whole design. Your data stays the same.'),
        Row(children: [
          lookChip('Classic', 'Current design', Icons.grid_view_rounded, 0),
          lookChip('Vytron Gold', 'Obsidian · emerald · gold', Icons.workspace_premium_rounded, 1),
        ]),
      ])),
      if (!P.vy)
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ttl('Appearance'),
        Row(children: [
          themeChip('Dark', Icons.dark_mode_rounded, ThemeMode.dark),
          themeChip('Light', Icons.light_mode_rounded, ThemeMode.light),
          themeChip('System', Icons.phone_android_rounded, ThemeMode.system),
        ]),
      ])),
      if (s != null)
        Row(children: [
          tile(Icons.local_fire_department_rounded, '${s.streak(s.wdays)}', 'Workout streak'),
          tile(Icons.event_available_rounded, '${s.lg.length}', 'Days logged in'),
          tile(Icons.emoji_events_rounded, '${s.ws.length}', 'Workouts'),
        ]),
      const SizedBox(height: 14),
      card(SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeColor: P.ac,
        title: const Text('Play videos inside the app'),
        subtitle: Text('YouTube links play in the app with volume control. No sign-up. Needs internet. Off = opens the YouTube app.', style: ts(12, c: P.mu)),
        value: embed,
        onChanged: (v) async {
          setState(() => embed = v);
          await DB.setKv('embed', v ? '1' : '0');
        },
      )),
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: P.gold,
          activeTrackColor: P.gold.withOpacity(.35),
          title: Row(children: [
            const Icon(Icons.record_voice_over_rounded, color: P.gold, size: 22),
            const SizedBox(width: 10),
            const Flexible(child: Text('Voice coach')),
          ]),
          subtitle: Text('A deep male voice speaks when rest starts, when rest ends and when each exercise begins, so you do not have to look at the screen. The phone only speaks. It never listens.', style: ts(12, c: P.mu)),
          value: voiceOn,
          onChanged: (v) async {
            setState(() => voiceOn = v);
            await Voice.setOn(v);
            if (v) Voice.say('Voice coach on.');
          },
        ),
        goldBtn('Test voice', () {
          if (voiceOn) {
            Voice.say('Rest. 60 seconds. Next up, bench press.');
          } else {
            msg('Turn Voice coach on first.');
          }
        }, i: Icons.volume_up_rounded),
      ])),
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ttl('Backup & restore', last.isEmpty ? 'No backup yet' : 'Last backup: $last'),
        Text('Saves everything (routines, weekly plan, history and your photos) into one file. Share it to Google Drive, WhatsApp or Files. To restore, tap Restore and pick that file.', style: ts(12, c: P.mu)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: gbtn(busy ? 'Working…' : 'Save backup', busy ? () {} : backup, i: Icons.cloud_upload_rounded)),
          const SizedBox(width: 10),
          Expanded(child: sbtn('Restore', busy ? () {} : restore, i: Icons.restore_rounded)),
        ]),
        Center(child: TextButton(onPressed: restoreText, child: Text('Restore from copied text (v1.2 backup)', style: ts(12, c: P.mu)))),
      ])),
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ttl('AI workout builder', 'Let ChatGPT or any AI build your routines'),
        Text('1. Tap Copy and paste it into the AI chat.\n2. Write what you want after "MY REQUEST".\n3. Copy the AI reply, then tap Add from copied text. New routines and video links are added. Nothing is deleted.', style: ts(12, c: P.mu)),
        const SizedBox(height: 12),
        gbtn('Copy prompt + my routines', aiCopy, i: Icons.auto_awesome_rounded),
        Row(children: [
          Expanded(child: sbtn('Add from copied text', aiPaste, i: Icons.content_paste_rounded)),
          const SizedBox(width: 10),
          Expanded(child: sbtn('Add from file', aiFile, i: Icons.upload_file_rounded)),
        ]),
      ])),
      const ReminderCard(),
      const AdCodeCard(),
      Text('Vytron Fit v1.6.3 · all data is stored on this phone in a local SQLite database.', style: ts(12, c: P.mu), textAlign: TextAlign.center),
    ]);
  }
}


// ---------- flexibility ----------
class FlexPage extends StatelessWidget {
  const FlexPage({super.key});
  @override
  Widget build(BuildContext context) => Async<Rows>(
        flexAll,
        (c, rows) => ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Your stretch library. Add a YouTube link to each stretch so you can see how it is done. Attach stretches to any routine, before or after the workout.', style: ts(14, c: P.mu))),
          gbtn('Add stretch', () => Navigator.push(c, MaterialPageRoute(builder: (_) => const FlexEditPage(null))), i: Icons.add_rounded),
          for (final r in rows)
            GestureDetector(
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => FlexEditPage(r))),
              child: card(Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['name']}', style: ts(16, w: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${tf(r['amt'] as int)}${((r['url'] as String?) ?? '').isNotEmpty ? ' · video linked' : ''}', style: ts(13, c: P.mu)),
                ])),
                if (((r['url'] as String?) ?? '').isNotEmpty) IconButton(onPressed: () => openLink(c, r['url'] as String), icon: Icon(Icons.play_circle_fill_rounded, color: P.ac)),
                Icon(Icons.edit_outlined, color: P.mu, size: 18),
              ])),
            ),
        ]),
      );
}

class FlexEditPage extends StatefulWidget {
  final Map<String, Object?>? row;
  const FlexEditPage(this.row, {super.key});
  @override
  State<FlexEditPage> createState() => _FE();
}

class _FE extends State<FlexEditPage> {
  late final TextEditingController n, u, note;
  late int amt;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    n = TextEditingController(text: (r?['name'] as String?) ?? '');
    u = TextEditingController(text: (r?['url'] as String?) ?? '');
    note = TextEditingController(text: (r?['note'] as String?) ?? '');
    amt = (r?['amt'] as int?) ?? 30;
  }

  @override
  void dispose() {
    n.dispose();
    u.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final name = n.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a stretch name.')));
      return;
    }
    final v = {'name': name, 'url': u.text.trim(), 'amt': amt, 'kind': 'time', 'note': note.text.trim()};
    if (widget.row == null) {
      await DB.d.insert('flex', v);
    } else {
      await DB.d.update('flex', v, where: 'id=?', whereArgs: [widget.row!['id']]);
    }
    tick.value++;
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> del() async {
    await DB.d.delete('flex', where: 'id=?', whereArgs: [widget.row!['id']]);
    tick.value++;
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => bg(Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent, title: Text(widget.row == null ? 'New stretch' : 'Edit stretch', style: ts(20, w: FontWeight.w800)), actions: [
          if (widget.row != null) IconButton(onPressed: del, icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
        ]),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
          TextField(controller: n, textCapitalization: TextCapitalization.sentences, decoration: fld('Stretch name')),
          const SizedBox(height: 12),
          TextField(controller: u, keyboardType: TextInputType.url, decoration: fld('YouTube link (optional)')),
          const SizedBox(height: 12),
          stepper('Seconds', amt, (v) => setState(() => amt = v), step: 5, unit: 's'),
          TextField(controller: note, maxLines: 3, decoration: fld('Notes (how to do it)')),
          const SizedBox(height: 20),
          gbtn('Save', save, i: Icons.check_rounded),
        ]),
      ));
}

class FlexSessionPage extends StatefulWidget {
  final String title;
  final Rows rows;
  const FlexSessionPage(this.title, this.rows, {super.key});
  @override
  State<FlexSessionPage> createState() => _FX();
}

class _FX extends State<FlexSessionPage> {
  int i = 0, left = 0;
  bool running = false;
  Timer? t;

  Map<String, Object?> get cur => widget.rows[i];

  @override
  void initState() {
    super.initState();
    left = cur['amt'] as int;
    t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !running) return;
      setState(() {
        left--;
        if (left <= 0) {
          HapticFeedback.heavyImpact();
          if (i < widget.rows.length - 1) {
            i++;
            left = cur['amt'] as int;
          } else {
            left = 0;
            running = false;
          }
        }
      });
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  void go(int d) {
    final j = i + d;
    if (j < 0 || j >= widget.rows.length) return;
    setState(() {
      i = j;
      left = cur['amt'] as int;
      running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = cur;
    final total = r['amt'] as int;
    final url = (r['url'] as String?) ?? '';
    final note = (r['note'] as String?) ?? '';
    final last = i == widget.rows.length - 1;
    return bg(Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            Expanded(child: Text(widget.title, style: ts(20, w: FontWeight.w800))),
            TextButton(onPressed: () => Navigator.pop(context), child: Text('DONE', style: ts(14, w: FontWeight.w900, c: P.ac))),
          ]),
          const SizedBox(height: 8),
          card(Column(children: [
            Text('STRETCH ${i + 1} OF ${widget.rows.length}', style: ts(11, w: FontWeight.w900, c: P.ac, ls: 1.5)),
            const SizedBox(height: 8),
            Text('${r['name']}', textAlign: TextAlign.center, style: ts(24, w: FontWeight.w900)),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(note, textAlign: TextAlign.center, style: ts(14, c: P.mu)),
            ],
            const SizedBox(height: 12),
            ShaderMask(shaderCallback: (b) => kGrad.createShader(b), child: Text(fmt(left), style: ts(72, w: FontWeight.w900, c: Colors.white))),
            gbar(total == 0 ? 0 : (total - left) / total, h: 10),
            const SizedBox(height: 14),
            if (url.isNotEmpty) TextButton.icon(onPressed: () => openLink(context, url), icon: const Icon(Icons.play_circle_outline), label: const Text('Watch how to do it')),
            gbtn(running ? 'Pause' : (left < total && left > 0 ? 'Resume' : 'Start'), () => setState(() {
                  if (left <= 0) left = total;
                  running = !running;
                }), i: running ? Icons.pause_rounded : Icons.play_arrow_rounded),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              TextButton(onPressed: i > 0 ? () => go(-1) : null, child: const Text('Previous')),
              TextButton(onPressed: last ? () => Navigator.pop(context) : () => go(1), child: Text(last ? 'Finish' : 'Next')),
            ]),
          ])),
          const SizedBox(height: 4),
          ttl('Up next'),
          for (var k = i + 1; k < widget.rows.length; k++)
            ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text('${widget.rows[k]['name']}'), trailing: Text(tf(widget.rows[k]['amt'] as int), style: ts(13, c: P.mu))),
        ]),
      ),
    ));
  }
}

// ---------- exercise library ----------
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LB();
}

class _LB extends State<LibraryPage> {
  String q = '', m = 'All';
  bool onlyAdded = false;
  Map<String, String> links = {};
  Map<String, List<String>> used = {}; // lower-case name -> routines using it
  Map<String, String> shown = {}; // lower-case name -> display name
  Map<String, String> addedMuscle = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await DB.d.query('exlinks');
    final it = await DB.d.rawQuery('SELECT i.name AS name, i.muscle AS muscle, r.name AS rn FROM items i LEFT JOIN routines r ON r.id=i.rid');
    final u = <String, List<String>>{};
    final sh = <String, String>{};
    final am = <String, String>{};
    for (final x in it) {
      final n = (x['name'] as String?) ?? '';
      if (n.isEmpty) continue;
      final k = n.toLowerCase();
      sh.putIfAbsent(k, () => n);
      am.putIfAbsent(k, () => (x['muscle'] as String?) ?? guess(n));
      final rn = x['rn'] as String?;
      final l = u.putIfAbsent(k, () => <String>[]);
      if (rn != null && !l.contains(rn)) l.add(rn);
    }
    if (!mounted) return;
    setState(() {
      links = {for (final x in r) x['name'] as String: (x['url'] as String?) ?? ''};
      used = u;
      shown = sh;
      addedMuscle = am;
    });
  }

  Future<void> edit(String name) async {
    final v = await askLink(context, name, links[name] ?? '');
    if (v == null) return;
    await saveLink(name, v);
    await load();
  }

  Widget modeChip(String l, bool on, VoidCallback f, {bool gold = false}) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(l),
          selected: on,
          showCheckmark: false,
          selectedColor: gold ? P.gold : kG1,
          backgroundColor: P.card,
          side: BorderSide(color: gold ? P.gold.withOpacity(.6) : P.line),
          labelStyle: ts(13, w: FontWeight.w800, c: on ? Colors.black : (gold ? P.goldx : null)),
          onSelected: (_) => f(),
        ),
      );

  Widget addedView() {
    final keys = used.keys.where((k) => q.isEmpty || k.contains(q)).toList()..sort();
    if (keys.isEmpty) {
      return Padding(padding: const EdgeInsets.all(30), child: Text(used.isEmpty ? 'No exercises are in your workouts yet. Add exercises to a routine and they will show here in gold.' : 'No match.', textAlign: TextAlign.center, style: ts(14, c: P.mu)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      itemCount: keys.length,
      itemBuilder: (c, i) {
        final k = keys[i];
        final name = shown[k] ?? k;
        final mu = addedMuscle[k] ?? 'Other';
        final url = links[name] ?? '';
        final rs = used[k] ?? <String>[];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: P.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: P.gold.withOpacity(.7), width: 1.2)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.bookmark_rounded, color: P.goldx, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: ts(16, w: FontWeight.w800, c: P.goldx))),
              Text(mu, style: ts(12, c: mc(mu))),
            ]),
            if (rs.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('In: ${rs.join(', ')}', style: ts(12, c: P.mu))),
            const SizedBox(height: 10),
            Row(children: [
              if (url.isNotEmpty) ...[
                Expanded(child: pbtn('Play', () => openLink(context, url), i: Icons.play_arrow_rounded)),
                const SizedBox(width: 8),
              ],
              Expanded(child: pbtn(url.isEmpty ? 'Attach my link' : 'Change link', () => edit(name), i: Icons.link_rounded, fill: false)),
            ]),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = exLib.where((e) => (m == 'All' || e[1] == m) && (q.isEmpty || e[0].toLowerCase().contains(q))).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: TextField(decoration: fld(onlyAdded ? 'Search your added exercises' : 'Search ${exLib.length} exercises'), onChanged: (v) => setState(() => q = v.trim().toLowerCase())),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Row(children: [
          modeChip('All exercises', !onlyAdded, () => setState(() => onlyAdded = false)),
          modeChip('Already added (${used.length})', onlyAdded, () => setState(() => onlyAdded = true), gold: true),
        ]),
      ),
      if (onlyAdded)
        Expanded(child: addedView())
      else ...[
        SizedBox(
          height: 46,
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: 20), scrollDirection: Axis.horizontal, children: [
            for (final x in ['All', ...muscles.where((y) => y != 'Other')])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(x),
                  selected: m == x,
                  showCheckmark: false,
                  selectedColor: kG1,
                  backgroundColor: P.card,
                  labelStyle: ts(12, w: FontWeight.w700, c: m == x ? Colors.black : null),
                  onSelected: (_) => setState(() => m = x),
                ),
              ),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 4), child: Align(alignment: Alignment.centerLeft, child: Text('${rows.length} shown · gold = already in your workouts · tap one to add or edit its video link', style: ts(12, c: P.mu)))),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            itemCount: rows.length,
            itemBuilder: (c, k) {
              final e = rows[k];
              final url = links[e[0]] ?? '';
              final isAdded = used.containsKey(e[0].toLowerCase());
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: isAdded ? Icon(Icons.bookmark_rounded, color: P.goldx) : null,
                title: Text(e[0], style: ts(15, w: FontWeight.w700, c: isAdded ? P.goldx : null)),
                subtitle: Text(isAdded ? '${e[1]} · already added' : e[1], style: ts(12, c: isAdded ? P.goldx : mc(e[1]))),
                trailing: url.isNotEmpty ? IconButton(onPressed: () => openLink(c, url), icon: Icon(Icons.play_circle_fill_rounded, color: isAdded ? P.goldx : P.ac)) : Icon(Icons.link_rounded, color: P.mu, size: 18),
                onTap: () => edit(e[0]),
              );
            },
          ),
        ),
      ],
    ]);
  }
}

// ---------- in-app video player (v1.6) ----------
class VideoPage extends StatefulWidget {
  final String url, id;
  final bool workout;
  const VideoPage({super.key, required this.url, required this.id, this.workout = false});
  @override
  State<VideoPage> createState() => _VP();
}

class _VP extends State<VideoPage> {
  late final YoutubePlayerController ctl;
  double vol = 100;
  bool muted = false;

  @override
  void initState() {
    super.initState();
    ctl = YoutubePlayerController.fromVideoId(videoId: widget.id, autoPlay: true, params: const YoutubePlayerParams(showFullscreenButton: false, mute: false, origin: 'https://www.youtube-nocookie.com'));
  }

  @override
  void dispose() {
    ctl.close();
    super.dispose();
  }

  void setVol(double v) {
    setState(() {
      vol = v;
      muted = v < 1;
    });
    ctl.setVolume(v.round());
  }

  void toggleMute() {
    setState(() {
      muted = !muted;
      if (!muted && vol < 1) vol = 60;
    });
    ctl.setVolume(muted ? 0 : vol.round());
  }

  @override
  Widget build(BuildContext context) => bg(Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent, title: Text('Watch', style: ts(20, w: FontWeight.w800))),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
          ClipRRect(borderRadius: BorderRadius.circular(18), child: YoutubePlayer(controller: ctl, aspectRatio: 16 / 9)),
          const SizedBox(height: 14),
          card(Row(children: [
            IconButton(onPressed: toggleMute, icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: P.ac)),
            Expanded(child: Slider(value: vol, min: 0, max: 100, activeColor: P.ac, onChanged: setVol)),
            SizedBox(width: 44, child: Text(muted ? 'Mute' : '${vol.round()}%', textAlign: TextAlign.right, style: ts(13, w: FontWeight.w700))),
          ])),
          Text('${widget.workout ? 'Your workout timer and rest timer are paused. Go back and everything continues where you left off.\n\n' : ''}Plays here with sound, no sign-up needed. Your phone volume buttons work too. If a video will not play (the owner may block embedding), use the button below.', style: ts(12, c: P.mu)),
          const SizedBox(height: 14),
          sbtn('Open in YouTube', () => openExternal(context, widget.url), i: Icons.open_in_new_rounded),
        ]),
      ));
}


// ---------- Vytron Gold look (v1.5.4) ----------
List<Widget> vyTop(BuildContext c, {required String name, required String greet, required int total, required int week, required int streak, required int secs, void Function(int)? go}) {
  void open(Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));
  Widget big(IconData ic, String t, String sb, bool goldEdge, VoidCallback f) => Expanded(
        child: GestureDetector(
          onTap: f,
          child: Container(
            height: 122,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [(goldEdge ? P.gold : P.emerald).withOpacity(.16), P.card]),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: goldEdge ? P.gold : P.emerald, width: 1.3),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(ic, size: 30, color: goldEdge ? P.gold : P.emerald),
                const Spacer(),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: goldEdge ? P.gold : P.emerald),
                  child: const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.black),
                ),
              ]),
              const Spacer(),
              Text(t, style: ts(16, w: FontWeight.w800)),
              Text(sb, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11, c: P.mu)),
            ]),
          ),
        ),
      );
  Widget stat(IconData ic, String v, String l, Color col) => Expanded(
        child: Column(children: [
          Icon(ic, size: 24, color: col),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: ts(22, w: FontWeight.w900))),
          Text(l, textAlign: TextAlign.center, style: ts(11, c: P.mu)),
        ]),
      );
  Widget qa(IconData ic, String l, VoidCallback f, bool gold) => Expanded(
        child: GestureDetector(
          onTap: f,
          child: Container(
            height: 86,
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: P.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: P.emerald.withOpacity(.45))),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(ic, size: 28, color: gold ? P.gold : P.emerald),
              const SizedBox(height: 6),
              Text(l, textAlign: TextAlign.center, style: ts(12, w: FontWeight.w700)),
            ]),
          ),
        ),
      );
  final who = name.isEmpty ? 'ATHLETE' : name.toUpperCase();
  return [
    ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: SizedBox(
        height: 236,
        child: Stack(fit: StackFit.expand, children: [
          Image.asset('${img}home_banner.jpg', fit: BoxFit.cover, alignment: Alignment.centerRight),
          Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xFF050807), Color(0xE6050807), Color(0x33050807)]))),
          Container(decoration: BoxDecoration(gradient: RadialGradient(center: const Alignment(1, -.6), radius: 1.1, colors: [P.emerald.withOpacity(.25), Colors.transparent]))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${greet.toUpperCase()}, $who', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11, w: FontWeight.w800, c: P.gold, ls: 1.5)),
              const SizedBox(height: 8),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('Stronger Today.', style: ts(34, w: FontWeight.w800, c: Colors.white).copyWith(fontStyle: FontStyle.italic))),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: ShaderMask(
                  shaderCallback: (r) => const LinearGradient(colors: [P.emerald, P.gold]).createShader(r),
                  child: Text('Greater Tomorrow.', style: ts(34, w: FontWeight.w800, c: Colors.white).copyWith(fontStyle: FontStyle.italic)),
                ),
              ),
              const SizedBox(height: 8),
              Container(height: 2, width: 190, decoration: const BoxDecoration(gradient: LinearGradient(colors: [P.gold, Color(0x00D6B66C)]))),
              const SizedBox(height: 12),
              Text('TRAIN  ·  TRACK  ·  ACHIEVE', style: ts(11, c: P.mu, ls: 3)),
            ]),
          ),
        ]),
      ),
    ),
    const SizedBox(height: 14),
    Row(children: [
      big(Icons.fitness_center_rounded, 'Start Workout', 'Choose from ${exLib.length}+ exercises', true, () => pickRoutine(c)),
      big(Icons.trending_up_rounded, 'View Progress', 'Track your fitness journey', false, () => go?.call(2)),
    ]),
    const SizedBox(height: 14),
    Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: P.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: P.emerald.withOpacity(.45))),
      child: Row(children: [
        stat(Icons.emoji_events_rounded, '$total', 'Total Workouts', P.gold),
        Container(width: 1, height: 44, color: P.gold.withOpacity(.35)),
        stat(Icons.calendar_month_rounded, '$week', 'This Week', P.emerald),
        Container(width: 1, height: 44, color: P.gold.withOpacity(.35)),
        stat(Icons.local_fire_department_rounded, '$streak', 'Day Streak', P.gold),
        Container(width: 1, height: 44, color: P.gold.withOpacity(.35)),
        stat(Icons.schedule_rounded, secs >= 3600 ? '${(secs / 3600).toStringAsFixed(1)}h' : '${(secs / 60).round()}m', 'Total Training', P.emerald),
      ]),
    ),
    const SizedBox(height: 20),
    Row(children: [
      Text('//', style: ts(20, w: FontWeight.w900, c: P.gold)),
      const SizedBox(width: 8),
      Text('Quick Actions', style: ts(18, w: FontWeight.w800)),
      const Spacer(),
      GestureDetector(
        onTap: () => Scaffold.of(c).openDrawer(),
        child: Text('See All →', style: ts(13, w: FontWeight.w700, c: P.gold)),
      ),
    ]),
    const SizedBox(height: 8),
    Row(children: [
      qa(Icons.menu_book_rounded, 'Exercise\nLibrary', () => open(sub('Exercise library', const LibraryPage())), true),
      qa(Icons.event_note_rounded, 'Workout\nPlans', () => open(sub('My routines', const RoutinesPage())), false),
      qa(Icons.bar_chart_rounded, 'Track\nStats', () => go?.call(2), false),
    ]),
    Row(children: [
      qa(Icons.spa_rounded, 'Flexibility', () => open(sub('Flexibility', const FlexPage())), false),
      qa(Icons.emoji_events_rounded, 'Personal\nRecords', () => go?.call(5), false),
      qa(Icons.settings_rounded, 'Settings', () => go?.call(4), true),
    ]),
    const SizedBox(height: 14),
  ];
}

Widget vyBanner() => Container(
      margin: const EdgeInsets.only(top: 4),
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [P.gold.withOpacity(.22), P.card, P.emerald.withOpacity(.22)]),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: P.gold.withOpacity(.7), width: 1.3),
      ),
      child: Row(children: [
        const Icon(Icons.emoji_events_rounded, size: 46, color: P.gold),
        const SizedBox(width: 14),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Push Your Limits', style: ts(22, w: FontWeight.w800, c: P.gold).copyWith(fontStyle: FontStyle.italic)),
            Text('Be the best version of yourself', style: ts(13, c: P.mu)),
          ]),
        ),
      ]),
    );

// Animated switch between the two looks: a dark veil sweeps in, the look changes, then the shadow moves out.
Future<void> switchLook(BuildContext c, int v) async {
  if ((P.vy ? 1 : 0) == v) return;
  final ov = Overlay.of(c, rootOverlay: true);
  late OverlayEntry e;
  e = OverlayEntry(builder: (_) => StyleSweep(toVy: v == 1, onMid: () => setStyle(v), onDone: () => e.remove()));
  ov.insert(e);
}

class StyleSweep extends StatefulWidget {
  final bool toVy;
  final VoidCallback onMid, onDone;
  const StyleSweep({super.key, required this.toVy, required this.onMid, required this.onDone});
  @override
  State<StyleSweep> createState() => _SS();
}

class _SS extends State<StyleSweep> with SingleTickerProviderStateMixin {
  late final AnimationController ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  bool fired = false;

  @override
  void initState() {
    super.initState();
    ac.addListener(() {
      if (!fired && ac.value >= .5) {
        fired = true;
        widget.onMid();
      }
    });
    ac.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: ac,
            builder: (_, __) => Stack(fit: StackFit.expand, children: [
              CustomPaint(painter: SweepPainter(ac.value, widget.toVy)),
              Center(
                child: Opacity(
                  opacity: math.sin(math.pi * ac.value).clamp(0.0, 1.0).toDouble(),
                  child: Text(widget.toVy ? 'VYTRON FIT' : 'CLASSIC', style: ts(30, w: FontWeight.w900, c: widget.toVy ? P.gold : const Color(0xFF00E676), ls: 6)),
                ),
              ),
            ]),
          ),
        ),
      );
}

class SweepPainter extends CustomPainter {
  final double t;
  final bool toVy;
  SweepPainter(this.t, this.toVy);

  @override
  void paint(Canvas cv, Size s) {
    final diag = math.sqrt(s.width * s.width + s.height * s.height);
    final center = Offset(s.width / 2, s.height * .55);
    final veil = Paint()..color = const Color(0xFF050807);
    final edge = toVy ? P.gold : const Color(0xFF00E676);
    final inFirst = t < .5;
    final k = Curves.easeInOut.transform(((inFirst ? t : t - .5) / .5).clamp(0.0, 1.0).toDouble());
    final r = diag * k;
    if (inFirst) {
      cv.drawCircle(center, r, veil);
    } else {
      final path = Path.combine(PathOperation.difference, Path()..addRect(Rect.fromLTWH(0, 0, s.width, s.height)), Path()..addOval(Rect.fromCircle(center: center, radius: r)));
      cv.drawPath(path, veil);
    }
    if (r > 2) {
      cv.drawCircle(center, r + 18, Paint()..style = PaintingStyle.stroke..strokeWidth = 46..color = const Color(0x99000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26));
      cv.drawCircle(center, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 5..color = edge.withOpacity(.9)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      cv.drawCircle(center, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = edge);
    }
  }

  @override
  bool shouldRepaint(SweepPainter o) => o.t != t;
}
