import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/survey.dart';

/// 조사 목록을 기기에 보관한다.
///
/// 사진 바이트는 넣지 않는다. localStorage는 보통 5MB 남짓이라 사진 한 장에도
/// 넘치고, 사진의 정본은 이미 드라이브에 있기 때문이다.
class SurveyStore {
  static const String _key = 'smuboard.surveys';

  Future<List<Survey>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return <Survey>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final surveys = list
          .cast<Map<String, dynamic>>()
          .map(Survey.fromJson)
          .toList();
      surveys.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return surveys;
    } catch (e) {
      debugPrint('조사 목록을 읽지 못했습니다: $e');
      return <Survey>[];
    }
  }

  /// 한 건을 저장한다. 같은 id가 있으면 덮어쓴다.
  Future<void> save(Survey survey) async {
    final surveys = await loadAll();
    final index = surveys.indexWhere((s) => s.id == survey.id);
    if (index >= 0) {
      surveys[index] = survey;
    } else {
      surveys.insert(0, survey);
    }
    await _write(surveys);
  }

  Future<void> delete(String id) async {
    final surveys = await loadAll();
    surveys.removeWhere((s) => s.id == id);
    await _write(surveys);
  }

  Future<void> _write(List<Survey> surveys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(surveys.map((s) => s.toJson()).toList()),
    );
  }
}
