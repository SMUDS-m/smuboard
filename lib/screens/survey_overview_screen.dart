import 'package:flutter/material.dart';

import '../app_services.dart';
import '../models/survey.dart';
import '../models/survey_enums.dart';
import '../services/location_service.dart';
import '../widgets/form_fields.dart';
import 'capture_screen.dart';

/// 02 조사 개요. 누가·언제·어디서·무슨 재난인지를 먼저 확정한다.
///
/// 여기서 채운 값이 사진 보드의 머리글과 약도 중심 좌표가 된다.
class SurveyOverviewScreen extends StatefulWidget {
  const SurveyOverviewScreen({super.key, required this.survey});

  final Survey survey;

  @override
  State<SurveyOverviewScreen> createState() => _SurveyOverviewScreenState();
}

class _SurveyOverviewScreenState extends State<SurveyOverviewScreen> {
  late final TextEditingController _siteName;
  late final TextEditingController _inspectorName;
  late final TextEditingController _inspectorContact;
  late final TextEditingController _organization;
  late final TextEditingController _weather;
  late final TextEditingController _addressParcel;

  bool _locating = false;

  Survey get _survey => widget.survey;

  @override
  void initState() {
    super.initState();
    _siteName = TextEditingController(text: _survey.siteName);
    _inspectorName = TextEditingController(text: _survey.inspectorName);
    _inspectorContact = TextEditingController(text: _survey.inspectorContact);
    _organization = TextEditingController(text: _survey.organization);
    _weather = TextEditingController(text: _survey.weather);
    _addressParcel = TextEditingController(text: _survey.addressParcel);
  }

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _siteName,
      _inspectorName,
      _inspectorContact,
      _organization,
      _weather,
      _addressParcel,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 값이 바뀔 때마다 즉시 저장한다. 모바일 웹은 탭이 언제 정리될지 모른다.
  void _save() {
    AppScope.of(context).store.save(_survey);
  }

  void _edit(VoidCallback change) {
    setState(change);
    _save();
  }

  Future<void> _fetchLocation() async {
    setState(() => _locating = true);
    try {
      final result = await AppScope.of(context).location.current();
      if (!mounted) return;
      _edit(() {
        _survey.latitude = result.latitude;
        _survey.longitude = result.longitude;
        final parcel = result.address?.parcel;
        final road = result.address?.road;
        if (parcel != null) {
          _survey.addressParcel = parcel;
          _addressParcel.text = parcel;
        }
        if (road != null) _survey.addressRoad = road;
      });
      _toast(
        result.address == null ? '좌표만 가져왔습니다(주소 변환 실패).' : '현재 위치를 채웠습니다.',
      );
    } on LocationUnavailable catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('위치를 가져오지 못했습니다: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _next() async {
    _save();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CaptureScreen(survey: _survey)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('조사 개요')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: FilledButton.icon(
            onPressed: _next,
            icon: const Icon(Icons.camera_alt),
            label: Text(
              _survey.photos.isEmpty
                  ? '현장 촬영으로'
                  : '현장 촬영으로 (${_survey.photos.length}장)',
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: <Widget>[
              Text(
                _survey.surveyNumber,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),

              ChoiceField<DisasterType>(
                label: '재난유형',
                values: DisasterType.values,
                selected: _survey.disasterType,
                labelOf: (v) => v.label,
                onChanged: (v) => _edit(() => _survey.disasterType = v),
              ),

              LabeledField(
                label: '현장명',
                hint: '예) ○○천 좌안 제방 유실',
                icon: Icons.place_outlined,
                controller: _siteName,
                onChanged: (v) {
                  _survey.siteName = v;
                  _save();
                  setState(() {});
                },
              ),

              DateTimeField(
                label: '재난 발생일시',
                value: _survey.occurredAt,
                onChanged: (v) => _edit(() => _survey.occurredAt = v),
              ),
              DateTimeField(
                label: '조사일시',
                value: _survey.surveyedAt,
                onChanged: (v) => _edit(() => _survey.surveyedAt = v),
              ),

              LabeledField(
                label: '기상조건',
                hint: '예) 3시간 누적강우 82mm, 순간최대풍속 18m/s',
                icon: Icons.cloud_outlined,
                controller: _weather,
                onChanged: (v) {
                  _survey.weather = v;
                  _save();
                },
              ),

              const Divider(height: 32),
              Text('위치', style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),

              LabeledField(
                label: '주소 (지번)',
                icon: Icons.map_outlined,
                controller: _addressParcel,
                onChanged: (v) {
                  _survey.addressParcel = v;
                  _save();
                },
                suffix: IconButton(
                  onPressed: _locating ? null : _fetchLocation,
                  tooltip: '현재 위치 가져오기',
                  icon: _locating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                ),
              ),
              if (_survey.addressRoad.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '도로명 ${_survey.addressRoad}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              Text(
                _survey.hasCoordinates
                    ? _survey.coordinateText
                    : '좌표 없음 - 약도를 넣으려면 위치를 가져와야 합니다.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _survey.hasCoordinates
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.error,
                ),
              ),

              const Divider(height: 32),
              Text('조사자', style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),

              LabeledField(
                label: '소속',
                icon: Icons.school_outlined,
                controller: _organization,
                onChanged: (v) {
                  _survey.organization = v;
                  _save();
                },
              ),
              LabeledField(
                label: '성명',
                icon: Icons.badge_outlined,
                controller: _inspectorName,
                onChanged: (v) {
                  _survey.inspectorName = v;
                  _save();
                },
              ),
              LabeledField(
                label: '연락처',
                icon: Icons.call_outlined,
                keyboardType: TextInputType.phone,
                controller: _inspectorContact,
                onChanged: (v) {
                  _survey.inspectorContact = v;
                  _save();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
