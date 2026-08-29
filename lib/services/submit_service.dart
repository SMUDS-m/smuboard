import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/survey.dart';
import '../models/survey_enums.dart';
import 'drive_service.dart';
import 'hwpx_builder.dart';
import 'upload_queue.dart';

/// 제출 산출물 한 항목의 진행 상태.
class SubmitItem {
  SubmitItem({required this.key, required this.label});

  final String key;
  final String label;

  UploadState state = UploadState.pending;
  String? link;
  String? error;
}

/// 검토·제출 화면의 진행 상태 전체.
class SubmitProgress {
  SubmitProgress(this.items);

  final List<SubmitItem> items;

  bool get isDone => items.every((i) => i.state == UploadState.done);

  bool get hasFailure => items.any((i) => i.state == UploadState.failed);
}

/// 조사 한 건에서 산출물 네 종을 만들어 드라이브에 올린다.
///
/// 항목끼리 서로를 기다리지 않는다. 하나가 실패해도 나머지는 올라가고,
/// 실패한 것만 다시 시도할 수 있다.
class SubmitService {
  SubmitService(this._drive, this._queue, {HwpxBuilder? hwpx})
    : _hwpx = hwpx ?? const HwpxBuilder();

  final DriveService _drive;
  final UploadQueue _queue;
  final HwpxBuilder _hwpx;

  static const String hwpxKey = 'hwpx';
  static const String jsonKey = 'json';
  static const String sheetKey = 'sheet';
  static const String photosKey = 'photos';

  SubmitProgress createProgress(Survey survey) {
    return SubmitProgress(<SubmitItem>[
      SubmitItem(key: hwpxKey, label: '현황조사표 (HWPX)'),
      SubmitItem(key: photosKey, label: '현장사진 ${survey.photos.length}장'),
      SubmitItem(key: jsonKey, label: '조사 원본 데이터 (JSON)'),
      SubmitItem(key: sheetKey, label: '구글 시트 집계표'),
    ]);
  }

  /// 아직 끝나지 않은 항목만 순서대로 처리한다. 재시도에도 같은 함수를 쓴다.
  Future<void> submit(
    Survey survey,
    SubmitProgress progress, {
    required VoidCallback onChanged,
  }) async {
    // 폴더는 모든 항목의 전제라 먼저 확보한다. 여기서 실패하면 전부 실패다.
    try {
      await _drive.ensureSurveyFolder(survey);
    } catch (e) {
      for (final item in progress.items) {
        if (item.state != UploadState.done) {
          item.state = UploadState.failed;
          item.error = '$e';
        }
      }
      onChanged();
      return;
    }

    for (final item in progress.items) {
      if (item.state == UploadState.done) continue;
      item.state = UploadState.uploading;
      item.error = null;
      onChanged();

      try {
        item.link = await _runItem(survey, item.key);
        item.state = UploadState.done;
      } catch (e) {
        item.state = UploadState.failed;
        item.error = '$e';
      }
      onChanged();
    }

    if (progress.isDone) {
      survey.submittedAt = DateTime.now();
      // 정본이 드라이브에 모두 올라갔으니 기기 보관본을 비운다.
      await _queue.releaseSurvey(survey);
      onChanged();
    }
  }

  Future<String?> _runItem(Survey survey, String key) async {
    switch (key) {
      case hwpxKey:
        return _uploadHwpx(survey);
      case photosKey:
        // 사진은 촬영 직후 큐가 올린다. 남은 것이 있으면 여기서 한 번 밀어 본다.
        if (survey.photos.any((p) => p.state != UploadState.done)) {
          await _queue.drain();
        }
        final pending = survey.photos
            .where((p) => p.state != UploadState.done)
            .length;
        if (pending > 0) {
          throw DriveException(
            _queue.isOnline
                ? '업로드되지 않은 사진이 $pending장 있습니다. 잠시 후 다시 시도해 주세요.'
                : '오프라인입니다. 사진 $pending장이 기기에 보관돼 있으며 연결되면 자동으로 올라갑니다.',
          );
        }
        return survey.driveFolderLink;
      case jsonKey:
        return _uploadJson(survey);
      case sheetKey:
        final file = await _drive.appendToSpreadsheet(survey);
        return file.link;
      default:
        throw StateError('알 수 없는 산출물: $key');
    }
  }

  Future<String?> _uploadHwpx(Survey survey) async {
    // 조사표에 넣을 사진은 템플릿 사진칸 수까지만 필요하다. 원본은 드라이브에
    // 있으므로 여기서는 보관된 축소본을 쓴다. 탭을 새로고침해 메모리 캐시가
    // 비었어도 보관소에서 되살아난다.
    final photos = <Uint8List>[];
    for (final photo in survey.photos) {
      final thumbnail = await _queue.thumbnailOf(photo);
      if (thumbnail != null) photos.add(thumbnail);
    }

    final bytes = await _hwpx.build(
      values: survey.toTemplateValues(),
      photos: photos,
    );

    final file = await _drive.uploadBytes(
      survey: survey,
      bytes: bytes,
      fileName: '현황조사표_${survey.folderName}.hwpx',
      mimeType: 'application/hwp+zip',
    );
    return file.link;
  }

  Future<String?> _uploadJson(Survey survey) async {
    final bytes = Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent('  ').convert(survey.toJson()),
      ),
    );
    final file = await _drive.uploadBytes(
      survey: survey,
      bytes: bytes,
      fileName: 'survey.json',
      mimeType: 'application/json',
    );
    return file.link;
  }
}
