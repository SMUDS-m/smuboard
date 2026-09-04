import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../app_services.dart';
import '../config/app_config.dart';
import '../models/survey.dart';
import '../services/google_auth_service.dart';
import '../services/upload_queue.dart';
import '../widgets/smuds_logo.dart';
import 'survey_overview_screen.dart';

/// 메인 화면. 진행 중·완료된 조사가 카드로 쌓인다.
class SurveyListScreen extends StatefulWidget {
  const SurveyListScreen({super.key});

  @override
  State<SurveyListScreen> createState() => _SurveyListScreenState();
}

class _SurveyListScreenState extends State<SurveyListScreen> {
  List<Survey>? _surveys;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  Future<void> _reload() async {
    final surveys = await AppScope.of(context).store.loadAll();
    if (mounted) setState(() => _surveys = surveys);
  }

  Future<void> _open(Survey survey) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SurveyOverviewScreen(survey: survey),
      ),
    );
    await _reload();
  }

  Future<void> _createNew() async {
    final services = AppScope.of(context);
    final previous = _surveys?.firstOrNull;
    final now = DateTime.now();

    // 같은 조사자가 연달아 조사하는 경우가 대부분이다. 직전 조사자 정보를
    // 이어받아 매번 다시 입력하지 않게 한다.
    final survey = Survey(
      id: const Uuid().v4(),
      createdAt: now,
      surveyedAt: now,
      organization: previous?.organization ?? '세명대학교 재난안전학과',
      inspectorName: previous?.inspectorName ?? '',
      inspectorContact: previous?.inspectorContact ?? '',
    );
    await services.store.save(survey);
    if (mounted) await _open(survey);
  }

  Future<void> _signOut() async {
    await AppScope.of(context).auth.signOut();
  }

  /// 게스트로 들어온 뒤 여기서 로그인하면 대기 중이던 사진이 곧바로 올라간다.
  Future<void> _signIn() async {
    try {
      final account = await AppScope.of(context).auth.signIn();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${account.email} 계정으로 로그인했습니다.')),
      );
      await AppScope.of(context).queue.drain();
    } on GoogleAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final surveys = _surveys;
    final account = AppScope.of(context).auth.account;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const SmudsLogo(height: 30),
        actions: <Widget>[
          _PendingIndicator(queue: AppScope.of(context).queue),
          if (account == null)
            TextButton.icon(
              onPressed: _signIn,
              icon: const Icon(Icons.login, size: 18),
              label: const Text('로그인'),
            )
          else
            PopupMenuButton<String>(
              tooltip: account.email,
              icon: CircleAvatar(
                radius: 15,
                backgroundImage: account.photoUrl == null
                    ? null
                    : NetworkImage(account.photoUrl!),
                child: account.photoUrl == null
                    ? const Icon(Icons.person, size: 17)
                    : null,
              ),
              onSelected: (_) => _signOut(),
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(account.email),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'signOut',
                  child: Text('로그아웃'),
                ),
              ],
            ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNew,
        icon: const Icon(Icons.add),
        label: const Text('새 조사'),
      ),
      body: surveys == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                if (account == null) const _GuestBanner(),
                Expanded(child: _list(surveys)),
              ],
            ),
    );
  }

  Widget _list(List<Survey> surveys) {
    return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: surveys.isEmpty
                    ? const _EmptyState()
                    : RefreshIndicator(
                        onRefresh: _reload,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                          itemCount: surveys.length,
                          itemBuilder: (context, index) => _SurveyCard(
                            survey: surveys[index],
                            onTap: () => _open(surveys[index]),
                          ),
                        ),
                      ),
              ),
            );
  }
}

/// 로그인하지 않은 채 들어와 있다는 사실을 화면에 계속 붙여 둔다.
///
/// 조사와 촬영은 되지만 드라이브로는 아무것도 나가지 않는 상태이므로,
/// 이걸 모르고 현장에서 쓰면 다 올라간 줄 알게 된다.
class _GuestBanner extends StatelessWidget {
  const _GuestBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppConfig.allowGuest
                  ? '로그인하지 않은 상태입니다. 촬영은 기기에 저장되고, 로그인해야 드라이브로 올라갑니다.'
                  : '로그인이 필요합니다.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 업로드를 기다리는 사진이 있을 때만 보이는 표시.
///
/// 오프라인에서 촬영만 하고 앱을 닫았다가 다시 연 사용자가, 사진이 아직
/// 기기에 있다는 것을 목록 화면에서 바로 알 수 있어야 한다.
class _PendingIndicator extends StatelessWidget {
  const _PendingIndicator({required this.queue});

  final UploadQueue queue;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        if (queue.pendingCount == 0) return const SizedBox.shrink();
        final offline = !queue.isOnline;
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: TextButton.icon(
            onPressed: queue.isDraining ? null : queue.drain,
            icon: Icon(
              offline ? Icons.cloud_off : Icons.cloud_upload_outlined,
              size: 18,
            ),
            label: Text('${queue.pendingCount}'),
            style: TextButton.styleFrom(
              foregroundColor: offline
                  ? Theme.of(context).colorScheme.tertiary
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.assignment_outlined,
              size: 52,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('아직 조사가 없습니다', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '새 조사를 시작하면 여기에 쌓입니다.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurveyCard extends StatelessWidget {
  const _SurveyCard({required this.survey, required this.onTap});

  final Survey survey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateFormat(
      'yyyy-MM-dd',
    ).format(survey.surveyedAt ?? survey.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Chip(
                    label: Text(survey.disasterType.label),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  const Spacer(),
                  if (survey.isSubmitted)
                    Icon(
                      Icons.cloud_done,
                      size: 19,
                      color: theme.colorScheme.primary,
                    )
                  else
                    Icon(
                      Icons.edit_note,
                      size: 19,
                      color: theme.colorScheme.outline,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                survey.displayName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '$date · 사진 ${survey.photos.length}장'
                '${survey.isSubmitted ? ' · 제출 완료' : ' · 작성 중'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
