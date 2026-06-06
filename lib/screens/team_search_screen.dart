import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';
import '../models/models.dart';
import '../utils/clipboard_otp_mixin.dart';
import '../widgets/team_card.dart';
import '../widgets/empty_state.dart';
import '../dialogs/create_team_dialog.dart';
import '../version.dart';
import 'team_detail_screen.dart';

class TeamSearchScreen extends StatefulWidget {
  const TeamSearchScreen({super.key});

  @override
  State<TeamSearchScreen> createState() => _TeamSearchScreenState();
}

class _TeamSearchScreenState extends State<TeamSearchScreen>
    with
        AutomaticKeepAliveClientMixin,
        WidgetsBindingObserver,
        ClipboardOtpMixin {
  @override
  bool get wantKeepAlive => true;
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  List<TeamSearchResult> _teams = [];
  bool _loading = true;
  String? _error;
  late final StreamSubscription _recoverySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initClipboardOtp();
    _loadTeams();
    _recoverySub = _api.backendRecovered.stream.listen((_) => _loadTeams());
    _checkForAppUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    handleLifecycleForOtp(state);
  }

  Future<void> _checkForAppUpdate() async {
    if (kIsWeb) return;
    if (appVersion == 'APP_VERSION_PLACEHOLDER') return;
    if (!await UpdateService.isAutoUpdateEnabled()) return;
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final update = await UpdateService.checkForUpdate();
    if (update != null && mounted) {
      showUpdateDialog(context, update);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disposeClipboardOtp();
    _recoverySub.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTeams() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final teams = await _api.searchTeams(
        _searchController.text.isNotEmpty ? _searchController.text : null,
      );
      setState(() {
        _teams = teams;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openCreateTeamDialog() async {
    final teamId = await showCreateTeamDialog(
      context,
      clipboardOtp: clipboardOtp,
      pasteClipboardCode: pasteClipboardCode,
      launchAuthenticatorWithUri: launchAuthenticatorWithUri,
    );
    resetClipboardOtp();
    if (teamId != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TeamDetailScreen(teamId: teamId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateTeamDialog,
        tooltip: 'Create Team',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search teams...',
              leading: const Icon(Icons.search),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _loadTeams();
                    },
                  ),
              ],
              onSubmitted: (_) => _loadTeams(),
              onChanged: (_) {
                _loadTeams();
                setState(() {});
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadTeams,
              child: _buildBody(cs),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 200),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (_error != null) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: ErrorState(
              isNoInternet: _api.noInternet.value,
              title: _api.noInternet.value
                  ? 'No Internet Connection'
                  : 'Unable to Reach Server',
              subtitle: _api.noInternet.value
                  ? 'Check your internet connection and try again.'
                  : 'The backend server is not responding. It may be down for maintenance.',
              onRetry: _loadTeams,
            ),
          ),
        ),
      );
    }

    if (_teams.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: const EmptyState(
              icon: Icons.group_work,
              title: 'No teams found',
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        Widget teamItem(TeamSearchResult team) => TeamCard(
          team: team,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TeamDetailScreen(teamId: team.id),
              ),
            );
          },
        );

        if (isWide) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: constraints.maxWidth > 900 ? 3 : 2,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.4,
                ),
                itemCount: _teams.length,
                itemBuilder: (context, index) => teamItem(_teams[index]),
              ),
            ),
          );
        }

        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          itemCount: _teams.length,
          itemBuilder: (context, index) => teamItem(_teams[index]),
        );
      },
    );
  }
}
