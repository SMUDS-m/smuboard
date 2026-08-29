import 'package:flutter/material.dart';

import '../app_services.dart';
import '../models/survey.dart';
import '../models/survey_enums.dart';
import '../widgets/form_fields.dart';
import 'submit_screen.dart';

/// 04 현황조사표. 피해시설·피해현황·원인·조치를 채운다.
///
/// 섹션을 접었다 펴는 형태라 긴 폼을 한 번에 마주하지 않는다.
class SurveyFormScreen extends StatefulWidget {
  const SurveyFormScreen({super.key, required this.survey});

  final Survey survey;

  @override
  State<SurveyFormScreen> createState() => _SurveyFormScreenState();
}

class _SurveyFormScreenState extends State<SurveyFormScreen> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};

  Survey get _survey => widget.survey;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String key, String initial) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: initial),
    );
  }

  void _save() => AppScope.of(context).store.save(_survey);

  void _edit(VoidCallback change) {
    setState(change);
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('현황조사표')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: FilledButton.icon(
            onPressed: () async {
              _save();
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SubmitScreen(survey: _survey),
                ),
              );
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('검토 · 제출로'),
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
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            children: <Widget>[
              SectionCard(
                title: 'D. 피해시설',
                subtitle: _survey.facilityName.isEmpty
                    ? _survey.facilityType.label
                    : '${_survey.facilityType.label} · ${_survey.facilityName}',
                initiallyExpanded: true,
                children: <Widget>[
                  ChoiceField<FacilityType>(
                    label: '시설유형',
                    values: FacilityType.values,
                    selected: _survey.facilityType,
                    labelOf: (v) => v.label,
                    onChanged: (v) => _edit(() => _survey.facilityType = v),
                  ),
                  LabeledField(
                    label: '시설명',
                    controller: _controllerFor('facility', _survey.facilityName),
                    onChanged: (v) {
                      _survey.facilityName = v;
                      _save();
                    },
                  ),
                  LabeledField(
                    label: '관리주체',
                    hint: '예) ○○시 하천과',
                    controller: _controllerFor('manager', _survey.manager),
                    onChanged: (v) {
                      _survey.manager = v;
                      _save();
                    },
                  ),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: LabeledField(
                          label: '연장 (m)',
                          keyboardType: TextInputType.number,
                          controller: _controllerFor('len', _survey.scaleLength),
                          onChanged: (v) {
                            _survey.scaleLength = v;
                            _save();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LabeledField(
                          label: '폭 (m)',
                          keyboardType: TextInputType.number,
                          controller: _controllerFor('wid', _survey.scaleWidth),
                          onChanged: (v) {
                            _survey.scaleWidth = v;
                            _save();
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: LabeledField(
                          label: '높이 (m)',
                          keyboardType: TextInputType.number,
                          controller: _controllerFor('hei', _survey.scaleHeight),
                          onChanged: (v) {
                            _survey.scaleHeight = v;
                            _save();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LabeledField(
                          label: '면적 (㎡)',
                          keyboardType: TextInputType.number,
                          controller: _controllerFor('area', _survey.scaleArea),
                          onChanged: (v) {
                            _survey.scaleArea = v;
                            _save();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              SectionCard(
                title: 'E. 피해현황',
                subtitle: _survey.damageLevel.label,
                children: <Widget>[
                  ChoiceField<DamageLevel>(
                    label: '피해정도',
                    values: DamageLevel.values,
                    selected: _survey.damageLevel,
                    labelOf: (v) => v.label,
                    onChanged: (v) => _edit(() => _survey.damageLevel = v),
                  ),
                  Text('인명피해 (명)', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: CountField(
                          label: '사망',
                          value: _survey.casualtyDead,
                          onChanged: (v) {
                            _survey.casualtyDead = v;
                            _save();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CountField(
                          label: '부상',
                          value: _survey.casualtyInjured,
                          onChanged: (v) {
                            _survey.casualtyInjured = v;
                            _save();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CountField(
                          label: '실종',
                          value: _survey.casualtyMissing,
                          onChanged: (v) {
                            _survey.casualtyMissing = v;
                            _save();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CountField(
                          label: '대피',
                          value: _survey.casualtyEvacuated,
                          onChanged: (v) {
                            _survey.casualtyEvacuated = v;
                            _save();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LabeledField(
                    label: '피해내용',
                    hint: '유실 구간, 침하량, 균열 폭 등 관측한 사실 위주로',
                    maxLines: 4,
                    controller: _controllerFor(
                      'damage',
                      _survey.damageDescription,
                    ),
                    onChanged: (v) {
                      _survey.damageDescription = v;
                      _save();
                    },
                  ),
                ],
              ),

              SectionCard(
                title: 'F. 원인 · 2차 위험',
                subtitle: '2차 위험도 ${_survey.riskLevel.label}',
                children: <Widget>[
                  LabeledField(
                    label: '추정 원인',
                    maxLines: 3,
                    controller: _controllerFor('cause', _survey.cause),
                    onChanged: (v) {
                      _survey.cause = v;
                      _save();
                    },
                  ),
                  ChoiceField<RiskLevel>(
                    label: '2차 피해 위험도',
                    values: RiskLevel.values,
                    selected: _survey.riskLevel,
                    labelOf: (v) => v.label,
                    onChanged: (v) => _edit(() => _survey.riskLevel = v),
                  ),
                  LabeledField(
                    label: '위험요인',
                    hint: '예) 상류 추가 강우 시 제방 추가 유실 우려',
                    maxLines: 3,
                    controller: _controllerFor('risk', _survey.riskFactor),
                    onChanged: (v) {
                      _survey.riskFactor = v;
                      _save();
                    },
                  ),
                ],
              ),

              SectionCard(
                title: 'G. 조치',
                children: <Widget>[
                  LabeledField(
                    label: '응급조치 · 통제사항',
                    hint: '예) 마대 적치 30m, 하천변 진입 통제',
                    maxLines: 3,
                    controller: _controllerFor(
                      'action',
                      _survey.emergencyAction,
                    ),
                    onChanged: (v) {
                      _survey.emergencyAction = v;
                      _save();
                    },
                  ),
                  LabeledField(
                    label: '조치의견 · 건의',
                    maxLines: 4,
                    controller: _controllerFor('opinion', _survey.opinion),
                    onChanged: (v) {
                      _survey.opinion = v;
                      _save();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
