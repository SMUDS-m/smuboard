import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../models/sketch_map_options.dart';
import '../models/survey.dart';
import '../models/survey_enums.dart';
import '../models/survey_photo.dart';
import '../services/upload_queue.dart';
import '../widgets/board_painter.dart';
import 'survey_form_screen.dart';

/// 03 현장 촬영. 촬영 → 합성 → 업로드가 한 사이클이다.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, required this.survey});

  final Survey survey;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final TextEditingController _caption = TextEditingController();

  bool _working = false;
  ui.Image? _previewSketch;
  String _sketchKey = '';
  UploadQueue? _queue;

  Survey get _survey => widget.survey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshSketch();
      _restoreThumbnails();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final queue = AppScope.of(context).queue;
    // 지난 세션에서 넘어온 조사도 갱신 대상으로 등록한다. 이걸 빠뜨리면 큐가
    // 저장소 사본만 고쳐, 화면이 쥔 사진 상태가 대기에 머문 것처럼 보인다.
    queue.track(_survey);
    if (identical(queue, _queue)) return;
    _queue?.removeListener(_onQueueChanged);
    _queue = queue..addListener(_onQueueChanged);
  }

  @override
  void dispose() {
    _queue?.removeListener(_onQueueChanged);
    _caption.dispose();
    _previewSketch?.dispose();
    super.dispose();
  }

  void _onQueueChanged() {
    if (mounted) setState(() {});
  }

  /// 탭을 새로고침하면 메모리의 축소본이 비어 있다. 보관소에서 되살린다.
  Future<void> _restoreThumbnails() async {
    final queue = AppScope.of(context).queue;
    var restored = false;
    for (final photo in _survey.photos) {
      if (photo.thumbnail != null) continue;
      if (await queue.thumbnailOf(photo) != null) restored = true;
    }
    if (restored && mounted) setState(() {});
  }

  void _save() => AppScope.of(context).store.save(_survey);

  /// 미리보기 약도. 설정이나 좌표가 바뀔 때만 다시 뽑는다.
  Future<void> _refreshSketch() async {
    final services = AppScope.of(context);
    if (!_survey.sketchMap.enabled ||
        !_survey.hasCoordinates ||
        !services.vworld.isConfigured) {
      _previewSketch?.dispose();
      if (mounted) {
        setState(() {
          _previewSketch = null;
          _sketchKey = '';
        });
      }
      return;
    }

    final key =
        '${_survey.latitude}/${_survey.longitude}/'
        '${_survey.sketchMap.zoom}/${_survey.sketchMap.layer.id}';
    if (key == _sketchKey) return;

    try {
      final image = await services.vworld.renderSketchMap(
        latitude: _survey.latitude!,
        longitude: _survey.longitude!,
        size: const Size(360, 270),
        zoom: _survey.sketchMap.zoom,
        layer: _survey.sketchMap.layer,
      );
      if (!mounted) {
        image.dispose();
        return;
      }
      _previewSketch?.dispose();
      setState(() {
        _previewSketch = image;
        _sketchKey = key;
      });
    } catch (e) {
      _toast('약도를 불러오지 못했습니다: $e');
    }
  }

  Future<void> _capture({required bool fromCamera}) async {
    final services = AppScope.of(context);
    setState(() => _working = true);
    try {
      final bytes = fromCamera
          ? await services.capture.takePhoto()
          : await services.capture.pickFromGallery();
      if (bytes == null || !mounted) return;

      await services.photos.process(
        survey: _survey,
        photoBytes: bytes,
        caption: _caption.text.trim(),
      );
      _caption.clear();
      if (mounted) setState(() {});
      _save();
    } catch (e) {
      _toast('사진을 처리하지 못했습니다: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _retryUploads() async {
    await AppScope.of(context).queue.drain();
    if (mounted) setState(() {});
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final theme = Theme.of(context);
    final pending = _survey.photos
        .where((p) => p.state != UploadState.done)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('현장 촬영'),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              _save();
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SurveyFormScreen(survey: _survey),
                ),
              );
              if (mounted) setState(() {});
            },
            child: const Text('조사표'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: <Widget>[
              _BoardPreview(survey: _survey, sketchMap: _previewSketch),
              const SizedBox(height: 14),

              TextField(
                controller: _caption,
                decoration: const InputDecoration(
                  labelText: '사진 설명',
                  hintText: '예) 제방 유실부 전경',
                  prefixIcon: Icon(Icons.short_text),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),

              Row(
                children: <Widget>[
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _working ? null : () => _capture(fromCamera: true),
                      icon: _working
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt),
                      label: const Text('촬영'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _working ? null : () => _capture(fromCamera: false),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('불러오기'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                ],
              ),

              if (!services.queue.isOnline || pending > 0) ...<Widget>[
                const SizedBox(height: 14),
                _QueueBanner(queue: services.queue, pending: pending),
              ],

              const SizedBox(height: 22),
              _sketchSettings(services.vworld.isConfigured),

              const Divider(height: 30),
              Row(
                children: <Widget>[
                  Text(
                    '촬영 ${_survey.photos.length}장',
                    style: theme.textTheme.titleSmall,
                  ),
                  const Spacer(),
                  if (pending > 0)
                    TextButton.icon(
                      onPressed: services.queue.isDraining
                          ? null
                          : _retryUploads,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('지금 올리기'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_survey.photos.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    '촬영한 사진은 기기에 먼저 보관되고, 연결되는 대로 드라이브에 올라갑니다.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                  itemCount: _survey.photos.length,
                  itemBuilder: (context, index) =>
                      _PhotoTile(photo: _survey.photos[index]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sketchSettings(bool configured) {
    final sketch = _survey.sketchMap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: sketch.enabled && configured,
          onChanged: configured
              ? (v) {
                  setState(() => _survey.sketchMap = sketch.copyWith(enabled: v));
                  _save();
                  _refreshSketch();
                }
              : null,
          title: const Text('약도 넣기 (브이월드)'),
          subtitle: Text(
            !configured
                ? '브이월드 인증키가 빌드에 주입되지 않았습니다.'
                : !_survey.hasCoordinates
                ? '조사 개요에서 위치를 가져오면 약도가 표시됩니다.'
                : '사진 모서리에 위치 지도를 합성합니다.',
          ),
        ),
        if (sketch.enabled && configured && _survey.hasCoordinates) ...<Widget>[
          Row(
            children: <Widget>[
              const SizedBox(width: 52, child: Text('배경')),
              Expanded(
                child: SegmentedButton<VWorldLayer>(
                  segments: <ButtonSegment<VWorldLayer>>[
                    for (final layer in VWorldLayer.values)
                      ButtonSegment<VWorldLayer>(
                        value: layer,
                        label: Text(layer.label),
                      ),
                  ],
                  selected: <VWorldLayer>{sketch.layer},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    setState(
                      () => _survey.sketchMap = sketch.copyWith(layer: s.first),
                    );
                    _save();
                    _refreshSketch();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const SizedBox(width: 52, child: Text('위치')),
              Expanded(
                child: SegmentedButton<SketchMapCorner>(
                  segments: <ButtonSegment<SketchMapCorner>>[
                    for (final corner in SketchMapCorner.values)
                      ButtonSegment<SketchMapCorner>(
                        value: corner,
                        label: Text(corner.label),
                      ),
                  ],
                  selected: <SketchMapCorner>{sketch.corner},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    setState(
                      () => _survey.sketchMap = sketch.copyWith(corner: s.first),
                    );
                    _save();
                  },
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              const SizedBox(width: 52, child: Text('확대')),
              Expanded(
                child: Slider(
                  value: sketch.zoom.toDouble(),
                  min: 12,
                  max: 19,
                  divisions: 7,
                  label: '${sketch.zoom}',
                  onChanged: (v) => setState(
                    () => _survey.sketchMap = sketch.copyWith(zoom: v.round()),
                  ),
                  onChangeEnd: (_) {
                    _save();
                    _refreshSketch();
                  },
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 오프라인이거나 올릴 것이 남았을 때만 보이는 상태 줄.
///
/// "실패"가 아니라 "보관됨"이라고 말한다 - 통신이 없는 것은 사용자 잘못이
/// 아니고, 사진은 실제로 안전하게 남아 있기 때문이다.
class _QueueBanner extends StatelessWidget {
  const _QueueBanner({required this.queue, required this.pending});

  final UploadQueue queue;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offline = !queue.isOnline;
    final tone = offline
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;

    final String message;
    if (offline) {
      message = pending > 0
          ? '오프라인입니다. 사진 $pending장이 기기에 보관돼 있고, 연결되면 자동으로 올라갑니다.'
          : '오프라인입니다. 촬영은 계속할 수 있고, 연결되면 자동으로 올라갑니다.';
    } else if (queue.isDraining) {
      message = '사진 $pending장을 올리는 중입니다.';
    } else {
      final retryIn = queue.retryIn;
      message = retryIn == null
          ? '사진 $pending장이 업로드를 기다리고 있습니다.'
          : '사진 $pending장 대기 중. ${retryIn.inSeconds}초 뒤 다시 시도합니다.';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: tone, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            offline ? Icons.cloud_off : Icons.cloud_upload_outlined,
            size: 18,
            color: tone,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(message, style: theme.textTheme.bodySmall),
                if (queue.lastError != null && !offline) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    queue.lastError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 촬영 전에 보드와 약도가 어떻게 찍힐지 보여 준다. 최종 합성과 같은 페인터다.
class _BoardPreview extends StatelessWidget {
  const _BoardPreview({required this.survey, this.sketchMap});

  final Survey survey;
  final ui.Image? sketchMap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: const Color(0xFF8C9AA5),
          child: CustomPaint(
            painter: BoardPainter(
              survey.toBoardData(capturedAt: DateTime.now()),
              sketchMap: sketchMap,
            ),
            child: const Center(
              child: Text(
                '미리보기',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo});

  final SurveyPhoto photo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbnail = photo.thumbnail;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (thumbnail != null)
            Image.memory(thumbnail, fit: BoxFit.cover)
          else
            ColoredBox(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Center(child: Icon(Icons.cloud_done, size: 20)),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      photo.caption.isEmpty ? '현장사진' : photo.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                  _StateBadge(photo: photo),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.photo});

  final SurveyPhoto photo;

  @override
  Widget build(BuildContext context) {
    return switch (photo.state) {
      UploadState.done => const Icon(Icons.check, size: 13, color: Colors.white),
      UploadState.uploading => const SizedBox(
        width: 11,
        height: 11,
        child: CircularProgressIndicator(strokeWidth: 1.6, color: Colors.white),
      ),
      UploadState.failed => Tooltip(
        message: photo.error ?? '업로드 실패',
        child: const Icon(
          Icons.error_outline,
          size: 14,
          color: Colors.orangeAccent,
        ),
      ),
      // 대기는 실패가 아니다. 기기에 보관돼 있고 연결되면 자동으로 올라간다.
      UploadState.pending => Tooltip(
        message: photo.error ?? '업로드 대기 - 기기에 보관됨',
        child: const Icon(Icons.schedule, size: 13, color: Colors.white70),
      ),
    };
  }
}
