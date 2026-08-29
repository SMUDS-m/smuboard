import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/survey.dart';
import 'google_auth_service.dart';

/// 드라이브에 올라간 파일 하나.
class DriveFile {
  const DriveFile({required this.id, required this.name, this.link});

  final String id;
  final String name;
  final String? link;
}

class DriveException implements Exception {
  const DriveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 조사 산출물을 구글 드라이브에 올린다.
///
/// 폴더 구조는 `내 드라이브/SMUBoard 재난조사/{날짜}_{현장명}/`이고,
/// 전 조사건을 한 줄씩 쌓는 집계표 스프레드시트를 루트 폴더에 하나 둔다.
class DriveService {
  DriveService(this._auth);

  final GoogleAuthService _auth;

  static const String rootFolderName = 'SMUBoard 재난조사';
  static const String spreadsheetName = '조사집계표';
  static const String _sheetIdKey = 'smuboard.spreadsheet_id';
  static const String _folderMime = 'application/vnd.google-apps.folder';

  String? _rootFolderId;

  /// 조사 폴더를 만들거나 찾는다. 이미 만든 폴더는 조사 객체가 기억한다.
  Future<DriveFile> ensureSurveyFolder(Survey survey) async {
    final existing = survey.driveFolderId;
    if (existing != null) {
      return DriveFile(
        id: existing,
        name: survey.folderName,
        link: survey.driveFolderLink,
      );
    }

    final api = await _drive();
    final root = await _ensureRootFolder(api);
    final folder = await _findOrCreateFolder(api, survey.folderName, root);
    survey.driveFolderId = folder.id;
    survey.driveFolderLink = folder.link;
    return folder;
  }

  /// 파일 한 개를 조사 폴더에 올린다.
  Future<DriveFile> uploadBytes({
    required Survey survey,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final folder = await ensureSurveyFolder(survey);
    final api = await _drive();

    try {
      final created = await api.files.create(
        drive.File()
          ..name = fileName
          ..parents = <String>[folder.id],
        uploadMedia: drive.Media(
          Stream<List<int>>.value(bytes),
          bytes.length,
          contentType: mimeType,
        ),
        $fields: 'id,name,webViewLink',
      );
      return DriveFile(
        id: created.id!,
        name: created.name ?? fileName,
        link: created.webViewLink,
      );
    } on drive.DetailedApiRequestError catch (e) {
      throw DriveException('업로드 실패 (${e.status}): ${e.message ?? fileName}');
    }
  }

  /// 집계표에 조사 한 건을 한 줄로 덧붙인다.
  ///
  /// 시트가 없으면 만들고 머리글을 먼저 넣는다. 시트 ID는 기기에 저장해 두고
  /// 다음 조사부터 같은 표에 쌓는다.
  Future<DriveFile> appendToSpreadsheet(Survey survey) async {
    final client = await _auth.authClient();
    final sheetsApi = sheets.SheetsApi(client);
    final prefs = await SharedPreferences.getInstance();

    var spreadsheetId = prefs.getString(_sheetIdKey);
    var created = false;

    if (spreadsheetId == null) {
      final created0 = await sheetsApi.spreadsheets.create(
        sheets.Spreadsheet(
          properties: sheets.SpreadsheetProperties(title: spreadsheetName),
        ),
        $fields: 'spreadsheetId',
      );
      spreadsheetId = created0.spreadsheetId!;
      await prefs.setString(_sheetIdKey, spreadsheetId);
      created = true;

      // 새로 만든 시트는 마이 드라이브 최상위에 생긴다. 조사 폴더 옆으로 옮긴다.
      final api = await _drive();
      final root = await _ensureRootFolder(api);
      await api.files.update(
        drive.File(),
        spreadsheetId,
        addParents: root,
        $fields: 'id',
      );
    }

    try {
      if (created) {
        await sheetsApi.spreadsheets.values.append(
          sheets.ValueRange(values: <List<Object?>>[Survey.sheetHeader]),
          spreadsheetId,
          'A1',
          valueInputOption: 'USER_ENTERED',
        );
      }
      await sheetsApi.spreadsheets.values.append(
        sheets.ValueRange(values: <List<Object?>>[survey.toSheetRow()]),
        spreadsheetId,
        'A1',
        valueInputOption: 'USER_ENTERED',
      );
    } on sheets.DetailedApiRequestError catch (e) {
      // 시트를 사용자가 지웠을 수 있다. 다음 제출에서 새로 만들도록 잊는다.
      if (e.status == 404) {
        await prefs.remove(_sheetIdKey);
      }
      throw DriveException('집계표 기록 실패 (${e.status}): ${e.message ?? ''}');
    }

    return DriveFile(
      id: spreadsheetId,
      name: spreadsheetName,
      link: 'https://docs.google.com/spreadsheets/d/$spreadsheetId',
    );
  }

  Future<drive.DriveApi> _drive() async =>
      drive.DriveApi(await _auth.authClient());

  Future<String> _ensureRootFolder(drive.DriveApi api) async {
    final cached = _rootFolderId;
    if (cached != null) return cached;
    final folder = await _findOrCreateFolder(api, rootFolderName, null);
    return _rootFolderId = folder.id;
  }

  Future<DriveFile> _findOrCreateFolder(
    drive.DriveApi api,
    String name,
    String? parentId,
  ) async {
    final escaped = name.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final query = <String>[
      "name = '$escaped'",
      "mimeType = '$_folderMime'",
      'trashed = false',
      if (parentId != null) "'$parentId' in parents",
    ].join(' and ');

    try {
      final found = await api.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id,name,webViewLink)',
        pageSize: 1,
      );
      final files = found.files;
      if (files != null && files.isNotEmpty) {
        return DriveFile(
          id: files.first.id!,
          name: files.first.name ?? name,
          link: files.first.webViewLink,
        );
      }

      final created = await api.files.create(
        drive.File()
          ..name = name
          ..mimeType = _folderMime
          ..parents = parentId == null ? null : <String>[parentId],
        $fields: 'id,name,webViewLink',
      );
      return DriveFile(
        id: created.id!,
        name: created.name ?? name,
        link: created.webViewLink,
      );
    } on drive.DetailedApiRequestError catch (e) {
      throw DriveException('폴더 준비 실패 (${e.status}): ${e.message ?? name}');
    }
  }
}
