// 오프라인 촬영 → 보관 → 새로고침 → 연결 복구 → 업로드를 실제로 확인하는
// 개발 하네스. 배포 번들에는 들어가지 않는다.
//
//   flutter run -t lib/dev/offline_capture_check.dart -d chrome \
//     --dart-define=VWORLD_KEY=...
//
// 진짜인 것: IndexedDB 보관소, UploadQueue, BoardComposer, 약도, SurveyStore,
//            페이지 새로고침(브라우저가 실제로 다시 로드한다).
// 가짜인 것: DriveService 하나. 로그인 없이 드라이브를 부를 수 없기 때문이다.
//            업로드 기록은 새로고침 뒤에도 보이도록 localStorage에 남긴다.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/survey.dart';
import '../models/survey_enums.dart';
import '../services/board_composer.dart';
import '../services/drive_service.dart';
import '../services/google_auth_service.dart';
import '../services/location_service.dart';
import '../services/offline/connectivity.dart';
import '../services/offline/photo_blob_store.dart';
import '../services/photo_pipeline.dart';
import '../services/survey_store.dart';
import '../services/upload_queue.dart';
import '../services/vworld_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  runApp(const _App());
}

/// 업로드를 흉내 내되, 기록은 새로고침 뒤에도 남긴다.
class _FakeDrive extends DriveService {
  _FakeDrive() : super(GoogleAuthService());

  static const String logKey = 'dev.upload_log';

  @override
  Future<DriveFile> ensureSurveyFolder(Survey survey) async {
    survey.driveFolderId ??= 'dev-folder';
    survey.driveFolderLink ??= 'https://drive.example/dev-folder';
    return const DriveFile(id: 'dev-folder', name: 'dev');
  }

  @override
  Future<DriveFile> uploadBytes({
    required Survey survey,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final log = prefs.getStringList(logKey) ?? <String>[];
    log.add('$fileName · ${(bytes.length / 1024).round()}KB');
    await prefs.setStringList(logKey, log);
    return DriveFile(id: 'dev-${log.length}', name: fileName);
  }
}

/// 화면에서 껐다 켤 수 있는 연결 상태.
class _ToggleConnectivity implements Connectivity {
  final _controller = StreamController<bool>.broadcast();
  bool _online = true;

  @override
  bool get isOnline => _online;

  @override
  Stream<bool> get changes => _controller.stream;

  void set(bool value) {
    if (_online == value) return;
    _online = value;
    _controller.add(value);
  }

  @override
  void dispose() => _controller.close();
}

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B57A4)),
    ),
    home: const _Harness(),
  );
}

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  static const String _stageKey = 'dev.stage';

  final PhotoBlobStore _blobs = PhotoBlobStore();
  final SurveyStore _store = SurveyStore();
  final _FakeDrive _drive = _FakeDrive();
  final _ToggleConnectivity _connectivity = _ToggleConnectivity();
  final VWorldService _vworld = VWorldService();

  late final UploadQueue _queue = UploadQueue(
    blobs: _blobs,
    drive: _drive,
    store: _store,
    connectivity: _connectivity,
  );
  late final PhotoPipeline _pipeline = PhotoPipeline(
    composer: BoardComposer(_vworld, maxEdge: 1400),
    location: _NoLocation(_vworld),
    queue: _queue,
  );

  final List<({String name, bool ok, String detail})> _results = [];
  String _stage = '';
  String _headline = '시작하는 중…';
  bool _done = false;
  Survey? _survey;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _queue.dispose();
    _connectivity.dispose();
    _vworld.dispose();
    super.dispose();
  }

  void _record(String name, bool ok, String detail) {
    _results.add((name: name, ok: ok, detail: detail));
    if (mounted) setState(() {});
  }

  void _expect(String name, bool condition, String detail) =>
      _record(name, condition, detail);

  /// 페이지가 열릴 때마다 단계를 보고 이어서 진행한다.
  /// 1단계와 2단계 사이에는 브라우저의 진짜 새로고침이 들어간다.
  Future<void> _run() async {
    final prefs = await SharedPreferences.getInstance();
    _stage = prefs.getString(_stageKey) ?? 'A';
    setState(() {});

    try {
      if (_stage == 'A') {
        await _stageOfflineCapture(prefs);
      } else {
        await _stageReconnect(prefs);
      }
    } catch (e, stack) {
      _record('예기치 못한 오류', false, '$e\n$stack');
    }
    if (mounted) setState(() => _done = true);
  }

  /// 1단계 - 오프라인에서 두 장 찍고 기기에 남는지 본다.
  Future<void> _stageOfflineCapture(SharedPreferences prefs) async {
    setState(() => _headline = '1단계 · 오프라인 촬영');

    // 깨끗한 상태에서 시작한다.
    await _blobs.removeAll(await _blobs.keys());
    await prefs.remove(_FakeDrive.logKey);
    for (final survey in await _store.loadAll()) {
      await _store.delete(survey.id);
    }

    _connectivity.set(false);
    _expect('오프라인 전환', !_connectivity.isOnline, '연결 없음');

    final survey = Survey(
      id: const Uuid().v4(),
      createdAt: DateTime.now(),
      surveyedAt: DateTime.now(),
      siteName: '○○천 좌안 제방 유실',
      inspectorName: '홍길동',
      disasterType: DisasterType.heavyRain,
      facilityType: FacilityType.river,
      addressParcel: '충청북도 제천시 청전동 482-18',
      latitude: 37.1447,
      longitude: 128.2013,
    );
    await _store.save(survey);
    _queue.track(survey);
    _survey = survey;

    for (var i = 0; i < 2; i++) {
      final bytes = await _syntheticPhoto(i);
      await _pipeline.process(
        survey: survey,
        photoBytes: bytes,
        caption: '촬영 ${i + 1}',
      );
      await _store.save(survey);
      if (mounted) setState(() {});
    }

    _expect('사진 2장 촬영됨', survey.photos.length == 2, '${survey.photos.length}장');
    _expect(
      '업로드되지 않음',
      (prefs.getStringList(_FakeDrive.logKey) ?? const <String>[]).isEmpty,
      '업로드 기록 없음',
    );
    _expect(
      '대기로 표시됨',
      survey.photos.every((p) => p.state == UploadState.pending),
      survey.photos.map((p) => p.state.name).join(', '),
    );
    _expect('큐 대기 건수', _queue.pendingCount == 2, '${_queue.pendingCount}건');

    final keys = await _blobs.keys()..sort();
    final fulls = keys.where((k) => k.startsWith('full:')).length;
    final thumbs = keys.where((k) => k.startsWith('thumb:')).length;
    _expect('원본이 IndexedDB에 보관됨', fulls == 2, 'full 키 $fulls개');
    _expect('축소본도 보관됨', thumbs == 2, 'thumb 키 $thumbs개');

    var stored = 0;
    for (final key in keys.where((k) => k.startsWith('full:'))) {
      stored += (await _blobs.get(key))?.length ?? 0;
    }
    _expect('보관된 사진 용량', stored > 0, '${(stored / 1024).round()}KB');

    await prefs.setString(_stageKey, 'B');
    setState(() => _headline = '1단계 완료 · 이제 페이지를 새로고침하세요');
  }

  /// 2단계 - 새로고침 뒤에도 남아 있는지, 연결되면 올라가는지 본다.
  Future<void> _stageReconnect(SharedPreferences prefs) async {
    setState(() => _headline = '2단계 · 새로고침 후 연결 복구');

    // 앱 시작과 같은 경로: 저장된 조사를 읽고 대기분을 이어받는다.
    final surveys = await _store.loadAll();
    _expect('새로고침 후 조사가 남아 있음', surveys.length == 1, '${surveys.length}건');
    if (surveys.isEmpty) return;

    final survey = surveys.first;
    _survey = survey;
    _queue.track(survey);

    _expect(
      '사진 기록이 대기 상태로 복구됨',
      survey.photos.length == 2 &&
          survey.photos.every((p) => p.state == UploadState.pending),
      '${survey.photos.length}장 · '
          '${survey.photos.map((p) => p.state.name).join(', ')}',
    );

    final before = await _blobs.keys();
    _expect(
      '보관된 원본이 새 세션에서도 읽힘',
      before.where((k) => k.startsWith('full:')).length == 2,
      before.where((k) => k.startsWith('full:')).join(', '),
    );

    // 메모리 캐시는 비어 있다. 보관소에서 되살아나야 목록에 사진이 보인다.
    _expect(
      '축소본이 메모리에 없음(새 세션)',
      survey.photos.every((p) => p.thumbnail == null),
      '캐시 비어 있음',
    );
    for (final photo in survey.photos) {
      await _queue.thumbnailOf(photo);
    }
    _expect(
      '축소본이 보관소에서 복구됨',
      survey.photos.every((p) => p.thumbnail != null),
      survey.photos
          .map((p) => '${(p.thumbnail?.length ?? 0) ~/ 1024}KB')
          .join(', '),
    );

    // 오프라인인 채로 먼저 시도해 본다. 올라가면 안 된다.
    _connectivity.set(false);
    await _queue.drain();
    _expect(
      '오프라인에서는 올리지 않음',
      (prefs.getStringList(_FakeDrive.logKey) ?? const <String>[]).isEmpty,
      '업로드 기록 없음',
    );

    // 연결 복구. online 이벤트만으로 자동 전송이 시작돼야 한다.
    _connectivity.set(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _queue.drain();

    final log = prefs.getStringList(_FakeDrive.logKey) ?? const <String>[];
    _expect('연결되자 자동 업로드됨', log.length == 2, log.join(' / '));
    _expect(
      '사진이 완료로 바뀜',
      survey.photos.every((p) => p.state == UploadState.done),
      survey.photos.map((p) => p.state.name).join(', '),
    );
    _expect('큐 대기 0', _queue.pendingCount == 0, '${_queue.pendingCount}건');

    final after = await _blobs.keys()..sort();
    _expect(
      '올라간 원본은 정리됨',
      after.every((k) => !k.startsWith('full:')),
      'full 키 ${after.where((k) => k.startsWith('full:')).length}개 남음',
    );
    _expect(
      '축소본은 제출 전까지 남음',
      after.where((k) => k.startsWith('thumb:')).length == 2,
      'thumb 키 ${after.where((k) => k.startsWith('thumb:')).length}개',
    );

    await _queue.releaseSurvey(survey);
    _expect('제출 후 보관소가 비워짐', (await _blobs.keys()).isEmpty, '0개');

    await prefs.setString(_stageKey, 'A');
    setState(() => _headline = '2단계 완료');
  }

  /// 카메라가 없는 환경이라 합성 입력을 그려서 만든다.
  /// 이후 경로(합성·보관·업로드)는 실제 코드 그대로다.
  Future<Uint8List> _syntheticPhoto(int index) async {
    const size = Size(1600, 1200);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            Color.lerp(const Color(0xFF4E6B57), const Color(0xFF8A6A45), index / 4)!,
            const Color(0xFF2E3B44),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );
    for (var i = 0; i < 9; i++) {
      canvas.drawCircle(
        Offset(180.0 + i * 150, 300.0 + (i.isEven ? 120 : 260)),
        44 + i * 6,
        Paint()..color = const Color(0x33FFFFFF),
      );
    }
    final painter = TextPainter(
      text: TextSpan(
        text: '모의 현장 ${index + 1}',
        style: const TextStyle(color: Colors.white70, fontSize: 72),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, const Offset(80, 120));

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    picture.dispose();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return png!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = _results.where((r) => !r.ok).length;
    final survey = _survey;

    return Scaffold(
      appBar: AppBar(
        title: Text('오프라인 촬영 점검 · 단계 $_stage'),
        backgroundColor: !_done
            ? theme.colorScheme.surfaceContainerHighest
            : failed == 0
            ? const Color(0xFFCDEBD3)
            : const Color(0xFFF5CFCB),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(_headline, style: theme.textTheme.titleMedium),
          Text(
            _done ? '검사 ${_results.length}건 · 실패 $failed건' : '실행 중…',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          for (final r in _results)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              minLeadingWidth: 26,
              leading: Icon(
                r.ok ? Icons.check_circle : Icons.error,
                color: r.ok ? Colors.green.shade600 : Colors.red.shade700,
                size: 19,
              ),
              title: Text(r.name, style: theme.textTheme.bodyMedium),
              subtitle: Text(r.detail, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 14),
          if (survey != null && survey.photos.isNotEmpty)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                for (final photo in survey.photos)
                  if (photo.thumbnail != null)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Image.memory(photo.thumbnail!, width: 240),
                        Text(
                          '${photo.caption} · ${photo.state.name}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 헤드리스 환경에는 위치 권한이 없다. 조사 대표 좌표를 그대로 쓰게 둔다.
class _NoLocation extends LocationService {
  const _NoLocation(super.vworld);

  @override
  Future<LocationResult> current() async =>
      throw const LocationUnavailable('개발 하네스: 위치 조회 없음');
}
