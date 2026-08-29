import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_services.dart';
import '../models/survey.dart';
import '../models/survey_enums.dart';
import '../services/submit_service.dart';

/// 05 검토 · 제출. 산출물 네 종을 하나씩 올리고 진행률을 보여 준다.
class SubmitScreen extends StatefulWidget {
  const SubmitScreen({super.key, required this.survey});

  final Survey survey;

  @override
  State<SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<SubmitScreen> {
  late SubmitProgress _progress;
  bool _running = false;

  Survey get _survey => widget.survey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    services.queue.track(_survey);
    _progress = services.submit.createProgress(_survey);
  }

  Future<void> _submit() async {
    setState(() => _running = true);
    final services = AppScope.of(context);
    await services.submit.submit(
      _survey,
      _progress,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    await services.store.save(_survey);
    if (mounted) setState(() => _running = false);
  }

  Future<void> _openFolder() async {
    final link = _survey.driveFolderLink;
    if (link == null) return;
    await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = _survey.missingFields;

    return Scaffold(
      appBar: AppBar(title: const Text('검토 · 제출')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: _progress.isDone
              ? FilledButton.icon(
                  onPressed: _openFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('드라이브 폴더 열기'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                )
              : FilledButton.icon(
                  onPressed: _running ? null : _submit,
                  icon: _running
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload),
                  label: Text(_progress.hasFailure ? '실패한 항목 재시도' : '드라이브에 제출'),
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
                _survey.displayName,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_survey.surveyNumber} · ${_survey.disasterType.label} · '
                '사진 ${_survey.photos.length}장',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '저장 위치  내 드라이브 / SMUBoard 재난조사 / ${_survey.folderName}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              if (missing.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.5,
                    ),
                    border: Border(
                      left: BorderSide(color: theme.colorScheme.error, width: 3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '비어 있는 항목',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        missing.join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '이대로도 제출할 수 있습니다. 현장에서 확인이 어려운 항목은 나중에 채워 다시 제출하세요.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 22),
              Text('산출물', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final item in _progress.items) _ItemTile(item: item),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final SubmitItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: switch (item.state) {
        UploadState.done => Icon(
          Icons.check_circle,
          color: theme.colorScheme.primary,
        ),
        UploadState.uploading => const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
        UploadState.failed => Icon(
          Icons.error_outline,
          color: theme.colorScheme.error,
        ),
        UploadState.pending => Icon(
          Icons.radio_button_unchecked,
          color: theme.colorScheme.outline,
        ),
      },
      title: Text(item.label),
      subtitle: item.error == null
          ? null
          : Text(
              item.error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
      trailing: item.link == null
          ? null
          : IconButton(
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () => launchUrl(
                Uri.parse(item.link!),
                mode: LaunchMode.externalApplication,
              ),
            ),
    );
  }
}
