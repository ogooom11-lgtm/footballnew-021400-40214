import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/page_routes.dart';
import '../game/enums/ai_difficulty.dart';
import '../game/enums/ai_play_style.dart';
import '../game/enums/match_mode.dart';
import '../game/enums/player_role.dart';
import '../game/enums/team_id.dart';
import '../game/models/formation.dart';
import '../game/models/jersey_kit.dart';
import '../game/models/match_event.dart';
import '../game/models/player_profile.dart';
import '../game/models/shooting.dart';
import '../game/models/team_profile.dart';
import '../game/models/team_setup.dart';
import '../storage/roster_storage.dart';
import 'account_detail_screen.dart';
import 'free_agents_screen.dart';
import 'game_screen.dart';
import 'team_players_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final RosterStorage _storage = RosterStorage();
  final TextEditingController _newAccountController = TextEditingController();
  final TextEditingController _newPlayerController = TextEditingController();
  final TextEditingController _newTeamController = TextEditingController();
  final TextEditingController _importPlayersPathController =
      TextEditingController();
  final TextEditingController _blueNameController = TextEditingController();
  final TextEditingController _redNameController = TextEditingController();
  final FocusNode _keyboardFocus = FocusNode();
  final Set<LogicalKeyboardKey> _pressedKeys = <LogicalKeyboardKey>{};
  SavedGameData? _data;
  bool _newIsGoalkeeper = false;
  int _setupTab = 0;
  bool _blueAiControlled = false;
  bool _redAiControlled = false;
  AiDifficulty _aiDifficulty = AiDifficulty.medium;
  AiPlayStyle _bluePlayStyle = AiPlayStyle.balanced;
  AiPlayStyle _redPlayStyle = AiPlayStyle.balanced;
  int _blueKitIndex = 0;
  int _redKitIndex = 0;
  Timer? _adminUnlockTimer;
  final TextEditingController _adminPasswordController =
      TextEditingController();
  bool _showAdminPasswordField = false;
  bool _adminPasswordError = false;

  /// True while the match is being prepared: shows the bouncing-ball
  /// loading splash instead of jumping straight into the game.
  bool _startingMatch = false;
  int _pendingAdminTab = 6;
  int _adminSubTab = 0;
  String? _adminValueTeamId;
  String? _adminBulkAttribute;
  int _adminBulkStep = 1;
  final Set<String> _adminSelectedPlayerIds = <String>{};
  String _penaltySearch = '';
  String _accountSearch = '';
  String _teamSearch = '';
  String _playerSearch = '';
  String _playerPoolSort = 'points';
  String _adminPlayerSearch = '';
  String _adminTeamSearch = '';
  String _countrySearch = '';
  String _countryPageSearch = '';
  String _countriesSort = 'value';
  String? _adminKitsTeamId;
  final TextEditingController _adminNewTeamController = TextEditingController();
  final Map<String, String> _lineupSearchByTeam = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newAccountController.dispose();
    _newPlayerController.dispose();
    _newTeamController.dispose();
    _importPlayersPathController.dispose();
    _blueNameController.dispose();
    _redNameController.dispose();
    _adminUnlockTimer?.cancel();
    _adminPasswordController.dispose();
    _adminNewTeamController.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await _storage.load();
    if (!mounted) {
      return;
    }
    // Keep the current admin session alive across in-app page reloads.
    // It only expires when the app restarts or the admin locks it.
    final previous = _data;
    if (previous != null && previous.adminLoggedIn) {
      data.adminLoggedIn = true;
      data.adminFullAccess = previous.adminFullAccess;
    }
    _blueNameController.text = data.blueTeam.name;
    _redNameController.text = data.redTeam.name;
    _blueAiControlled = data.blueAiControlled;
    _redAiControlled = data.redAiControlled;
    _aiDifficulty = data.aiDifficulty;
    _bluePlayStyle = data.bluePlayStyle;
    _redPlayStyle = data.redPlayStyle;
    _blueKitIndex = data.blueTeam.activeKitIndex;
    _redKitIndex = data.redTeam.activeKitIndex;
    setState(() => _data = data);
  }

  Future<void> _save() async {
    final data = _data;
    if (data == null) {
      return;
    }
    if (data.isTeamOwnerLoggedIn(data.blueTeam)) {
      data.blueTeam
        ..name = _blueNameController.text.trim().isEmpty
            ? 'Mavi Takim'
            : _blueNameController.text.trim()
        ..formation = data.blueFormation
        ..playStyle = _bluePlayStyle
        ..aiDifficulty = _aiDifficulty
        ..playerIds = data.bluePlayerIds;
    }
    if (data.isTeamOwnerLoggedIn(data.redTeam)) {
      data.redTeam
        ..name = _redNameController.text.trim().isEmpty
            ? 'Kirmizi Takim'
            : _redNameController.text.trim()
        ..formation = data.redFormation
        ..playStyle = _redPlayStyle
        ..aiDifficulty = _aiDifficulty
        ..playerIds = data.redPlayerIds;
    }
    for (final team in data.teams) {
      team.ensureLineupDefaults(data.players);
    }
    data
      ..blueName = data.blueTeam.name
      ..redName = data.redTeam.name
      ..blueAiControlled = _blueAiControlled
      ..redAiControlled = _redAiControlled
      ..aiDifficulty = _aiDifficulty
      ..bluePlayStyle = _bluePlayStyle
      ..redPlayStyle = _redPlayStyle;
    data.blueTeam.activeKitIndex = _blueKitIndex;
    data.redTeam.activeKitIndex = _redKitIndex;
    await _storage.save(data);
  }

  Future<void> _addAccount() async {
    final data = _data;
    if (data == null || _newAccountController.text.trim().isEmpty) {
      return;
    }
    final password = await _askPassword('Yeni hesap sifresi', requireNew: true);
    if (password == null) {
      return;
    }
    final account = SavedAccountProfile.create(
      _newAccountController.text,
      password: password,
    );
    setState(() {
      data.accounts.add(account);
      data.activeAccountId = account.id;
      data.loggedInAccountIds.add(account.id);
      _newAccountController.clear();
      _setupTab = 1;
    });
    await _save();
  }

  Future<void> _switchAccount(String id) async {
    final data = _data;
    if (data == null) {
      return;
    }
    final account = data.accounts.firstWhere((account) => account.id == id);
    if (!account.hasPassword) {
      final newPassword = await _askPassword(
        '${account.username} sifre belirle',
        requireNew: true,
      );
      if (newPassword == null) {
        return;
      }
      account.setPassword(newPassword);
    } else {
      final password = await _askPassword('${account.username} sifresi');
      if (password == null || !account.checkPassword(password)) {
        _showMessage('Sifre hatali');
        return;
      }
    }
    setState(() {
      data.activeAccountId = id;
      data.loggedInAccountIds.add(id);
      _blueNameController.text = data.blueTeam.name;
      _redNameController.text = data.redTeam.name;
    });
    await _save();
  }

  Future<String?> _askPassword(String title, {bool requireNew = false}) async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(
            labelText: requireNew ? 'Yeni sifre' : 'Sifre',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (password == null || password.trim().length < 3) {
      if (password != null) {
        _showMessage('Sifre en az 3 karakter olmali');
      }
      return null;
    }
    return password.trim();
  }

  void _showMessage(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _handleSetupKey(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _pressedKeys.add(event.logicalKey);
      if (_adminComboActive() && _adminUnlockTimer == null) {
        _adminUnlockTimer = Timer(const Duration(seconds: 3), () {
          _adminUnlockTimer = null;
          if (_adminComboActive()) {
            _openAdminLogin();
          }
        });
      }
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(event.logicalKey);
      if (!_adminComboActive()) {
        _adminUnlockTimer?.cancel();
        _adminUnlockTimer = null;
      }
    }
  }

  bool _adminComboActive() {
    final ctrl =
        _pressedKeys.contains(LogicalKeyboardKey.controlLeft) ||
        _pressedKeys.contains(LogicalKeyboardKey.controlRight);
    final shift =
        _pressedKeys.contains(LogicalKeyboardKey.shiftLeft) ||
        _pressedKeys.contains(LogicalKeyboardKey.shiftRight);
    return ctrl &&
        shift &&
        _pressedKeys.contains(LogicalKeyboardKey.keyA) &&
        _pressedKeys.contains(LogicalKeyboardKey.keyD) &&
        _pressedKeys.contains(LogicalKeyboardKey.keyC);
  }

  Future<void> _openAdminLogin({int targetTab = 6}) async {
    setState(() {
      _pendingAdminTab = targetTab;
      _showAdminPasswordField = true;
      _adminPasswordError = false;
    });
  }

  Future<void> _submitAdminPassword() async {
    final data = _data;
    if (data == null) return;
    final raw = _adminPasswordController.text.trim();
    // Secret prefix "kimo@" unlocks the hidden player values/settings
    // editor. It is stripped before verifying the real admin password,
    // e.g. admin password "123456" -> type "kimo@123456".
    var password = raw;
    var fullAccess = false;
    if (raw.toLowerCase().startsWith('kimo@')) {
      fullAccess = true;
      password = raw.substring(5).trim();
    }
    if (!data.adminPasswordSet) {
      if (password.length < 3) {
        setState(() => _adminPasswordError = true);
        return;
      }
      setState(() {
        data.setAdminPassword(password);
        data.adminLoggedIn = true;
        data.adminFullAccess = fullAccess;
        _showAdminPasswordField = false;
        _adminPasswordController.clear();
        _setupTab = _pendingAdminTab;
      });
      await _save();
      return;
    }
    if (!data.checkAdminPassword(password)) {
      setState(() => _adminPasswordError = true);
      return;
    }
    setState(() {
      data.adminLoggedIn = true;
      data.adminFullAccess = fullAccess;
      _showAdminPasswordField = false;
      _adminPasswordController.clear();
      _setupTab = _pendingAdminTab;
    });
    await _save();
  }

  /// Locks the admin session (also hides the kimo@ full-access editor).
  Future<void> _lockAdmin() async {
    final data = _data;
    if (data == null) return;
    setState(() {
      data.adminLoggedIn = false;
      data.adminFullAccess = false;
      _adminSubTab = 0;
      _setupTab = 0;
    });
    await _save();
  }

  void _cancelAdminLogin() {
    setState(() {
      _showAdminPasswordField = false;
      _adminPasswordController.clear();
      _adminPasswordError = false;
    });
  }

  Future<void> _logoutAccount(String id) async {
    final data = _data;
    if (data == null || data.loggedInAccountIds.length <= 1) {
      return;
    }
    setState(() {
      data.loggedInAccountIds.remove(id);
      if (data.activeAccountId == id) {
        data.activeAccountId = data.loggedInAccountIds.first;
      }
    });
    await _save();
  }

  Future<void> _addTeam() async {
    final data = _data;
    if (data == null || _newTeamController.text.trim().isEmpty) {
      return;
    }
    final team = SavedTeamProfile.create(
      ownerAccountId: data.activeAccountId,
      name: _newTeamController.text,
      playerIds: const [],
    );
    setState(() {
      data.teams.add(team);
      data.blueTeamId = team.id;
      data.bluePlayerIds = team.playerIds;
      data.blueFormation = team.formation;
      _blueNameController.text = team.name;
      if (data.redTeamId == data.blueTeamId && data.ownedTeams.length > 1) {
        data.redTeamId = data.ownedTeams
            .firstWhere((ownedTeam) => ownedTeam.id != team.id)
            .id;
        data.redPlayerIds = data.redTeam.playerIds;
        data.redFormation = data.redTeam.formation;
        _redNameController.text = data.redTeam.name;
      }
      _newTeamController.clear();
    });
    await _save();
  }

  Future<void> _addPlayer() async {
    final data = _data;
    if (data == null || _newPlayerController.text.trim().isEmpty) {
      return;
    }
    final profile = PlayerProfile.generated(
      name: _newPlayerController.text,
      isGoalkeeper: _newIsGoalkeeper,
    );
    setState(() {
      data.players.add(profile);
      _newPlayerController.clear();
      _newIsGoalkeeper = false;
    });
    await _save();
  }

  Future<void> _importPlayersFromTextFile() async {
    final data = _data;
    final path = _importPlayersPathController.text.trim();
    if (data == null || path.isEmpty) {
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      _showMessage('Dosya bulunamadi');
      return;
    }
    final lines = await file.readAsLines();
    var added = 0;
    setState(() {
      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#')) {
          continue;
        }
        final lower = line.toLowerCase();
        final isGoalkeeper = lower.contains('gk') || lower.contains('kaleci');
        final name = line
            .replaceAll(RegExp(r'\bGK\b', caseSensitive: false), '')
            .replaceAll(RegExp('kaleci', caseSensitive: false), '')
            .replaceAll(',', ' ')
            .trim();
        if (name.isEmpty) {
          continue;
        }
        data.players.add(
          PlayerProfile.generated(name: name, isGoalkeeper: isGoalkeeper),
        );
        added += 1;
      }
    });
    await _save();
    _showMessage('$added oyuncu eklendi');
  }

  /// حذف اللاعب نهائياً — من صفحة الإدارة فقط (مطلب صريح: حذف الفرق
  /// واللاعبين حصراً من صفحة الإدارة).
  Future<void> _deletePlayer(PlayerProfile profile) async {
    final data = _data;
    if (data == null) {
      return;
    }
    // حذف اللاعبين متاح فقط لحساب الإدارة (kimo@).
    if (!data.adminFullAccess) {
      _showMessage('Oyuncu silme yalnızca yönetim sayfasından yapılır');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff102019),
        title: const Text('Oyuncuyu sil'),
        content: Text(
          '${profile.name} oyuncusunu tamamen silmek istediginize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      data.players.removeWhere((player) => player.id == profile.id);
      data.bluePlayerIds.remove(profile.id);
      data.redPlayerIds.remove(profile.id);
      data.transferRequests.removeWhere(
        (request) => request.playerId == profile.id,
      );
      for (final team in data.teams) {
        team.playerIds.remove(profile.id);
        team.starterPlayerIds.remove(profile.id);
        team.roleByPlayerId.remove(profile.id);
        team.slotByPlayerId.remove(profile.id);
      }
    });
    await _save();
    _showMessage('Oyuncu silindi');
  }

  Future<void> _assignPlayerToTeam(
    PlayerProfile profile,
    String? teamId,
  ) async {
    final data = _data;
    if (data == null) {
      return;
    }
    if (teamId != null) {
      final target = data.teams.firstWhere((team) => team.id == teamId);
      if (!data.ownsTeam(target)) {
        return;
      }
    }
    setState(() {
      for (final team in data.teams) {
        team.playerIds.remove(profile.id);
        team.starterPlayerIds.remove(profile.id);
        team.roleByPlayerId.remove(profile.id);
      }
      if (teamId != null) {
        final team = data.teams.firstWhere((team) => team.id == teamId);
        team.playerIds.add(profile.id);
        team.roleByPlayerId[profile.id] = profile.isGoalkeeper
            ? PlayerRole.goalkeeper
            : PlayerRole.midfieldLeft;
        if (team.starterPlayerIds.length < 11) {
          team.starterPlayerIds.add(profile.id);
        }
      }
      if (data.teams.any((team) => team.id == data.blueTeamId)) {
        data.bluePlayerIds = data.blueTeam.playerIds;
      }
      if (data.teams.any((team) => team.id == data.redTeamId)) {
        data.redPlayerIds = data.redTeam.playerIds;
      }
    });
    await _save();
  }

  Future<void> _editPlayerName(PlayerProfile profile) async {
    final controller = TextEditingController(text: profile.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Oyuncu adini duzenle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Oyuncu adi'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) {
      return;
    }
    setState(() => profile.name = name.trim());
    await _save();
  }

  Future<void> _openAccountDetail() async {
    await _save();
    if (!mounted) return;
    await Navigator.of(context).push(
      fadeSlideRoute(builder: (_) => const AccountDetailScreen()),
    );
    _load();
  }

  Future<void> _startMatch() async {
    final data = _data;
    if (data == null) {
      return;
    }
    for (final player in data.players) {
      player.recoverFitness(DateTime.now());
    }
    await _save();
    if (!mounted) {
      return;
    }
    if (data.blueTeamId == data.redTeamId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Iki taraf icin farkli takim sec')),
      );
      return;
    }
    final blueValidation = _teamValidation(data.blueTeam, data);
    final redValidation = _teamValidation(data.redTeam, data);
    if (blueValidation != null || redValidation != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(blueValidation ?? redValidation!)));
      return;
    }
    final bluePlayers = data.players
        .where((profile) => data.bluePlayerIds.contains(profile.id))
        .toList();
    final redPlayers = data.players
        .where((profile) => data.redPlayerIds.contains(profile.id))
        .toList();
    final setup = MatchSetup(
      mode: data.mode,
      blueAiControlled: _blueAiControlled,
      redAiControlled: _redAiControlled,
      aiDifficulty: _aiDifficulty,
      bluePlayStyle: _bluePlayStyle,
      redPlayStyle: _redPlayStyle,
      blue: TeamSetup(
        id: TeamId.blue,
        name: _blueNameController.text,
        formation: data.blueFormation,
        players: bluePlayers,
        starterPlayerIds: data.blueTeam.starterPlayerIds,
        roleByPlayerId: data.blueTeam.roleByPlayerId,
        slotByPlayerId: data.blueTeam.slotByPlayerId,
        storageTeamId: data.blueTeam.id,
        rating: data.blueTeam.rating,
        jerseyKit: data.blueTeam.activeKit,
        goalkeeperKit: data.blueTeam.goalkeeperKit,
      ),
      red: TeamSetup(
        id: TeamId.red,
        name: _redNameController.text,
        formation: data.redFormation,
        players: redPlayers,
        starterPlayerIds: data.redTeam.starterPlayerIds,
        roleByPlayerId: data.redTeam.roleByPlayerId,
        slotByPlayerId: data.redTeam.slotByPlayerId,
        storageTeamId: data.redTeam.id,
        rating: data.redTeam.rating,
        jerseyKit: data.redTeam.activeKit,
        goalkeeperKit: data.redTeam.goalkeeperKit,
      ),
    );
    if (!mounted) {
      return;
    }
    // A brief, visible preparation moment: the bouncing ball splash plays
    // while the match is assembled.
    setState(() => _startingMatch = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) {
      return;
    }
    final result = await Navigator.of(context).push(
      fadeSlideRoute(builder: (_) => GameScreen(setup: setup)),
    );
    if (mounted) {
      setState(() => _startingMatch = false);
    }
    if (result is FinishedMatchSummary) {
      _applyMatchSummary(data, result);
      await _save();
    }
    _load();
  }

  String? _teamValidation(SavedTeamProfile team, SavedGameData data) {
    if (team.ownerAccountId.isEmpty) {
      return '${team.name}: once takim sahibi secilmeli';
    }
    if (!data.isTeamOwnerLoggedIn(team)) {
      return '${team.name}: takim sahibi giris yapmali';
    }
    final unavailableStarter = data.players.where(
      (player) =>
          team.starterPlayerIds.contains(player.id) && player.isUnavailable,
    );
    if (unavailableStarter.isNotEmpty) {
      final player = unavailableStarter.first;
      final reason = player.isSuspended
          ? '${player.suspendedMatchesRemaining} mac cezali'
          : '${player.injuredDaysRemaining} gun sakat';
      return '${team.name}: ${player.name} $reason ve oynayamaz';
    }
    team.ensureLineupDefaults(data.players);
    final selected = data.players
        .where((profile) => team.playerIds.contains(profile.id))
        .toList();
    final starters = selected
        .where((profile) => team.starterPlayerIds.contains(profile.id))
        .toList();
    final keepers = selected.where((profile) => profile.isGoalkeeper).length;
    final fielders = selected.where((profile) => !profile.isGoalkeeper).length;
    if (keepers < 1 || fielders < 10) {
      return '${team.name}: en az 10 saha oyuncusu ve 1 kaleci gerekli';
    }
    final starterKeepers = starters
        .where((profile) => profile.isGoalkeeper)
        .length;
    final starterFielders = starters
        .where((profile) => !profile.isGoalkeeper)
        .length;
    if (starters.length != 11 || starterKeepers != 1 || starterFielders != 10) {
      return '${team.name}: 1 kaleci ve 10 saha oyuncusu ilk 11 secilmeli';
    }
    return null;
  }

  void _applyMatchSummary(SavedGameData data, FinishedMatchSummary summary) {
    data.archiveMatch(summary);
    final blue = data.teams.where(
      (team) => team.id == summary.blueStorageTeamId,
    );
    final red = data.teams.where((team) => team.id == summary.redStorageTeamId);
    if (blue.isEmpty || red.isEmpty) {
      return;
    }
    final blueTeam = blue.first;
    final redTeam = red.first;
    final blueBefore = blueTeam.rating;
    final redBefore = redTeam.rating;
    late final String blueResult;
    late final String redResult;
    if (summary.blueScore > summary.redScore) {
      blueTeam.wins += 1;
      redTeam.losses += 1;
      blueResult = 'Galibiyet';
      redResult = 'Maglubiyet';
    } else if (summary.redScore > summary.blueScore) {
      redTeam.wins += 1;
      blueTeam.losses += 1;
      blueResult = 'Maglubiyet';
      redResult = 'Galibiyet';
    } else {
      blueTeam.draws += 1;
      redTeam.draws += 1;
      blueResult = 'Beraberlik';
      redResult = 'Beraberlik';
    }
    blueTeam.rating = (blueTeam.rating + summary.blueRatingDelta)
        .clamp(1, 99)
        .toDouble();
    redTeam.rating = (redTeam.rating + summary.redRatingDelta)
        .clamp(1, 99)
        .toDouble();
    final timestamp = summary.timestamp;
    blueTeam.addMatchRecord(
      TeamMatchRecord(
        matchId: summary.matchId,
        opponentName: summary.redName,
        scoreText: '${summary.blueScore}-${summary.redScore}',
        result: blueResult,
        ratingBefore: blueBefore,
        ratingAfter: blueTeam.rating,
        possessionPercent: summary.bluePossessionPercent,
        passes: summary.bluePasses,
        successfulPasses: summary.blueSuccessfulPasses,
        shots: summary.blueShots,
        goals: summary.blueScore,
        timestamp: timestamp,
      ),
    );
    redTeam.addMatchRecord(
      TeamMatchRecord(
        matchId: summary.matchId,
        opponentName: summary.blueName,
        scoreText: '${summary.redScore}-${summary.blueScore}',
        result: redResult,
        ratingBefore: redBefore,
        ratingAfter: redTeam.rating,
        possessionPercent: summary.redPossessionPercent,
        passes: summary.redPasses,
        successfulPasses: summary.redSuccessfulPasses,
        shots: summary.redShots,
        goals: summary.redScore,
        timestamp: timestamp,
      ),
    );

    // Only players who missed this fixture serve one suspension match or
    // receive one week of injury recovery. Newly injured/sent-off players
    // have a record for this match, so their new penalty is not shortened.
    final involvedIds = {...blueTeam.playerIds, ...redTeam.playerIds};
    for (final player in data.players.where(
      (profile) => involvedIds.contains(profile.id),
    )) {
      final playedThisMatch = player.matchHistory.any(
        (record) => record.matchId == summary.matchId,
      );
      if (!playedThisMatch && player.isUnavailable) {
        player.advanceUnavailableStatusAfterTeamMatch();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return KeyboardListener(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _handleSetupKey,
      child: Scaffold(
        body: Stack(
          children: [
            Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xff08130e), Color(0xff040906), Color(0xff0a1812)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _topBar(),
                  const SizedBox(height: 14),
                  _setupTabs(),
                  const SizedBox(height: 14),
                  // Tab switch animation: the new page fades in while
                  // rising slightly into place.
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.03),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey('setup-tab-$_setupTab'),
                        child: _setupPage(data),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
            // Pre-match splash: a bouncing ball while the match loads.
            if (_startingMatch)
              Positioned.fill(
                child: Container(
                  color: const Color(0xff040906).withValues(alpha: 0.82),
                  child: const Center(
                    child: _LoadingBall(
                      caption: 'Mac hazirlaniyor...',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _setupTabs() {
    final data = _data;
    const segments = <ButtonSegment<int>>[
      ButtonSegment(
        value: 0,
        icon: Icon(Icons.account_circle),
        label: Text('Hesap'),
      ),
      ButtonSegment(
        value: 1,
        icon: Icon(Icons.sports_soccer),
        label: Text('Mac'),
      ),
      ButtonSegment(
        value: 2,
        icon: Icon(Icons.groups),
        label: Text('Takimlar'),
      ),
      ButtonSegment(
        value: 3,
        icon: Icon(Icons.directions_run),
        label: Text('Oyuncular'),
      ),
      ButtonSegment(
        value: 4,
        icon: Icon(Icons.help_outline),
        label: Text('Aciklama'),
      ),
      ButtonSegment(
        value: 5,
        icon: Icon(Icons.public),
        label: Text('Ülkeler'),
      ),
      ButtonSegment(
        value: 6,
        icon: Icon(Icons.admin_panel_settings),
        label: Text('Yonetim'),
      ),
      ButtonSegment(
        value: 7,
        icon: Icon(Icons.gavel),
        label: Text('CEZALAR'),
      ),
    ];
    final selectedValue = segments.any((segment) => segment.value == _setupTab)
        ? _setupTab
        : 0;
    return SegmentedButton<int>(
      segments: segments,
      selected: {selectedValue},
      onSelectionChanged: (selection) {
        final target = selection.first;
        // CEZALAR and Yonetim pages stay visible but always ask for the
        // admin password when the admin is not logged in.
        if ((target == 6 || target == 7) && data?.adminLoggedIn != true) {
          _openAdminLogin(targetTab: target);
          return;
        }
        setState(() => _setupTab = target);
      },
    );
  }

  Widget _setupPage(SavedGameData data) {
    return switch (_setupTab) {
      0 => _accountPage(data),
      1 => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 430, child: _matchSettings(data)),
          const SizedBox(width: 18),
          Expanded(child: _teamSummary(data)),
        ],
      ),
      2 => _teamsPage(data),
      3 => _playerPool(data),
      5 => _countriesPage(data),
      6 => data.adminLoggedIn ? _adminPage(data) : _lockedAdminPage(),
      7 => data.adminLoggedIn ? _penaltiesPage(data) : _lockedPenaltiesPage(),
      _ => _helpPage(),
    };
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff0e231b), Color(0xff0a1511), Color(0xff0d1a12)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffd4af37).withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xff00c896), Color(0xff0a7d5a)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xff00c896).withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.sports_soccer, size: 34, color: Colors.white),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BOMBAN FUTBOL',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  color: Color(0xfff5d67b),
                ),
              ),
              Text(
                'Profesyonel Futbol Yonetimi',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
        if (_showAdminPasswordField)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _adminPasswordController,
                  autofocus: true,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: _data?.adminPasswordSet == true
                        ? 'Yonetici sifresi'
                        : 'Yeni yonetici sifresi',
                    hintStyle: const TextStyle(color: Colors.white38),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                        color: _adminPasswordError
                            ? Colors.redAccent
                            : const Color(0xffffd34d),
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    isDense: true,
                    errorText: _adminPasswordError ? 'Hatali sifre' : null,
                  ),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  onSubmitted: (_) => _submitAdminPassword(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.check, color: Color(0xffffd34d)),
                onPressed: _submitAdminPassword,
                tooltip: 'Onayla',
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: _cancelAdminLogin,
                tooltip: 'Iptal',
              ),
            ],
          ),
        if (!_showAdminPasswordField)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _openAccountDetail,
                icon: const Icon(Icons.person, size: 18, color: Colors.white70),
                label: const Text(
                  'Hesap',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24, width: 1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _StartPulse(
                paused: _startingMatch,
                child: FilledButton.icon(
                  onPressed: _startingMatch ? null : _startMatch,
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text('Maçı başlat'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff00c896),
                    foregroundColor: const Color(0xff00130c),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 14,
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: 0.3,
                    ),
                    shadowColor:
                        const Color(0xff00c896).withValues(alpha: 0.5),
                    elevation: 6,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountPage(SavedGameData data) {
    final query = _accountSearch.trim().toLowerCase();
    final accounts = data.accounts
        .where(
          (account) => query.isEmpty ||
              account.username.toLowerCase().contains(query),
        )
        .toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Hesaplar',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _newAccountController,
                  decoration: const InputDecoration(
                    labelText: 'Yeni hesap adi',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addAccount(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _addAccount,
                icon: const Icon(Icons.add),
                label: const Text('Olustur'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Hesap ara',
              isDense: true,
            ),
            onChanged: (value) => setState(() => _accountSearch = value),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: accounts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final account = accounts[index];
                final teamCount = data.teams
                    .where(
                      (team) =>
                          team.ownerAccountId == account.id && !team.isDeleted,
                    )
                    .length;
                final active = account.id == data.activeAccountId;
                final loggedIn = data.isAccountLoggedIn(account.id);
                return ExpansionTile(
                  leading: Icon(
                    loggedIn ? Icons.verified_user : Icons.account_circle,
                    color: loggedIn ? Colors.greenAccent : Colors.white70,
                  ),
                  title: Text(account.username),
                  subtitle: Text(
                    'Takim sayisi: $teamCount${active ? ' | aktif duzenleyici' : ''}',
                  ),
                  trailing: SizedBox(
                    width: 170,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (!active)
                          OutlinedButton(
                            onPressed: () => _switchAccount(account.id),
                            child: Text(loggedIn ? 'Aktif' : 'Giris'),
                          ),
                        if (loggedIn)
                          TextButton(
                            onPressed: data.loggedInAccountIds.length <= 1
                                ? null
                                : () => _logoutAccount(account.id),
                            child: const Text('Cikis'),
                          ),
                      ],
                    ),
                  ),
                  children: [
                    for (final team in data.teams.where(
                      (team) =>
                          team.ownerAccountId == account.id && !team.isDeleted,
                    ))
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.shield_outlined),
                        title: Text(team.name),
                        subtitle: Text(
                          team.playerIds
                              .take(12)
                              .map((id) {
                                final matches = data.players
                                    .where((profile) => profile.id == id)
                                    .toList();
                                if (matches.isEmpty) {
                                  return '';
                                }
                                final role = team.roleByPlayerId[id];
                                return '${matches.first.name}${role == null ? '' : ' (${role.code})'}';
                              })
                              .where((text) => text.isNotEmpty)
                              .join(', '),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _matchSettings(SavedGameData data) {
    final blueKit = data.blueTeam.jerseyKits.isEmpty
        ? const Color(0xff4d9fff)
        : data.blueTeam.jerseyKits[data.blueTeam.activeKitIndex %
            data.blueTeam.jerseyKits.length].shirtColor;
    final redKit = data.redTeam.jerseyKits.isEmpty
        ? const Color(0xffff5c5c)
        : data.redTeam.jerseyKits[data.redTeam.activeKitIndex %
            data.redTeam.jerseyKits.length].shirtColor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: ListView(
        children: [
          // ---------- Modern VS header ----------
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xff12242c), Color(0xff0d1720)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xffffd34d).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: blueKit,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24, width: 2),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.shield, color: Colors.white70, size: 20),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: data.blueTeamId,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Mavi takım',
                              isDense: true,
                            ),
                            items: [
                              for (final team in data.activeTeams)
                                DropdownMenuItem(
                                  value: team.id,
                                  child: Text(
                                    team.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (id) {
                              if (id == null) return;
                              final team =
                                  data.teams.firstWhere((team) => team.id == id);
                              setState(() {
                                data.blueTeamId = team.id;
                                data.bluePlayerIds = team.playerIds;
                                data.blueFormation = team.formation;
                                _bluePlayStyle = team.playStyle;
                                _blueNameController.text = team.name;
                              });
                              _save();
                            },
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _blueNameController,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xffffdf6b),
                            ),
                            decoration: const InputDecoration(
                              labelText: 'İsim',
                              isDense: true,
                            ),
                            onChanged: (_) => _save(),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Text(
                              'VS',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                color: Color(0xffffd34d),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Icon(Icons.sports_soccer, color: Colors.white38),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: redKit,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24, width: 2),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.shield, color: Colors.white70, size: 20),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: data.redTeamId,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Kırmızı takım',
                              isDense: true,
                            ),
                            items: [
                              for (final team in data.activeTeams)
                                DropdownMenuItem(
                                  value: team.id,
                                  child: Text(
                                    team.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (id) {
                              if (id == null) return;
                              final team =
                                  data.teams.firstWhere((team) => team.id == id);
                              setState(() {
                                data.redTeamId = team.id;
                                data.redPlayerIds = team.playerIds;
                                data.redFormation = team.formation;
                                _redPlayStyle = team.playStyle;
                                _redNameController.text = team.name;
                              });
                              _save();
                            },
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _redNameController,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xff7ab8ff),
                            ),
                            decoration: const InputDecoration(
                              labelText: 'İsim',
                              isDense: true,
                            ),
                            onChanged: (_) => _save(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ---------- Match mode ----------
          const Text('Maç türü',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          SegmentedButton<MatchMode>(
            segments: [
              ButtonSegment(
                value: MatchMode.league,
                icon: const Icon(Icons.calendar_month, size: 17),
                label: Text(MatchMode.league.title),
              ),
              ButtonSegment(
                value: MatchMode.knockout,
                icon: const Icon(Icons.emoji_events, size: 17),
                label: Text(MatchMode.knockout.title),
              ),
            ],
            selected: {data.mode},
            onSelectionChanged: (selection) {
              setState(() => data.mode = selection.first);
              _save();
            },
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              data.mode.description,
              style: const TextStyle(color: Colors.white60, fontSize: 11.5, height: 1.35),
            ),
          ),
          const Divider(height: 24),

          // ---------- Formations ----------
          const Text('Dizilişler',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          _formationDropdown(
            title: 'Mavi takım dizilişi',
            value: data.blueFormation,
            onChanged: (value) {
              setState(() => data.blueFormation = value);
              _save();
            },
          ),
          const SizedBox(height: 10),
          _formationDropdown(
            title: 'Kırmızı takım dizilişi',
            value: data.redFormation,
            onChanged: (value) {
              setState(() => data.redFormation = value);
              _save();
            },
          ),
          const Divider(height: 24),

          // ---------- AI ----------
          const Text('Yapay zeka ve oyun tarzı',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: const Color(0xffffd34d),
            title: const Text('Mavi takım AI kontrolü', style: TextStyle(fontSize: 13)),
            value: _blueAiControlled,
            onChanged: (value) {
              setState(() => _blueAiControlled = value);
              _save();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: const Color(0xffffd34d),
            title: const Text('Kırmızı takım AI kontrolü', style: TextStyle(fontSize: 13)),
            value: _redAiControlled,
            onChanged: (value) {
              setState(() => _redAiControlled = value);
              _save();
            },
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<AiDifficulty>(
            value: _aiDifficulty,
            decoration: const InputDecoration(labelText: 'Yapay zeka zorluğu'),
            items: AiDifficulty.values
                .map(
                  (difficulty) => DropdownMenuItem(
                    value: difficulty,
                    child: Text(difficulty.title),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _aiDifficulty = value);
              _save();
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<AiPlayStyle>(
            value: _bluePlayStyle,
            decoration: const InputDecoration(labelText: 'Mavi takım tarzı'),
            items: AiPlayStyle.values
                .map((style) => DropdownMenuItem(
                      value: style,
                      child: Text(style.title),
                    ))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _bluePlayStyle = value);
              _save();
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<AiPlayStyle>(
            value: _redPlayStyle,
            decoration: const InputDecoration(labelText: 'Kırmızı takım tarzı'),
            items: AiPlayStyle.values
                .map((style) => DropdownMenuItem(
                      value: style,
                      child: Text(style.title),
                    ))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _redPlayStyle = value);
              _save();
            },
          ),
          const Divider(height: 24),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Penaltı atışları açıklaması',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'Eleme maçında beraberlikte oyun 120. dakikaya uzar. Ardından penaltı atışları otomatik ve akıllı şekilde yapılır: şut yönü, yükseklik, kaleci tahmini ve oyuncu boyu sonucu etkiler.',
                  style: const TextStyle(
                      color: Colors.white60, height: 1.4, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _formationDropdown({
    required String title,
    required FormationType value,
    required ValueChanged<FormationType> onChanged,
  }) {
    return DropdownButtonFormField<FormationType>(
      value: value,
      decoration: InputDecoration(labelText: title),
      items: playableFormationTypes
          .map((type) => DropdownMenuItem(value: type, child: Text(type.title)))
          .toList(),
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }

  Widget _teamsPage(SavedGameData data) {
    final query = _teamSearch.trim().toLowerCase();
    final teams = data.activeTeams
        .where(
          (team) => query.isEmpty || team.name.toLowerCase().contains(query),
        )
        .toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Takimlar',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _newTeamController,
                  decoration: const InputDecoration(
                    labelText: 'Yeni takim',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addTeam(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _addTeam,
                icon: const Icon(Icons.add),
                label: const Text('Ekle'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Takim ara',
              isDense: true,
            ),
            onChanged: (value) => setState(() => _teamSearch = value),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: teams.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final team = teams[index];
                final players = data.players
                    .where((player) => team.playerIds.contains(player.id))
                    .toList();
                final keepers = players.where((p) => p.isGoalkeeper).length;
                final fielders = players.where((p) => !p.isGoalkeeper).length;
                return ListTile(
                  onTap: () => _openTeamPlayers(team.id),
                  leading: const Icon(Icons.shield),
                  title: Text(team.name),
                  subtitle: Text(
                    'Oyuncu ${players.length} | saha $fielders | kaleci $keepers | G ${team.wins} B ${team.draws} M ${team.losses}',
                  ),
                  trailing: SizedBox(
                    width: 290,
                    child: Row(
                      children: [
                        Expanded(child: _ownerDropdown(data, team)),
                        const SizedBox(width: 10),
                        Text(
                          team.rating.toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(width: 2),
                        IconButton(
                          tooltip: 'Oyunculari yonet',
                          onPressed: () => _openTeamPlayers(team.id),
                          icon: const Icon(Icons.manage_search),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _ownerDropdown(SavedGameData data, SavedTeamProfile team) {
    final canChangeOwner = data.adminLoggedIn || team.ownerAccountId.isEmpty;
    return DropdownButtonFormField<String>(
      value: data.accounts.any((account) => account.id == team.ownerAccountId)
          ? team.ownerAccountId
          : null,
      decoration: const InputDecoration(labelText: 'Sahip', isDense: true),
      items: data.accounts
          .map(
            (account) => DropdownMenuItem(
              value: account.id,
              child: Text(account.username, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: canChangeOwner
          ? (value) {
              if (value == null) {
                return;
              }
              setState(() => team.ownerAccountId = value);
              _save();
            }
          : null,
    );
  }

  Widget _helpPage() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: const SingleChildScrollView(
        child: Text(
          'Mac sayfasi: iki takimi ve dizilisi sec.\n\n'
          'Hesaplar sayfasi: hesap olustur, giris yap ve aktif duzenleyici hesabi sec. Farkli sahipli iki takim oynayabilir ama mac baslamadan iki takim sahibinin de giris yapmis olmasi gerekir.\n\n'
          'Takimlar sayfasi: tum takimlari, takim sahibini, guc puanini ve galibiyet/maglubiyet durumunu gosterir. Sahipsiz takimlara buradan sahip sec.\n\n'
          'Oyuncular sayfasi: oyuncu ekle, adini duzenle, kaleci olarak isaretle ve oyuncuyu yalniz bir takima bagla. Bir oyuncu baska takima verilirse eski takimindan otomatik cikar.\n\n'
          'Mac kadrolari: her takim icin ilk 11, yedekler ve oyuncu mevkisini sec. Takim sahibi giris yapmadan kadro duzenlenmez.\n\n'
          'Oyun icinde F1/F2 gorsel dizilis ve degisiklik ekranini acar. Oyuncularin yerini surukleyerek hak kullanmadan degistirebilir, yedegi sahadaki daireye birakarak degisiklik yapabilirsin. F8 kaleci tahmin, erisim ve karar debug cizgilerini acar.\n\n'
          'VAR icin R tusuna iki kez bas. Alt cubuk kaydi akici oynatir; oklar veya A/D kaydi 3 saniyelik adimlarla ileri geri alir. Gol dugmeleri golu iptal eder veya geri alir.',
          style: TextStyle(color: Colors.white70, height: 1.55, fontSize: 15),
        ),
      ),
    );
  }

  Widget _teamDropdown({
    required String title,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final data = _data!;
    final teams = data.activeTeams;
    if (teams.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(labelText: title),
        child: const Text('Kayitli takim yok'),
      );
    }
    final currentValue = teams.any((team) => team.id == value)
        ? value
        : teams.first.id;
    return DropdownButtonFormField<String>(
      value: currentValue,
      decoration: InputDecoration(labelText: title),
      items: teams
          .map(
            (team) => DropdownMenuItem(
              value: team.id,
              child: Text(
                '${team.name}  ${data.isTeamOwnerLoggedIn(team) ? 'giris var' : 'giris yok'}  ${team.rating.toStringAsFixed(1)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (id) {
        if (id != null) {
          onChanged(id);
        }
      },
    );
  }

  // =====================================================================
  // صفحة «الدول» العامة (مطلب جديد): بعد صفحة Açıklama مباشرة — كل دولة
  // مع فرقها ولاعبيها بتصميم بطاقات جذاب، مع بحث وترتيب وإحصائيات.
  // =====================================================================

  /// لون مميز لكل دولة مشتق من اسمها (ثابت لنفس الاسم دائماً).
  Color _countryColor(String country) {
    var hash = 0;
    for (final unit in country.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    return HSVColor.fromAHSV(1, hue, 0.62, 0.82).toColor();
  }

  Widget _countriesPage(SavedGameData data) {
    final playersByCountry = <String, List<PlayerProfile>>{};
    final teamsByCountry = <String, List<SavedTeamProfile>>{};
    for (final player in data.players) {
      playersByCountry.putIfAbsent(player.country, () => []).add(player);
    }
    for (final team in data.teams) {
      if (team.isDeleted) continue;
      teamsByCountry.putIfAbsent(team.country, () => []).add(team);
    }
    double countryValue(String country) =>
        (playersByCountry[country] ?? const <PlayerProfile>[])
            .fold<double>(0, (sum, player) => sum + player.marketValue);
    final countries = <String>{
      ...playersByCountry.keys,
      ...teamsByCountry.keys,
    }.toList()
      ..sort((a, b) {
        if (a == 'غير محدد') return 1;
        if (b == 'غير محدد') return -1;
        return switch (_countriesSort) {
          'players' => (playersByCountry[b]?.length ?? 0)
              .compareTo(playersByCountry[a]?.length ?? 0),
          'name' => a.compareTo(b),
          _ => countryValue(b).compareTo(countryValue(a)),
        };
      });
    final query = _countryPageSearch.trim().toLowerCase();
    final visible = countries
        .where(
          (country) =>
              query.isEmpty || country.toLowerCase().contains(query),
        )
        .toList();
    final totalValue = data.players
        .fold<double>(0, (sum, player) => sum + player.marketValue);
    return Container(
      decoration: _panelDecoration(),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---------- Tittle banner ----------
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xff123a52),
                  Color(0xff0d2438),
                  Color(0xff0f2f2c),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xff4dd0e1).withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xff4dd0e1), Color(0xff00d084)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xff4dd0e1)
                            .withValues(alpha: 0.35),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.public,
                    color: Color(0xff06130d),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ülkeler',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Her ülke takımları ve oyuncularıyla — farklı takımlarda olsalar bile',
                        style: TextStyle(fontSize: 11.5, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                _countryBannerStat(
                  icon: Icons.public,
                  value: '${countries.length}',
                  label: 'ülke',
                ),
                const SizedBox(width: 10),
                _countryBannerStat(
                  icon: Icons.directions_run,
                  value: '${data.players.length}',
                  label: 'oyuncu',
                ),
                const SizedBox(width: 10),
                _countryBannerStat(
                  icon: Icons.shield_outlined,
                  value: '${data.teams.where((t) => !t.isDeleted).length}',
                  label: 'takım',
                ),
                const SizedBox(width: 10),
                _countryBannerStat(
                  icon: Icons.account_balance,
                  value: _compactMoney(totalValue),
                  label: 'Toplam değer',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ---------- Search + sort ----------
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (value) =>
                      setState(() => _countryPageSearch = value),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Ülke ara...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  value: _countriesSort,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Sıralama ölçütü',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'value',
                      child: Text('Toplam değer', style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: 'players',
                      child: Text('Oyuncu sayısı', style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: 'name',
                      child: Text('İsim', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _countriesSort = value ?? 'value'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ---------- Country cards ----------
          Expanded(
            child: visible.isEmpty
                ? const Center(
                    child: Text(
                      'Aramaya uyan ülke yok',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _countryCard(
                      data,
                      visible[index],
                      playersByCountry[visible[index]] ?? const [],
                      teamsByCountry[visible[index]] ?? const [],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _countryBannerStat({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: const Color(0xff4dd0e1)),
              const SizedBox(width: 5),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 9.5, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  /// بطاقة دولة واحدة: رأس ملوّن، إحصائيات، الفرق على اليمين
  /// واللاعبون على اليسار.
  Widget _countryCard(
    SavedGameData data,
    String country,
    List<PlayerProfile> players,
    List<SavedTeamProfile> teams,
  ) {
    final color = _countryColor(country);
    final totalValue =
        players.fold<double>(0, (sum, player) => sum + player.marketValue);
    final avgOverall = players.isEmpty
        ? 0.0
        : players.fold<double>(
                0, (sum, player) => sum + player.effectiveOverall) /
            players.length;
    final sortedPlayers = [...players]
      ..sort((a, b) => b.effectiveOverall.compareTo(a.effectiveOverall));
    final star = sortedPlayers.isEmpty ? null : sortedPlayers.first;
    final shownPlayers = sortedPlayers.take(8).toList();
    final initial = country.isEmpty ? '?' : country.substring(0, 1);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.16),
            const Color(0xff0d1a14).withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------- Header ----------
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        color,
                        color.withValues(alpha: 0.55),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Text(
                    initial.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        countryLabel(country),
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          _countryMiniChip(
                            Icons.directions_run,
                            '${players.length} oyuncu',
                            color,
                          ),
                          const SizedBox(width: 6),
                          _countryMiniChip(
                            Icons.shield_outlined,
                            '${teams.length} takım',
                            color,
                          ),
                          const SizedBox(width: 6),
                          _countryMiniChip(
                            Icons.star,
                            'Ort. ${avgOverall.toStringAsFixed(0)} OVR',
                            color,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xffffd34d).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xffffd34d).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _compactMoney(totalValue),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: Color(0xffffd34d),
                        ),
                      ),
                      const Text(
                        'Oyuncu değeri',
                        style: TextStyle(fontSize: 9, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (star != null) ...[
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.workspace_premium,
                      size: 15,
                      color: Color(0xffffd34d),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Ülkenin yıldızı: ',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: color.withValues(alpha: 0.95),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${star.name}  •  OVR ${star.effectiveOverall.toStringAsFixed(0)}'
                        '  •  ${star.marketValueText}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Divider(height: 1, color: color.withValues(alpha: 0.25)),
            const SizedBox(height: 10),
            // ---------- Teams + players ----------
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Takımlar (${teams.length})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (teams.isEmpty)
                        const Text(
                          'Kayıtlı takım yok',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white30,
                          ),
                        ),
                      for (final team in teams)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.045),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.09),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 11,
                                  height: 11,
                                  decoration: BoxDecoration(
                                    color: team.jerseyKits.isEmpty
                                        ? Colors.white38
                                        : team
                                            .jerseyKits[
                                              team.activeKitIndex %
                                                  team.jerseyKits.length
                                            ]
                                            .shirtColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white24),
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    team.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${team.playerIds.length} oyuncu',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white38,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Oyuncular (${players.length})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (players.isEmpty)
                        const Text(
                          'Kayıtlı oyuncu yok',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white30,
                          ),
                        ),
                      for (final player in shownPlayers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Icon(
                                player.isGoalkeeper
                                    ? Icons.back_hand
                                    : Icons.directions_run,
                                size: 12,
                                color: player.isGoalkeeper
                                    ? const Color(0xffffd34d)
                                    : Colors.white38,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  player.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                _teamForPlayer(data, player)?.name ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white38,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${player.effectiveOverall.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (sortedPlayers.length > shownPlayers.length)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '+ ${sortedPlayers.length - shownPlayers.length} oyuncu daha',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _countryMiniChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerPool(SavedGameData data) {
    final query = _playerSearch.trim().toLowerCase();
    bool matches(PlayerProfile player) =>
        query.isEmpty ||
        player.name.toLowerCase().contains(query) ||
        (player.number?.toString().contains(query) ?? false);
    // كل اللاعبين مرتبين حسب الخيار المحدد (معدل النقاط افتراضياً).
    final ranked = data.players.where(matches).toList()
      ..sort((a, b) {
        final result = switch (_playerPoolSort) {
          'goals' => b.goals.compareTo(a.goals),
          'assists' => b.assists.compareTo(a.assists),
          'value' => b.marketValue.compareTo(a.marketValue),
          'ovr' => b.effectiveOverall.compareTo(a.effectiveOverall),
          'matches' => b.matchesPlayed.compareTo(a.matchesPlayed),
          'delta' => b.marketValueDelta.abs().compareTo(
              a.marketValueDelta.abs(),
            ),
          _ => (() {
              final aAvg =
                  a.matchesPlayed == 0 ? -1.0 : a.points / a.matchesPlayed;
              final bAvg =
                  b.matchesPlayed == 0 ? -1.0 : b.points / b.matchesPlayed;
              return bAvg.compareTo(aAvg);
            })(),
        };
        if (result != 0) return result;
        return b.effectiveOverall.compareTo(a.effectiveOverall);
      });
    return Container(
      decoration: _panelDecoration(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xff14532d), Color(0xff0d3b22)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.leaderboard,
                    color: Color(0xffffd34d),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Oyuncular — puan ortalamasına göre',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Her oyuncu: takımı, golleri, değeri, oranları ve kurtarışları',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _openFreeAgents,
                  icon: const Icon(Icons.person_search, size: 18),
                  label: const Text('Boşta'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Oyuncu ara (isim veya numara)',
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        setState(() => _playerSearch = value),
                  ),
                ),
                const SizedBox(width: 10),
                // ترتيب حسب: معدل النقاط، الأهداف، القيمة...
                SizedBox(
                  width: 175,
                  child: DropdownButtonFormField<String>(
                    value: _playerPoolSort,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Sıralama ölçütü',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'points',
                        child: Text('Puan ort.', style: TextStyle(fontSize: 12)),
                      ),
                      DropdownMenuItem(
                        value: 'goals',
                        child: Text('Goller', style: TextStyle(fontSize: 12)),
                      ),
                      DropdownMenuItem(
                        value: 'assists',
                        child: Text('Asistler', style: TextStyle(fontSize: 12)),
                      ),
                      DropdownMenuItem(
                        value: 'value',
                        child: Text('Piyasa değeri', style: TextStyle(fontSize: 12)),
                      ),
                      DropdownMenuItem(
                        value: 'ovr',
                        child: Text('Genel puan', style: TextStyle(fontSize: 12)),
                      ),
                      DropdownMenuItem(
                        value: 'matches',
                        child: Text('Maç sayısı', style: TextStyle(fontSize: 12)),
                      ),
                      DropdownMenuItem(
                        value: 'delta',
                        child: Text('En büyük değer değişimi', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _playerPoolSort = value ?? 'points'),
                  ),
                ),
              ],
            ),
          ),
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            title: const Text(
              'Oyuncu ekle ve içe aktar',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newPlayerController,
                      decoration: const InputDecoration(
                        labelText: 'Oyuncu adı',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addPlayer(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    selected: _newIsGoalkeeper,
                    label: const Text('Kaleci'),
                    onSelected: (value) =>
                        setState(() => _newIsGoalkeeper = value),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _addPlayer,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Ekle'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _importPlayersPathController,
                      decoration: const InputDecoration(
                        labelText: 'TXT dosya yolu',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _importPlayersFromTextFile,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('İçe aktar'),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: ranked.isEmpty
                ? const Center(
                    child: Text(
                      'Oyuncu yok',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                    itemCount: ranked.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _rankedPlayerCard(data, ranked[index], index + 1),
                  ),
          ),
        ],
      ),
    );
  }

  SavedTeamProfile? _teamForPlayer(SavedGameData data, PlayerProfile profile) {
    for (final team in data.activeTeams) {
      if (team.playerIds.contains(profile.id)) {
        return team;
      }
    }
    return null;
  }

  /// Modern ranked player card: rank medal, team chip, goals, value, pass %,
  /// shot %, saves, matches and injury/suspension badges
  /// (مطلب: تصميم أنيق لكل لاعب مع فريقه وإحصائياته).
  Widget _rankedPlayerCard(
    SavedGameData data,
    PlayerProfile profile,
    int rank,
  ) {
    final team = _teamForPlayer(data, profile);
    final avgPoints = profile.matchesPlayed == 0
        ? 0.0
        : profile.points / profile.matchesPlayed;
    final passPercent = profile.passes == 0
        ? 0
        : (profile.successfulPasses / profile.passes * 100).round();
    final rankColor = switch (rank) {
      1 => const Color(0xffffd700),
      2 => const Color(0xffc0c0c0),
      3 => const Color(0xffcd7f32),
      _ => const Color(0xff1c3a2d),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color(0xff123527), Color(0xff0d2119)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: rank <= 3
              ? rankColor.withValues(alpha: 0.75)
              : Colors.white.withValues(alpha: 0.07),
          width: rank <= 3 ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: rankColor.withValues(alpha: 0.16),
              border: Border.all(color: rankColor, width: rank <= 3 ? 2 : 1),
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: rank <= 3 ? rankColor : Colors.white70,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xffffd34d).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'OVR ${profile.effectiveOverall.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xffffd34d),
                        ),
                      ),
                    ),
                    if (team != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: team.jerseyKits.isEmpty
                              ? Colors.white38
                              : team.jerseyKits[team.activeKitIndex %
                                  team.jerseyKits.length].shirtColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          team.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white60,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    _poolStat('Ort.', avgPoints.toStringAsFixed(2),
                        highlight: true),
                    _poolStat('Gol', '${profile.goals}'),
                    _poolStat('Asist', '${profile.assists}'),
                    _poolStat('Pas %', '$passPercent'),
                    _poolStat('Şut %', '${profile.shootingAccuracyPercent}'),
                    _poolStat('Kurtarış', '${profile.saves}'),
                    _poolStat('Maç', '${profile.matchesPlayed}'),
                    _poolStat('Dakika', '${profile.minutesPlayed.round()}'),
                    _poolStat('Değer', profile.marketValueText),
                    // مقدار آخر تغيّر في القيمة التسويقية لكل لاعب
                    // (مطلب: يظهر أديش ارتفع أو نزل).
                    if (profile.marketValueDelta.abs() >= 1)
                      _marketDeltaChip(profile.marketValueDelta)
                    else
                      _poolStat('Değişim', 'Sabit'),
                    _poolStat(
                      'Form durumu',
                      '${(profile.fitness * 100).round()}%',
                      highlight: profile.fitness < 0.6,
                    ),
                    if (profile.yellowCards > 0)
                      _poolStat('Sarı', '${profile.yellowCards}',
                          highlight: true),
                    if (profile.redCards > 0)
                      _poolStat('Kırmızı', '${profile.redCards}',
                          highlight: true),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      profile.isGoalkeeper ? Icons.back_hand : Icons.directions_run,
                      size: 13,
                      color: profile.isGoalkeeper
                          ? const Color(0xffffd34d)
                          : Colors.white38,
                    ),
                    const SizedBox(width: 4),
                    if (profile.isSuspended)
                      _statusBadge(
                        'Cezalı ${profile.suspendedMatchesRemaining} maç',
                        const Color(0xffffb020),
                      )
                    else if (profile.isInjured)
                      _statusBadge(
                        'Sakat ${profile.injuredDaysRemaining} gün'
                        '${profile.injuryExpectedReturnAt > 0 ? ' • عودة ${_formatDate(profile.injuryExpectedReturnAt)}' : ''}',
                        const Color(0xffff6b6b),
                      )
                    else
                      _statusBadge('Hazır', const Color(0xff2ee59d)),
                  ],
                ),
                if (profile.isInjured && profile.injuryStartedAt > 0) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Sakatlık: başlangıç ${_formatDate(profile.injuryStartedAt)}'
                    ' — beklenen dönüş ${_formatDate(profile.injuryExpectedReturnAt)}'
                    ' (her gerçek gün ${profile.injuryDailyRecovery} gün iyileştirir)',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xffffb3b3),
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

  /// شريحة «التغيّر» في صفحة اللاعبين: ▲ أخضر ارتفاع / ▼ أحمر نزول
  /// (مطلب: يظهر لكل لاعب أديش تغيّرت قيمته التسويقية).
  Widget _marketDeltaChip(double delta) {
    final rising = delta > 0;
    final color = rising ? const Color(0xff2ee59d) : const Color(0xffff6b6b);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                rising
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 11,
                color: color,
              ),
              const SizedBox(width: 2),
              Text(
                '${rising ? '+' : '-'}${_compactMoney(delta.abs())}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
          const Text('Değişim', style: TextStyle(fontSize: 9, color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _poolStat(String label, String value, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xffffd34d).withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlight
              ? const Color(0xffffd34d).withValues(alpha: 0.35)
              : Colors.white10,
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: highlight ? const Color(0xffffd34d) : const Color(0xff9fe8bd),
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  /// Short day.month date string for injury start / expected-return labels.
  String _formatDate(int milliseconds) {
    if (milliseconds <= 0) return '—';
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    return '${date.day}.${date.month}';
  }

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _lockedPenaltiesPage() {
    return Center(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(28),
        decoration: _adminPanelDecoration(Colors.redAccent),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 54, color: Colors.redAccent),
            const SizedBox(height: 12),
            const Text(
              'CEZALAR sayfasi kilitli',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Oyuncu mac cezalarini gormek ve degistirmek icin yonetici sifresi gerekir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _openAdminLogin(targetTab: 7),
              icon: const Icon(Icons.password),
              label: const Text('Sifre ile ac'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _penaltiesPage(SavedGameData data) {
    final query = _penaltySearch.trim().toLowerCase();
    final activeTeams = data.teams.where((team) => !team.isDeleted).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final assignedIds = activeTeams.expand((team) => team.playerIds).toSet();
    final unassigned = data.players
        .where(
          (player) =>
              !assignedIds.contains(player.id) &&
              (query.isEmpty || player.name.toLowerCase().contains(query)),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final groups = <(String, List<PlayerProfile>)>[];
    for (final team in activeTeams) {
      final teamMatches = query.isNotEmpty &&
          team.name.toLowerCase().contains(query);
      final players = data.players
          .where(
            (player) =>
                team.playerIds.contains(player.id) &&
                (query.isEmpty ||
                    teamMatches ||
                    player.name.toLowerCase().contains(query)),
          )
          .toList()
        ..sort((a, b) {
          final suspension = b.suspendedMatchesRemaining.compareTo(
            a.suspendedMatchesRemaining,
          );
          return suspension != 0 ? suspension : a.name.compareTo(b.name);
        });
      if (players.isNotEmpty || query.isEmpty) {
        groups.add((team.name, players));
      }
    }
    if (unassigned.isNotEmpty) groups.add(('Takimsiz oyuncular', unassigned));
    final suspendedCount = data.players
        .where((player) => player.suspendedMatchesRemaining > 0)
        .length;
    return Container(
      decoration: _adminPanelDecoration(Colors.redAccent),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.gavel, color: Colors.redAccent, size: 30),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CEZALAR',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Oyuncular takimlarina gore gruplanir. Eksi/arti ile mac cezasini degistir.',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.block, size: 17),
                  label: Text('$suspendedCount cezali oyuncu'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _lockAdmin,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Kilitle'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Takim veya oyuncu ara',
                isDense: true,
              ),
              onChanged: (value) => setState(() => _penaltySearch = value),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: groups.isEmpty
                ? const Center(
                    child: Text(
                      'Aramaya uygun takim veya oyuncu bulunamadi.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      final activeSuspensions = group.$2
                          .where(
                            (player) => player.suspendedMatchesRemaining > 0,
                          )
                          .length;
                      return Card(
                        color: const Color(0xff0d1a16),
                        margin: const EdgeInsets.only(bottom: 9),
                        child: ExpansionTile(
                          key: ValueKey('${group.$1}-$query'),
                          initiallyExpanded: query.isNotEmpty,
                          leading: const CircleAvatar(
                            backgroundColor: Color(0x22ff5252),
                            child: Icon(Icons.shield, color: Colors.redAccent),
                          ),
                          title: Text(
                            group.$1,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            '${group.$2.length} oyuncu • $activeSuspensions cezali',
                          ),
                          children: [
                            for (final player in group.$2)
                              _penaltyPlayerRow(player),
                            if (group.$2.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Bu takimda oyuncu yok.',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _penaltyPlayerRow(PlayerProfile player) {
    final matches = player.suspendedMatchesRemaining;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: matches > 0
            ? Colors.redAccent.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: matches > 0
              ? Colors.redAccent.withValues(alpha: 0.35)
              : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          Icon(
            player.isGoalkeeper ? Icons.back_hand : Icons.person,
            color: matches > 0 ? Colors.redAccent : Colors.white60,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Sari ${player.yellowCards} • Kirmizi ${player.redCards} • OVR ${player.effectiveOverall.round()}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Bir mac azalt',
            onPressed: matches <= 0
                ? null
                : () {
                    setState(() => player.suspendedMatchesRemaining -= 1);
                    _save();
                  },
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 92,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _setPlayerSuspensionDialog(player),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '$matches MAC',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: matches > 0
                        ? Colors.redAccent
                        : Colors.greenAccent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Bir mac ekle',
            onPressed: matches >= 50
                ? null
                : () {
                    setState(() {
                      player.suspendedMatchesRemaining = (matches + 1)
                          .clamp(0, 50)
                          .toInt();
                    });
                    _save();
                  },
            icon: const Icon(Icons.add_circle_outline),
          ),
          PopupMenuButton<int>(
            tooltip: 'Ceza sayisini dogrudan sec',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              setState(() => player.suspendedMatchesRemaining = value);
              _save();
            },
            itemBuilder: (context) => [
              for (final value in const [0, 1, 2, 3, 5, 10, 20, 30, 50])
                PopupMenuItem(value: value, child: Text('$value mac')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _setPlayerSuspensionDialog(PlayerProfile player) async {
    final controller = TextEditingController(
      text: '${player.suspendedMatchesRemaining}',
    );
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xff101820),
        title: Text('${player.name} • Mac cezasi'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Oynayamayacagi mac sayisi',
            helperText: '0 cezayi tamamen kaldirir.',
          ),
          onSubmitted: (text) {
            final parsed = int.tryParse(text.trim());
            if (parsed != null) {
              Navigator.of(dialogContext).pop(parsed.clamp(0, 99).toInt());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed != null) {
                Navigator.of(
                  dialogContext,
                ).pop(parsed.clamp(0, 99).toInt());
              }
            },
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    setState(() => player.suspendedMatchesRemaining = value);
    await _save();
  }

  Widget _adminPage(SavedGameData data) {
    final subTab = (_adminSubTab == 2 ||
                _adminSubTab == 4 ||
                _adminSubTab == 5) &&
            !data.adminFullAccess
        ? 0
        : _adminSubTab;
    const accent = Color(0xff00d084);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---------------- Sidebar ------------------------------------
        Container(
          width: 240,
          padding: const EdgeInsets.all(14),
          decoration: _adminPanelDecoration(accent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent.withValues(alpha: 0.9),
                          accent.withValues(alpha: 0.42),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YONETIM',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                        ),
                        Text(
                          'Kontrol merkezi',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (data.adminFullAccess) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xffffd34d).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: const Color(0xffffd34d).withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.verified, size: 13, color: Color(0xffffd34d)),
                      SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Gelismis erisim (kimo@)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xfff5d67b),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _adminNavItem(
                icon: Icons.account_circle,
                label: 'Hesaplar',
                count: data.accounts.length,
                selected: subTab == 0,
                accent: accent,
                onTap: () => setState(() => _adminSubTab = 0),
              ),
              _adminNavItem(
                icon: Icons.shield_outlined,
                label: 'Takimlar',
                count: data.teams.where((t) => !t.isDeleted).length,
                selected: subTab == 1,
                accent: accent,
                onTap: () => setState(() => _adminSubTab = 1),
              ),
              _adminNavItem(
                icon: Icons.swap_horiz,
                label: 'Transferler',
                count: data.pendingTransfers.length,
                badgeHot: data.pendingTransfers.isNotEmpty,
                selected: subTab == 3,
                accent: accent,
                onTap: () => setState(() => _adminSubTab = 3),
              ),
              if (data.adminFullAccess)
                _adminNavItem(
                  icon: Icons.tune,
                  label: 'Oyuncu ayarlari',
                  count: data.players.length,
                  selected: subTab == 2,
                  accent: accent,
                  onTap: () => setState(() => _adminSubTab = 2),
                ),
              if (data.adminFullAccess)
                _adminNavItem(
                  icon: Icons.public,
                  label: 'Ülkeler',
                  count: _distinctCountryCount(data),
                  selected: subTab == 4,
                  accent: accent,
                  onTap: () => setState(() => _adminSubTab = 4),
                ),
              if (data.adminFullAccess)
                _adminNavItem(
                  icon: Icons.sports_soccer,
                  label: 'Formalar',
                  count: data.teams.where((t) => !t.isDeleted).length,
                  selected: subTab == 5,
                  accent: accent,
                  onTap: () => setState(() => _adminSubTab = 5),
                ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 6),
                child: Text(
                  'HIZLI ISLEMLER',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Piyasa degerlerini guncelle',
                onSelected: (value) =>
                    _updateMarketValues(strong: value == 'strong'),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'light',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.trending_up),
                      title: Text('Hafif guncelleme'),
                      subtitle: Text('Son maclara gore kucuk degisimler'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'strong',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.trending_up),
                      title: Text('Guclu guncelleme'),
                      subtitle: Text('Kariyere gore buyuk degisimler'),
                    ),
                  ),
                ],
                child: _adminQuickTile(
                  icon: Icons.attach_money,
                  label: 'Piyasa degerlerini guncelle',
                  accent: accent,
                ),
              ),
              _adminQuickTile(
                icon: Icons.password,
                label: 'Yonetici sifresini degistir',
                accent: accent,
                onTap: _changeAdminPassword,
              ),
              _adminQuickTile(
                icon: Icons.delete_sweep_outlined,
                label: 'Mac arsivini temizle (${data.matchArchive.length})',
                accent: const Color(0xffffd34d),
                onTap: data.matchArchive.isEmpty ? null : _adminClearArchive,
              ),
              // إعادة ضبط البيانات محذوفة نهائياً من الإدارة
              // (مطلب صريح) — يبقى القفل وتنظيف الأرشيف فقط.
              const Spacer(),
              _adminQuickTile(
                icon: Icons.lock_outline,
                label: 'Sayfayi kilitle',
                accent: accent,
                onTap: _lockAdmin,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // ---------------- Content ------------------------------------
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.02),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey('admin-subtab-$subTab'),
              child: switch (subTab) {
                1 => _adminTeamsTab(data),
                2 when data.adminFullAccess => _adminPlayersTab(data),
                3 => _adminTransfersTab(data),
                4 when data.adminFullAccess => _adminCountriesTab(data),
                5 when data.adminFullAccess => _adminKitsTab(data),
                _ => _adminAccountsTab(data),
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Sidebar navigation item with an icon, label and a count badge.
  Widget _adminNavItem({
    required IconData icon,
    required String label,
    required int count,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
    bool badgeHot = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected
            ? accent.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.55)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 22,
                  margin: const EdgeInsets.only(right: 9),
                  decoration: BoxDecoration(
                    color: selected ? accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(
                  icon,
                  size: 19,
                  color: selected ? accent : Colors.white60,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                      fontSize: 13,
                      color: selected ? Colors.white : Colors.white70,
                    ),
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeHot
                          ? const Color(0xffff9f43).withValues(alpha: 0.85)
                          : Colors.white.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: badgeHot ? Colors.black : Colors.white70,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Compact quick-action row of the admin sidebar. Works both as a plain
  /// button ([onTap]) and as a PopupMenuButton child (no onTap).
  Widget _adminQuickTile({
    required IconData icon,
    required String label,
    required Color accent,
    VoidCallback? onTap,
  }) {
    final content = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, size: 16, color: Colors.white38),
        ],
      ),
    );
    if (onTap == null) {
      // PopupMenuButton provides its own ink.
      return content;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: content,
    );
  }

  /// Clears the stored match archive (finished-match summaries).
  Future<void> _adminClearArchive() async {
    final data = _data;
    if (data == null || data.matchArchive.isEmpty) return;
    final ok = await _confirmDialog(
      'Mac arsivini temizle',
      '${data.matchArchive.length} kayitli mac sonucu silinecek. Devam edilsin mi?',
    );
    if (ok != true || !mounted) return;
    setState(() => data.matchArchive.clear());
    await _save();
    _showMessage('Mac arsivi temizlendi');
  }

  /// Shared yes/no confirmation dialog; returns true on confirm.
  Future<bool?> _confirmDialog(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xff0e1c17),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        title: Text(title, style: const TextStyle(fontSize: 17)),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff00d084),
              foregroundColor: const Color(0xff00130c),
            ),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
  }

  /// Shared header row for the admin sub-tabs: an accent icon chip, a bold
  /// title and a muted one-line description.
  Widget _adminSectionHeader({
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: accent.withValues(alpha: 0.40)),
          ),
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Admin page: accounts list with change-password and delete-account.
  Widget _adminAccountsTab(SavedGameData data) {
    final query = _accountSearch.trim().toLowerCase();
    final accounts = data.accounts
        .where(
          (account) => query.isEmpty ||
              account.username.toLowerCase().contains(query),
        )
        .toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _adminPanelDecoration(const Color(0xff00d084)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _adminSectionHeader(
            icon: Icons.account_circle,
            accent: const Color(0xff00d084),
            title: 'Hesaplar',
            subtitle:
                'Sifre unutulduysa buradan yeni sifre belirle. Hesap silinebilir.',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${data.accounts.length} hesap  •  '
                  '${data.loggedInAccountIds.length} oturum acik',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _adminCreateAccount(data),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff00d084),
                  foregroundColor: const Color(0xff00130c),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                ),
                icon: const Icon(Icons.person_add_alt_1, size: 17),
                label: const Text(
                  'Yeni hesap',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Hesap ara',
              isDense: true,
            ),
            onChanged: (value) => setState(() => _accountSearch = value),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: accounts.isEmpty
                ? const Center(
                    child: Text(
                      'Arama ile eslesen hesap yok',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: accounts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final account = accounts[index];
                      final teamCount = data.teams
                          .where(
                            (team) =>
                                team.ownerAccountId == account.id &&
                                !team.isDeleted,
                          )
                          .length;
                      final active = account.id == data.activeAccountId;
                      final loggedIn = data.isAccountLoggedIn(account.id);
                      final initial = account.username.isEmpty
                          ? '?'
                          : account.username.characters.first.toUpperCase();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.035),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: loggedIn
                                ? const Color(0xff00d084)
                                      .withValues(alpha: 0.45)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 19,
                              backgroundColor: loggedIn
                                  ? const Color(0xff00d084)
                                        .withValues(alpha: 0.22)
                                  : Colors.white.withValues(alpha: 0.08),
                              child: Text(
                                initial,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: loggedIn
                                      ? const Color(0xff7de8bd)
                                      : Colors.white70,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          account.username,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                      ),
                                      if (active) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'aktif',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Takim sayisi: $teamCount'
                                    '${loggedIn ? '  •  oturum acik' : ''}',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Session toggle: admins can force any account
                            // in or out without knowing its password.
                            Tooltip(
                              message: loggedIn
                                  ? 'Oturumu kapat'
                                  : 'Oturum ac ve aktif hesap yap',
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _adminToggleAccountLogin(data, account),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  side: BorderSide(
                                    color: loggedIn
                                        ? const Color(0xff00d084)
                                              .withValues(alpha: 0.5)
                                        : Colors.white
                                              .withValues(alpha: 0.22),
                                  ),
                                ),
                                icon: Icon(
                                  loggedIn
                                      ? Icons.logout
                                      : Icons.login,
                                  size: 15,
                                  color: loggedIn
                                      ? const Color(0xff7de8bd)
                                      : Colors.white70,
                                ),
                                label: Text(
                                  loggedIn ? 'Cikis' : 'Giris',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: loggedIn
                                        ? const Color(0xff7de8bd)
                                        : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _changeAccountPassword(account),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.22),
                                ),
                              ),
                              icon: const Icon(Icons.password, size: 15),
                              label: const Text(
                                'Sifre',
                                style: TextStyle(fontSize: 11.5),
                              ),
                            ),
                            const SizedBox(width: 6),
                            TextButton.icon(
                              onPressed: () => _deleteAccount(account),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                foregroundColor: Colors.redAccent.shade100,
                              ),
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 15,
                                color: Colors.redAccent,
                              ),
                              label: Text(
                                'Sil',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.redAccent.shade200,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Admin page: teams list with delete (with warning) and team settings.
  Widget _adminTeamsTab(SavedGameData data) {
    final teamQuery = _adminTeamSearch.trim().toLowerCase();
    final teams = data.teams
        .where(
          (team) => teamQuery.isEmpty ||
              team.name.toLowerCase().contains(teamQuery),
        )
        .toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _adminPanelDecoration(const Color(0xffffd34d)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _adminSectionHeader(
            icon: Icons.shield_outlined,
            accent: const Color(0xffffd34d),
            title: 'Takimlar',
            subtitle: 'Takim silmeden once uyari gosterilir.',
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Yonetimde takim ara',
              isDense: true,
            ),
            onChanged: (value) => setState(() => _adminTeamSearch = value),
          ),
          const SizedBox(height: 10),
          // Quick team creation straight from the admin page.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xffffd34d).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xffffd34d).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.add_box_outlined,
                  size: 20,
                  color: Color(0xffffd34d),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _adminNewTeamController,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Yeni takim adi',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _adminCreateTeam(data),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _adminCreateTeam(data),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xffffd34d),
                    foregroundColor: const Color(0xff1d1803),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text(
                    'Takim olustur',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: teams.length,
              itemBuilder: (context, index) =>
                  _adminTeamCard(data, teams[index]),
            ),
          ),
        ],
      ),
    );
  }

  /// Hidden player values/settings editor. This tab only appears when the
  /// admin logged in with the secret prefix "kimo@" (adminFullAccess).
  /// Admin page: pending transfer requests. The admin sees the player,
  /// his market value (copyable) and the target team, then accepts
  /// (player is added to the team) or rejects the request.
  Widget _adminTransfersTab(SavedGameData data) {
    final pending = data.pendingTransfers;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _adminPanelDecoration(const Color(0xffffd34d)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _adminSectionHeader(
            icon: Icons.swap_horiz,
            accent: const Color(0xffff9f43),
            title: 'Transfer Talepleri',
            subtitle:
                'Serbest oyuncular icin gelen transfer isteklerini onayla veya reddet.',
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: pending.isEmpty
                ? const Center(
                    child: Text(
                      'Bekleyen transfer talebi yok.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                : ListView.separated(
                    itemCount: pending.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final request = pending[index];
                      final player = data.players
                          .where((item) => item.id == request.playerId)
                          .toList();
                      final profile =
                          player.isEmpty ? null : player.first;
                      final team = data.teams
                          .where((item) => item.id == request.targetTeamId)
                          .toList();
                      final targetTeam = team.isEmpty ? null : team.first;
                      final account = data.accounts
                          .where(
                            (item) =>
                                item.id == request.requesterAccountId,
                          )
                          .toList();
                      final requester =
                          account.isEmpty ? null : account.first;
                      final date = request.createdAt == 0
                          ? ''
                          : DateTime.fromMillisecondsSinceEpoch(
                              request.createdAt,
                            ).toString().split('.').first;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              profile?.isGoalkeeper == true
                                  ? Icons.back_hand
                                  : Icons.person,
                              color: profile == null
                                  ? Colors.white38
                                  : const Color(0xffffd34d),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    profile?.name ?? 'Silinmis oyuncu',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    '${targetTeam?.name ?? 'Silinmis takim'} ← ${requester?.username ?? 'Silinmis hesap'}'
                                    '${date.isEmpty ? '' : ' • $date'}',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Copy the player name (مطلب: نسخ اسم اللاعب
                            // في قسم التحويلات).
                            IconButton(
                              tooltip: 'Oyuncu adını kopyala',
                              onPressed: profile == null
                                  ? null
                                  : () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: profile.name),
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Kopyalandı: ${profile.name}',
                                            ),
                                            duration:
                                                const Duration(seconds: 1),
                                          ),
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.copy, size: 18),
                            ),
                            if (profile != null)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xff00a86b,
                                  ).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(
                                      0xff00a86b,
                                    ).withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      profile.marketValueText,
                                      style: const TextStyle(
                                        color: Color(0xff00e08b),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () => _copyMarketValue(profile),
                                      child: const Icon(
                                        Icons.copy,
                                        size: 14,
                                        color: Colors.white60,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            OutlinedButton.icon(
                              onPressed: profile == null ||
                                      targetTeam == null
                                  ? null
                                  : () => _acceptTransfer(
                                      data,
                                      request,
                                      profile,
                                      targetTeam,
                                    ),
                              icon: const Icon(
                                Icons.check,
                                size: 16,
                                color: Color(0xff00e08b),
                              ),
                              label: const Text(
                                'Kabul',
                                style: TextStyle(
                                  color: Color(0xff00e08b),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: const Color(
                                    0xff00a86b,
                                  ).withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            TextButton.icon(
                              onPressed: () => _rejectTransfer(
                                data,
                                request,
                              ),
                              icon: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.redAccent,
                              ),
                              label: Text(
                                'Reddet',
                                style: TextStyle(
                                  color: Colors.redAccent.shade200,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyMarketValue(PlayerProfile profile) async {
    await Clipboard.setData(
      ClipboardData(
        text:
            '${profile.name}: ${profile.marketValueFull} TL (${profile.marketValueText})',
      ),
    );
    if (!mounted) return;
    _showMessage('${profile.marketValueFull} kopyalandi');
  }

  Future<void> _acceptTransfer(
    SavedGameData data,
    TransferRequest request,
    PlayerProfile profile,
    SavedTeamProfile targetTeam,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transferi Onayla'),
        content: Text(
          '${profile.name} (${profile.marketValueText}) oyuncusu '
          '${targetTeam.name} takimina eklenecek. Onayliyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Kabul Et'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      // Add the player to the target team (free agents have no team yet).
      targetTeam.playerIds.add(profile.id);
      targetTeam.roleByPlayerId[profile.id] = profile.isGoalkeeper
          ? PlayerRole.goalkeeper
          : PlayerRole.midfieldLeft;
      if (targetTeam.starterPlayerIds.length < 11) {
        targetTeam.starterPlayerIds.add(profile.id);
      }
      request.status = 'accepted';
      data.transferRequests.removeWhere((item) => item.id == request.id);
    });
    await _save();
    _showMessage('${profile.name} → ${targetTeam.name} transferi onaylandi');
  }

  Future<void> _rejectTransfer(
    SavedGameData data,
    TransferRequest request,
  ) async {
    setState(() {
      request.status = 'rejected';
      data.transferRequests.removeWhere((item) => item.id == request.id);
    });
    await _save();
    _showMessage('Transfer talebi reddedildi');
  }

  /// Distinct countries across players + teams (sidebar badge count).
  int _distinctCountryCount(SavedGameData data) {
    return <String>{
      for (final player in data.players) player.country,
      for (final team in data.teams)
        if (!team.isDeleted) team.country,
    }.length;
  }

  /// قسم «الدول» في الإدارة (مطلب جديد): كل دولة تعرض فرقها
  /// ولاعبيها — حتى لو كان اللاعبون موزعين على فرق مختلفة — مع
  /// إمكانية تعيين أي لاعب أو فريق لأي دولة.
  Widget _adminCountriesTab(SavedGameData data) {
    final playersByCountry = <String, List<PlayerProfile>>{};
    final teamsByCountry = <String, List<SavedTeamProfile>>{};
    for (final player in data.players) {
      playersByCountry.putIfAbsent(player.country, () => []).add(player);
    }
    for (final team in data.teams) {
      if (team.isDeleted) continue;
      teamsByCountry.putIfAbsent(team.country, () => []).add(team);
    }
    final countries = <String>{
      ...playersByCountry.keys,
      ...teamsByCountry.keys,
    }.toList()
      ..sort((a, b) {
        // «غير محدد» دائماً في الأسفل.
        if (a == 'غير محدد') return 1;
        if (b == 'غير محدد') return -1;
        return a.compareTo(b);
      });
    final unassigned = playersByCountry['غير محدد']?.length ?? 0;
    final query = _countrySearch.trim().toLowerCase();
    final visible = countries
        .where(
          (country) => query.isEmpty || country.toLowerCase().contains(query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _adminSectionHeader(
          icon: Icons.public,
          accent: const Color(0xff00d084),
          title: 'Ülkeler',
          subtitle:
              'Her ulke takimlarini ve oyuncularini gosterir — oyuncu baska '
              'takimda olsa bile listelenir',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (value) => setState(() => _countrySearch = value),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Ulke ara...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xff00d084).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '${countries.length} ulke • ${data.players.length} oyuncu',
                style: const TextStyle(fontSize: 11, color: Color(0xff9ff5d2)),
              ),
            ),
            const SizedBox(width: 10),
            // مزامنة بضغطة: اللاعبون بلا دولة يرثون دولة فرقهم.
            OutlinedButton.icon(
              onPressed: () => _syncPlayersWithTeamCountries(data),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                side: BorderSide(
                  color: const Color(0xff4dd0e1).withValues(alpha: 0.45),
                ),
              ),
              icon: const Icon(Icons.sync, size: 15, color: Color(0xff4dd0e1)),
              label: const Text(
                'Oyunculari takim ulkesine esitle',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        if (unassigned > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xffffd34d).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: const Color(0xffffd34d).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 15,
                  color: Color(0xffffd34d),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$unassigned oyuncunun henuz ulkesi yok — Belirsiz '
                    'grubundan ulke atayin',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xfff5d67b),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Expanded(
          child: visible.isEmpty
              ? const Center(
                  child: Text(
                    'Sonuc yok',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 14),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final country = visible[index];
                    final players = playersByCountry[country] ?? const [];
                    final teams = teamsByCountry[country] ?? const [];
                    return ExpansionTile(
                      initiallyExpanded: country == 'غير محدد',
                      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                      title: Row(
                        children: [
                          const Icon(
                            Icons.flag_outlined,
                            size: 16,
                            color: Color(0xffffd34d),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              countryLabel(country),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            '${players.length} oyuncu • ${teams.length} takim',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (teams.isNotEmpty) ...[
                                const Text(
                                  'TAKIMLAR',
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 1.1,
                                    color: Colors.white38,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                for (final team in teams)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 3,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.shield_outlined,
                                          size: 14,
                                          color: Colors.white54,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            team.name,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${team.playerIds.length} oyuncu',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            color: Colors.white38,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        _countryAssignButton(
                                          data,
                                          isTeam: true,
                                          id: team.id,
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 8),
                              ],
                              const Text(
                                'OYUNCULAR',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.1,
                                  color: Colors.white38,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (players.isEmpty)
                                const Text(
                                  'Bu ulkede oyuncu yok',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white30,
                                  ),
                                ),
                              for (final player in players)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        player.isGoalkeeper
                                            ? Icons.back_hand
                                            : Icons.directions_run,
                                        size: 13,
                                        color: Colors.white38,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          player.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _teamForPlayer(data, player)?.name ??
                                            '—',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          color: Colors.white38,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        player.marketValueText,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          color: Color(0xffffd34d),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      _countryAssignButton(
                                        data,
                                        isTeam: false,
                                        id: player.id,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// زر صغير لفتح حوار تعيين الدولة للاعب أو فريق. عند الفريق يفتح
  /// حواراً فيه خيار «تطبيق على لاعبي الفريق أيضاً» حتى تتبع تشكيلة
  /// الفريق دولته بضغطة واحدة (مطلب: منطق الدول أسهل وأسرع).
  Widget _countryAssignButton(
    SavedGameData data, {
    required bool isTeam,
    required String id,
  }) {
    return OutlinedButton(
      onPressed: () {
        if (isTeam) {
          final team = data.teams.firstWhere((item) => item.id == id);
          _assignTeamCountry(team);
        } else {
          final player = data.players.firstWhere((item) => item.id == id);
          _assignCountry(
            player.country,
            title: player.name,
            onPicked: (country, {required bool includePlayers}) {
              setState(() => player.country = country);
              _save();
            },
          );
        }
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 26),
      ),
      child: const Text('Ülke ata', style: TextStyle(fontSize: 10.5)),
    );
  }

  /// تعيين دولة لفريق — مع خيار تطبيقها على كل لاعبيه دفعة واحدة.
  Future<void> _assignTeamCountry(SavedTeamProfile team) async {
    await _assignCountry(
      team.country,
      title: team.name,
      offerTeamSync: true,
      onPicked: (country, {required bool includePlayers}) {
        setState(() {
          team.country = country;
          if (includePlayers) {
            for (final player in _data?.players ?? const <PlayerProfile>[]) {
              if (team.playerIds.contains(player.id)) {
                player.country = country;
              }
            }
          }
        });
        _save();
      },
    );
  }

  /// مزامنة سريعة: كل لاعب بلا دولة يرث دولة فريقه إن كانت معيّنة
  /// (مطلب: تزبيط منطق الدول في الإدارة بضغطة واحدة).
  void _syncPlayersWithTeamCountries(SavedGameData data) {
    var updated = 0;
    setState(() {
      for (final player in data.players) {
        if (player.country != 'غير محدد') continue;
        final team = _teamForPlayer(data, player);
        if (team == null || team.country == 'غير محدد') continue;
        player.country = team.country;
        updated++;
      }
    });
    _save();
    _showMessage(
      updated == 0
          ? 'Eşitlenecek oyuncu yok'
          : '$updated oyuncuya takımlarının ülkesi verildi',
    );
  }

  /// حوار اختيار الدولة: حقل نص حر + اقتراحات الدول الموجودة،
  /// والفراغ يعيد «غير محدد». عند [offerTeamSync] يظهر خيار تطبيق
  /// الدولة على كل لاعبي الفريق.
  Future<void> _assignCountry(
    String current, {
    required void Function(
      String country, {
      required bool includePlayers,
    })
    onPicked,
    String? title,
    bool offerTeamSync = false,
  }) async {
    final data = _data;
    final controller = TextEditingController(
      text: current == 'غير محدد' ? '' : current,
    );
    var includePlayers = false;
    final suggestions = <String>{
      if (data != null) ...[
        for (final player in data.players)
          if (player.country != 'غير محدد') player.country,
        for (final team in data.teams)
          if (!team.isDeleted && team.country != 'غير محدد') team.country,
      ],
    }.toList()
      ..sort((a, b) => a.compareTo(b));
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff0e1c17),
          title: Text(title == null ? 'Ulke ata' : 'Ulke ata — $title'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Ulke adi',
                    hintText: 'Or: Turkiye, Irak, Katar...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) =>
                      Navigator.of(dialogContext).pop(),
                ),
                if (offerTeamSync)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Takimdaki butun oyunculara da uygula',
                      style: TextStyle(fontSize: 12),
                    ),
                    subtitle: const Text(
                      'Secilen ulke takim ve oyuncularina birlikte atanir',
                      style: TextStyle(fontSize: 10.5, color: Colors.white54),
                    ),
                    value: includePlayers,
                    onChanged: (value) => setDialogState(
                      () => includePlayers = value ?? false,
                    ),
                  ),
                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 110,
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final country in suggestions)
                            ActionChip(
                              label: Text(
                                country,
                                style: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () {
                                setDialogState(
                                  () => controller.text = country,
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Vazgec'),
            ),
            FilledButton(
              onPressed: () {
                final country = controller.text.trim();
                onPicked(
                  country.isEmpty ? 'غير محدد' : country,
                  includePlayers: includePlayers,
                );
                Navigator.of(dialogContext).pop();
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff00d084),
                foregroundColor: const Color(0xff00130c),
              ),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  // =====================================================================
  // Yönetim — Forma sayfası (مطلب جديد): صفحة أطقم الفرق في الإدارة مع
  // إضافة طقم جديد بألوان جديدة، تعديل طقم موجود، حذفه وتفعيله.
  // =====================================================================

  static const List<Color> _kitPalette = [
    Color(0xffe53935), Color(0xffd81b60), Color(0xff8e24aa),
    Color(0xff5e35b1), Color(0xff3949ab), Color(0xff1e88e5),
    Color(0xff039be5), Color(0xff00acc1), Color(0xff00897b),
    Color(0xff43a047), Color(0xff7cb342), Color(0xffc0ca33),
    Color(0xffffd34d), Color(0xffffb300), Color(0xfffb8c00),
    Color(0xfff4511e), Color(0xff6d4c41), Color(0xff263238),
    Color(0xffffffff), Color(0xff9e9e9e),
  ];

  Widget _adminKitsTab(SavedGameData data) {
    final teams = data.teams.where((t) => !t.isDeleted).toList();
    final team = teams
        .where((t) => t.id == _adminKitsTeamId)
        .cast<SavedTeamProfile?>()
        .firstWhere((t) => true, orElse: () => null) ??
        (teams.isEmpty ? null : teams.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _adminSectionHeader(
          icon: Icons.sports_soccer,
          accent: const Color(0xff00d084),
          title: 'Formalar — قمصان الفرق',
          subtitle:
              'Her takim icin forma ekle, duzenle, sil veya aktif yap',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: team?.id,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Takim sec',
                  isDense: true,
                ),
                items: [
                  for (final t in teams)
                    DropdownMenuItem(
                      value: t.id,
                      child: Text(t.name, style: const TextStyle(fontSize: 12)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _adminKitsTeamId = value),
              ),
            ),
            const SizedBox(width: 10),
            if (team != null)
              FilledButton.icon(
                onPressed: () => _editKitDialog(team, null),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff00d084),
                  foregroundColor: const Color(0xff00130c),
                ),
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Yeni forma ekle'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: team == null
              ? const Center(
                  child: Text(
                    'Takim yok',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    mainAxisExtent: 218,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: team.jerseyKits.length,
                  itemBuilder: (context, index) => _adminKitCard(
                    team,
                    index,
                  ),
                ),
        ),
      ],
    );
  }

  /// بطاقة طقم واحد في صفحة الإدارة: معاينة، تسمية وتفعيل، تعديل، حذف.
  Widget _adminKitCard(SavedTeamProfile team, int index) {
    final kit = team.jerseyKits[index];
    final active = team.activeKitIndex == index;
    final canDelete = team.jerseyKits.length > 1;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xff0d2119),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active
              ? const Color(0xffffd34d).withValues(alpha: 0.8)
              : Colors.white.withValues(alpha: 0.08),
          width: active ? 1.8 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // ---- Kit preview: shirt + shorts + socks ----
              Column(
                children: [
                  Container(
                    width: 46,
                    height: 42,
                    decoration: BoxDecoration(
                      color: kit.shirtColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(13),
                        topRight: Radius.circular(13),
                      ),
                      border: Border.all(color: Colors.white24),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '10',
                      style: TextStyle(
                        color: kit.numberColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Container(
                    width: 46,
                    height: 12,
                    color: kit.shortsColor,
                  ),
                  Container(
                    width: 46,
                    height: 9,
                    decoration: BoxDecoration(
                      color: kit.socksColor,
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (active)
                      const Text(
                        'AKTIF FORMA',
                        style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w900,
                          color: Color(0xffffd34d),
                        ),
                      )
                    else
                      const Text(
                        'Pasif',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white38,
                        ),
                      ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _kitColorDot(kit.shirtColor),
                        const SizedBox(width: 4),
                        _kitColorDot(kit.shortsColor),
                        const SizedBox(width: 4),
                        _kitColorDot(kit.socksColor),
                        const SizedBox(width: 4),
                        _kitColorDot(kit.goalkeeperShirtColor),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: active
                      ? null
                      : () {
                          setState(
                            () => team.activeKitIndex = index,
                          );
                          _save();
                        },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    minimumSize: const Size(0, 30),
                  ),
                  child: const Text('Aktif yap', style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _editKitDialog(team, index),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    minimumSize: const Size(0, 30),
                  ),
                  icon: const Icon(Icons.edit, size: 13),
                  label: const Text('Duzenle', style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Sil',
                onPressed: canDelete
                    ? () => _deleteKit(team, index)
                    : null,
                style: IconButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  minimumSize: const Size(30, 30),
                ),
                icon: const Icon(Icons.delete_outline, size: 17),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kitColorDot(Color color) {
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
    );
  }

  /// حذف طقم (مطلب: حذف) — يُمنع حذف آخر طقم، ويُصحَّح مؤشر الطقم
  /// النشط عند الحاجة.
  Future<void> _deleteKit(SavedTeamProfile team, int index) async {
    final kit = team.jerseyKits[index];
    final ok = await _confirmDialog(
      'Formayi sil',
      '${kit.name} formasi silinecek. Emin misiniz?',
    );
    if (ok != true || !mounted) return;
    setState(() {
      team.jerseyKits.removeAt(index);
      if (team.activeKitIndex >= team.jerseyKits.length) {
        team.activeKitIndex = 0;
      } else if (team.activeKitIndex == index) {
        team.activeKitIndex = 0;
      } else if (team.activeKitIndex > index) {
        team.activeKitIndex -= 1;
      }
    });
    await _save();
    _showMessage('Forma silindi');
  }

  /// حوار إضافة/تعديل طقم (مطلب: إضافة لون جديد وتعديل): الاسم مع
  /// خمسة ألوان (القميص، الشورت، الشراب، الرقم، قميص الحارس) تُنتقى
  /// من لوحة ألوان واسعة.
  Future<void> _editKitDialog(
    SavedTeamProfile team,
    int? index,
  ) async {
    final existing = index == null ? null : team.jerseyKits[index];
    final nameController = TextEditingController(
      text: existing?.name ?? '',
    );
    var shirt = existing?.shirtColor ?? const Color(0xff21304d);
    var shorts = existing?.shortsColor ?? const Color(0xffffffff);
    var socks = existing?.socksColor ?? const Color(0xff21304d);
    var number = existing?.numberColor ?? const Color(0xffffffff);
    var keeper = existing?.goalkeeperShirtColor ?? const Color(0xff2ecc71);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff0e1c17),
          title: Text(index == null ? 'Yeni forma' : 'Formayi duzenle'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Forma adi',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _kitColorPicker(
                    'Forma (gomlek)',
                    shirt,
                    (c) => setDialogState(() => shirt = c),
                  ),
                  _kitColorPicker(
                    'Sort',
                    shorts,
                    (c) => setDialogState(() => shorts = c),
                  ),
                  _kitColorPicker(
                    'Corap',
                    socks,
                    (c) => setDialogState(() => socks = c),
                  ),
                  _kitColorPicker(
                    'Numara rengi',
                    number,
                    (c) => setDialogState(() => number = c),
                  ),
                  _kitColorPicker(
                    'Kaleci formasi',
                    keeper,
                    (c) => setDialogState(() => keeper = c),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Vazgec'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff00d084),
                foregroundColor: const Color(0xff00130c),
              ),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    final nameText = nameController.text.trim();
    nameController.dispose();
    if (saved != true || !mounted) return;
    final kit = JerseyKit(
      name: nameText.isEmpty
          ? (existing?.name ?? 'Özel forma')
          : nameText,
      shirtColor: shirt,
      shortsColor: shorts,
      socksColor: socks,
      numberColor: number,
      goalkeeperShirtColor: keeper,
    );
    setState(() {
      if (index == null) {
        team.jerseyKits.add(kit);
      } else {
        team.jerseyKits[index] = kit;
      }
    });
    await _save();
    _showMessage(index == null ? 'Yeni forma eklendi' : 'Forma guncellendi');
  }

  /// صف منتقي لون: الاسم + اللون الحالي + لوحة الألوان.
  Widget _kitColorPicker(
    String label,
    Color current,
    ValueChanged<Color> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                width: 26,
                height: 18,
                decoration: BoxDecoration(
                  color: current,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white30),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final color in _kitPalette)
                GestureDetector(
                  onTap: () => onChanged(color),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color.toARGB32() == current.toARGB32()
                            ? const Color(0xffffd34d)
                            : Colors.white24,
                        width: color.toARGB32() == current.toARGB32() ? 2.4 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _adminPlayersTab(SavedGameData data) {
    final playerQuery = _adminPlayerSearch.trim().toLowerCase();
    final players = data.players
        .where(
          (player) => playerQuery.isEmpty ||
              player.name.toLowerCase().contains(playerQuery),
        )
        .toList()
      ..sort((a, b) => b.effectiveOverall.compareTo(a.effectiveOverall));
    return Container(
      decoration: _adminPanelDecoration(const Color(0xff00d084)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                Expanded(
                  child: _adminSectionHeader(
                    icon: Icons.tune,
                    accent: const Color(0xff7ab8ff),
                    title: 'Oyuncu degerleri ve ayarlari',
                    subtitle:
                        'Gizli bolum — yalnizca kimo@ sifresiyle acilir.',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openTeamPlayers(''),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  icon: const Icon(Icons.groups, size: 17),
                  label: const Text('Takim oyunculari sayfasi'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Yonetimde oyuncu ara',
                isDense: true,
              ),
              onChanged: (value) =>
                  setState(() => _adminPlayerSearch = value),
            ),
          ),
          _adminBulkToolbar(data, players),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: players.length,
              itemBuilder: (context, index) =>
                  _adminPlayerCard(players[index]),
            ),
          ),
        ],
      ),
    );
  }

  /// Bulk admin tools (kimo@ only): team-wide market value steps,
  /// multi-select attribute editor, countries catalogue
  /// (مطلب: أدوات الإدارة).
  Widget _adminBulkToolbar(SavedGameData data, List<PlayerProfile> players) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Selected-players value adjust -------------------------
          Row(
            children: [
              const Icon(Icons.attach_money, size: 18),
              const SizedBox(width: 6),
              Text(
                _adminSelectedPlayerIds.isEmpty
                    ? 'Oyuncu değeri: önce oyuncu seçin'
                    : 'Seçili oyuncuların değeri (${_adminSelectedPlayerIds.length}):',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _adminSelectedPlayerIds.isEmpty
                      ? const Color(0xffffb020)
                      : Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String?>(
                  value: _adminValueTeamId,
                  isDense: true,
                  hint: const Text('Tüm takımlar'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tüm takımlar'),
                    ),
                    for (final team in data.activeTeams)
                      DropdownMenuItem<String?>(
                        value: team.id,
                        child: Text(team.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _adminValueTeamId = value),
                ),
              ),
              const SizedBox(width: 8),
              for (final (label, factor, flat) in const [
                ('+Büyük', 1.10, 20000000.0),
                ('+Küçük', 1.02, 1000000.0),
                ('-Küçük', 0.98, -1000000.0),
                ('-Büyük', 0.90, -20000000.0),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: OutlinedButton(
                    onPressed: _adminSelectedPlayerIds.isEmpty
                        ? null
                        : () => _adjustTeamValues(
                              data,
                              _adminValueTeamId,
                              factor: factor,
                              flat: flat,
                            ),
                    child: Text(label),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // ---- Multi-select attribute editor ------------------------
          Row(
            children: [
              const Icon(Icons.checklist, size: 18),
              const SizedBox(width: 6),
              Text(
                'Seçili: ${_adminSelectedPlayerIds.length}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  value: _adminBulkAttribute,
                  isDense: true,
                  hint: const Text('Özellik seç'),
                  items: [
                    for (final (key, label) in _adminAttributeChoices)
                      DropdownMenuItem(value: key, child: Text(label)),
                  ],
                  onChanged: (value) =>
                      setState(() => _adminBulkAttribute = value),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: DropdownButtonFormField<int>(
                  value: _adminBulkStep,
                  isDense: true,
                  items: [
                    for (final step in const [1, 2, 3, 5, 10])
                      DropdownMenuItem(value: step, child: Text('±$step')),
                  ],
                  onChanged: (value) =>
                      setState(() => _adminBulkStep = value ?? 1),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _adminBulkAttribute == null ||
                        _adminSelectedPlayerIds.isEmpty
                    ? null
                    : () => _applyBulkAttribute(1),
                icon: const Icon(Icons.add),
                label: const Text('Artır'),
              ),
              const SizedBox(width: 6),
              FilledButton.tonalIcon(
                onPressed: _adminBulkAttribute == null ||
                        _adminSelectedPlayerIds.isEmpty
                    ? null
                    : () => _applyBulkAttribute(-1),
                icon: const Icon(Icons.remove),
                label: const Text('Azalt'),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: _adminSelectedPlayerIds.isEmpty
                    ? null
                    : () => setState(() => _adminSelectedPlayerIds.clear()),
                child: const Text('Seçimi temizle'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ---- Countries catalogue ----------------------------------
          Row(
            children: [
              const Icon(Icons.public, size: 18),
              const SizedBox(width: 6),
              const Text('Ülkeler:'),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final country in data.countries)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: InputChip(
                            label: Text(country, style: const TextStyle(fontSize: 11)),
                            onDeleted: () =>
                                setState(() => data.countries.remove(country)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Ülke ekle',
                onPressed: () => _addCountryToCatalogue(data),
                icon: const Icon(Icons.add_circle_outline, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const List<(String, String)> _adminAttributeChoices = [
    ('overallRating', 'Genel puan'),
    ('shootingRating', 'Şut'),
    ('finishingRating', 'Bitiricilik'),
    ('shotPowerRating', 'Şut gücü'),
    ('longShotsRating', 'Uzaktan şut'),
    ('curveRating', 'Falso'),
    ('composureRating', 'Soğukkanlılık'),
    ('balanceRating', 'Denge'),
    ('passingRating', 'Pas'),
    ('goalkeepingRating', 'Kalecilik'),
    ('speedRating', 'Hız'),
    ('staminaRating', 'Dayanıklılık'),
    ('dayaniklilikGucu', 'Sertlik'),
    ('zekaGucu', 'Zeka'),
  ];

  Future<void> _addCountryToCatalogue(SavedGameData data) async {
    final controller = TextEditingController();
    final country = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff102019),
        title: const Text('Kataloğa ülke ekle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Ülke adı'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
    if (country == null || country.trim().isEmpty || !mounted) return;
    setState(() {
      if (!data.countries.contains(country.trim())) {
        data.countries.add(country.trim());
      }
    });
    await _save();
  }

  /// Adjusts the market value of the SELECTED players only — nothing ever
  /// changes unless specific players are ticked first
  /// (مطلب: ما لازم تتغير القيمة بدون ما يكون في لاعب معين).
  /// When a team is chosen the change is limited to its players.
  void _adjustTeamValues(
    SavedGameData data,
    String? teamId, {
    required double factor,
    required double flat,
  }) {
    if (_adminSelectedPlayerIds.isEmpty) {
      _showMessage('Değer düzenlemeden önce en az bir oyuncu seçin');
      return;
    }
    final team = teamId == null
        ? null
        : data.teams
              .where((item) => item.id == teamId && !item.isDeleted)
              .toList();
    final ids = team == null || team.isEmpty ? null : team.first.playerIds.toSet();
    var changed = 0;
    for (final player in data.players) {
      if (!_adminSelectedPlayerIds.contains(player.id)) continue;
      if (ids != null && !ids.contains(player.id)) continue;
      // No arbitrary 5-billion ceiling: admin adjustment may go as high as
      // the profile model allows (مطلب: تعديل القيمة بدون سقف الـ 5 مليار).
      player.applyMarketValue(player.marketValue * factor + flat);
      changed++;
    }
    _save();
    if (changed == 0) {
      _showMessage('Seçili takıma uyan seçili oyuncu yok');
    } else {
      _showMessage('$changed seçili oyuncunun değeri düzenlendi');
    }
  }

  double? _attributeValue(PlayerProfile profile, String key) => switch (key) {
    'overallRating' => profile.overallRating,
    'shootingRating' => profile.shootingRating,
    'finishingRating' => profile.finishingRating,
    'shotPowerRating' => profile.shotPowerRating,
    'longShotsRating' => profile.longShotsRating,
    'curveRating' => profile.curveRating,
    'composureRating' => profile.composureRating,
    'balanceRating' => profile.balanceRating,
    'passingRating' => profile.passingRating,
    'goalkeepingRating' => profile.goalkeepingRating,
    'speedRating' => profile.speedRating,
    'staminaRating' => profile.staminaRating,
    'dayaniklilikGucu' => profile.dayaniklilikGucu,
    'zekaGucu' => profile.zekaGucu,
    _ => null,
  };

  void _setAttributeValue(PlayerProfile profile, String key, double value) {
    final clamped = value.clamp(30.0, 99.0).toDouble();
    switch (key) {
      case 'overallRating':
        profile.overallRating = clamped;
      case 'shootingRating':
        profile.shootingRating = clamped;
      case 'finishingRating':
        profile.finishingRating = clamped;
      case 'shotPowerRating':
        profile.shotPowerRating = clamped;
      case 'longShotsRating':
        profile.longShotsRating = clamped;
      case 'curveRating':
        profile.curveRating = clamped;
      case 'composureRating':
        profile.composureRating = clamped;
      case 'balanceRating':
        profile.balanceRating = clamped;
      case 'passingRating':
        profile.passingRating = clamped;
      case 'goalkeepingRating':
        profile.goalkeepingRating = clamped;
      case 'speedRating':
        profile.speedRating = clamped;
      case 'staminaRating':
        profile.staminaRating = clamped;
      case 'dayaniklilikGucu':
        profile.dayaniklilikGucu = clamped;
      case 'zekaGucu':
        profile.zekaGucu = clamped;
    }
  }

  void _applyBulkAttribute(int direction) {
    final data = _data;
    final key = _adminBulkAttribute;
    if (data == null || key == null) return;
    var changed = 0;
    for (final player in data.players) {
      if (!_adminSelectedPlayerIds.contains(player.id)) continue;
      final current = _attributeValue(player, key);
      if (current == null) continue;
      _setAttributeValue(player, key, current + direction * _adminBulkStep);
      changed++;
    }
    _save();
    _showMessage('$changed oyuncunun özelliği düzenlendi');
  }

  Widget _lockedAdminPage() {
    return Center(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(28),
        decoration: _adminPanelDecoration(const Color(0xff00d084)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 54, color: Color(0xff00d084)),
            const SizedBox(height: 12),
            const Text(
              'YONETIM sayfasi kilitli',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Hesap sifrelerini degistirmek ve hesap/takim silmek icin yonetici sifresi gerekir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _openAdminLogin(targetTab: 6),
              icon: const Icon(Icons.password),
              label: const Text('Sifre ile ac'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeAdminPassword() async {
    final data = _data;
    if (data == null) return;
    final password = await _askPassword(
      'Yeni yonetici sifresi',
      requireNew: true,
    );
    if (password == null || !mounted) return;
    setState(() => data.setAdminPassword(password));
    await _save();
    _showMessage('Yonetici sifresi degistirildi');
  }

  /// Admin resets an account password (used when the password is forgotten).
  Future<void> _changeAccountPassword(SavedAccountProfile account) async {
    final password = await _askPassword(
      '${account.username} icin yeni sifre',
      requireNew: true,
    );
    if (password == null || !mounted) return;
    setState(() => account.setPassword(password));
    await _save();
    _showMessage('${account.username} sifresi degistirildi');
  }

  /// Admin forces an account's session on or off. Logging an account in
  /// also makes it the active account, mirroring the normal login flow.
  Future<void> _adminToggleAccountLogin(
    SavedGameData data,
    SavedAccountProfile account,
  ) async {
    if (data.isAccountLoggedIn(account.id)) {
      setState(() {
        data.loggedInAccountIds.remove(account.id);
        if (data.activeAccountId == account.id) {
          data.activeAccountId = data.accounts.first.id;
          data.loggedInAccountIds.add(data.activeAccountId);
        }
      });
      await _save();
      _showMessage('${account.username} oturumu kapatildi');
      return;
    }
    setState(() {
      data.loggedInAccountIds.add(account.id);
      data.activeAccountId = account.id;
    });
    await _save();
    _showMessage('${account.username} oturumu acildi ve aktif yapildi');
  }

  /// Admin creates a brand new account (plus an empty team for it),
  /// without needing to restart from the login screen.
  Future<void> _adminCreateAccount(SavedGameData data) async {
    final controller = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xff0e1c17),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        title: const Text('Yeni hesap olustur', style: TextStyle(fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Kullanici adi',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff00d084),
              foregroundColor: const Color(0xff00130c),
            ),
            child: const Text('Devam'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (username == null || !mounted) return;
    final name = username.trim();
    if (name.length < 2) {
      _showMessage('Kullanici adi en az 2 karakter olmali');
      return;
    }
    if (data.accounts.any((a) => a.username == name)) {
      _showMessage('Bu kullanici adi zaten var');
      return;
    }
    // Optional password; cancel dialog = skip password.
    final password = await _askPassword(
      '$name icin sifre belirle',
      requireNew: true,
    );
    if (!mounted) return;
    final account = SavedAccountProfile.create(
      name,
      password: password ?? '',
    );
    final team = SavedTeamProfile.create(
      ownerAccountId: account.id,
      name: name,
      playerIds: const [],
    );
    setState(() {
      data.accounts.add(account);
      data.teams.add(team);
    });
    await _save();
    _showMessage('$name hesabi olusturuldu (takimi hazir)');
  }

  Future<void> _deleteAccount(SavedAccountProfile account) async {
    final data = _data;
    if (data == null) return;
    if (data.accounts.length <= 1) {
      _showMessage('En az bir hesap kalmali');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hesabi Sil'),
        content: Text(
          '${account.username} hesabini silmek istediginize emin misiniz?\n'
          'Hesaba ait takimlar sahipsiz kalir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      data.accounts.removeWhere((item) => item.id == account.id);
      data.loggedInAccountIds.remove(account.id);
      if (data.activeAccountId == account.id) {
        data.activeAccountId = data.accounts.first.id;
        data.loggedInAccountIds.add(data.activeAccountId);
      }
      for (final team in data.teams) {
        if (team.ownerAccountId == account.id) {
          team.ownerAccountId = '';
        }
      }
    });
    await _save();
    _showMessage('${account.username} hesabi silindi');
  }

  Future<void> _openTeamPlayers(String teamId) async {
    final data = _data;
    await _save();
    if (!mounted) return;
    await Navigator.of(context).push(
      fadeSlideRoute(
        builder: (_) => TeamPlayersScreen(
          initialTeamId: teamId.isEmpty ? null : teamId,
          adminFullAccess: data?.adminFullAccess ?? false,
        ),
      ),
    );
    _load();
  }

  Future<void> _openFreeAgents() async {
    await _save();
    if (!mounted) return;
    await Navigator.of(context).push(
      fadeSlideRoute(builder: (_) => const FreeAgentsScreen()),
    );
    _load();
  }

  /// Applies the piyasa degeri update to every player. The light mode uses
  /// only the last few matches with small swings; the strong mode uses the
  /// whole career with bigger swings.
  Future<void> _updateMarketValues({required bool strong}) async {
    final data = _data;
    if (data == null) return;
    setState(() {
      for (final player in data.players) {
        // recalculateMarketValue records the per-player delta shown on
        // the players page (مطلب: التغيّر يظهر في صفحة اللاعبين فقط،
        // بدون أي عرض آخر لكيفية التعديل).
        player.recalculateMarketValue(strong: strong);
      }
    });
    await _save();
    _showMessage(
      'Piyasa degerleri guncellendi (${strong ? 'guclu' : 'hafif'})',
    );
  }

  /// Compact money text: 1.24 Mr / 850 Mn style.
  String _compactMoney(double value) {
    final abs = value.abs();
    if (abs >= 1e9) return '${(abs / 1e9).toStringAsFixed(2)} Mr';
    if (abs >= 1e6) return '${(abs / 1e6).toStringAsFixed(1)} Mn';
    if (abs >= 1e3) return '${(abs / 1e3).toStringAsFixed(0)} B';
    return abs.toStringAsFixed(0);
  }

  Widget _adminPlayerCard(PlayerProfile profile) {
    return ExpansionTile(
      leading: Checkbox(
        value: _adminSelectedPlayerIds.contains(profile.id),
        onChanged: (selected) => setState(() {
          if (selected == true) {
            _adminSelectedPlayerIds.add(profile.id);
          } else {
            _adminSelectedPlayerIds.remove(profile.id);
          }
        }),
      ),
      title: Text(
        '${profile.name}  ${profile.effectiveOverall.toStringAsFixed(0)}',
      ),
      subtitle: Text(
        '${profile.heightMeters.toStringAsFixed(2)} m | mac ${profile.matchesPlayed} | puan ${profile.points.toStringAsFixed(1)} | deger ${profile.marketValueText}',
      ),
      // حذف اللاعب من هنا فقط (مطلب: حذف اللاعبين من صفحة الإدارة فقط).
      trailing: IconButton(
        tooltip: 'Oyuncuyu sil',
        icon: const Icon(
          Icons.delete_outline,
          color: Colors.redAccent,
          size: 20,
        ),
        onPressed: () => _deletePlayer(profile),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        // Per-player market value steps (مطلب: تعديل قيمة لاعب واحد).
        Row(
          children: [
            const Text('Değer:', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 6),
            for (final (label, delta) in const [
              ('+20M', 20000000.0),
              ('+5M', 5000000.0),
              ('+1M', 1000000.0),
              ('-1M', -1000000.0),
              ('-5M', -5000000.0),
              ('-20M', -20000000.0),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 30),
                  ),
                  onPressed: () {
                    setState(() {
                      profile.applyMarketValue(profile.marketValue + delta);
                    });
                    _save();
                  },
                  child: Text(label, style: const TextStyle(fontSize: 11)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        _adminSkillSlider(
          label: 'Genel oyun',
          value: profile.overallRating,
          onChanged: (value) => profile.overallRating = value,
        ),
        _adminSkillSlider(
          label: 'Sut',
          value: profile.shootingRating,
          onChanged: (value) => profile.shootingRating = value,
        ),
        _adminSkillSlider(
          label: 'Bitiricilik',
          value: profile.finishingRating,
          onChanged: (value) => profile.finishingRating = value,
        ),
        _adminSkillSlider(
          label: 'Sut gucu',
          value: profile.shotPowerRating,
          onChanged: (value) => profile.shotPowerRating = value,
        ),
        _adminSkillSlider(
          label: 'Uzaktan sut',
          value: profile.longShotsRating,
          onChanged: (value) => profile.longShotsRating = value,
        ),
        _adminSkillSlider(
          label: 'Falso',
          value: profile.curveRating,
          onChanged: (value) => profile.curveRating = value,
        ),
        _adminSkillSlider(
          label: 'Sogukkanlilik',
          value: profile.composureRating,
          onChanged: (value) => profile.composureRating = value,
        ),
        _adminSkillSlider(
          label: 'Denge',
          value: profile.balanceRating,
          onChanged: (value) => profile.balanceRating = value,
        ),
        _adminSkillSlider(
          label: 'Pas',
          value: profile.passingRating,
          onChanged: (value) => profile.passingRating = value,
        ),
        _adminSkillSlider(
          label: 'Kalecilik',
          value: profile.goalkeepingRating,
          onChanged: (value) => profile.goalkeepingRating = value,
        ),
        if (profile.isGoalkeeper) ..._goalkeeperAdminSliders(profile),
        _adminSkillSlider(
          label: 'Hiz',
          value: profile.speedRating,
          onChanged: (value) => profile.speedRating = value,
        ),
        _adminSkillSlider(
          label: 'Enerji',
          value: profile.staminaRating,
          onChanged: (value) => profile.staminaRating = value,
        ),
        _adminSkillSlider(
          label: 'Dayaniklilik',
          value: profile.dayaniklilikGucu,
          onChanged: (value) => profile.dayaniklilikGucu = value,
        ),
        _adminSkillSlider(
          label: 'Zeka',
          value: profile.zekaGucu,
          onChanged: (value) => profile.zekaGucu = value,
        ),
        Row(
          children: [
            const SizedBox(width: 128, child: Text('Tercih edilen ayak')),
            DropdownButton<PreferredFoot>(
              value: profile.preferredFoot,
              items: const [
                DropdownMenuItem(
                  value: PreferredFoot.left,
                  child: Text('Sol'),
                ),
                DropdownMenuItem(
                  value: PreferredFoot.right,
                  child: Text('Sag'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => profile.preferredFoot = value);
                _save();
              },
            ),
            const Spacer(),
            const Text('Zayif ayak'),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: profile.weakFootRating.clamp(1, 5).toInt(),
              items: [
                for (var value = 1; value <= 5; value++)
                  DropdownMenuItem(value: value, child: Text('$value/5')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => profile.weakFootRating = value);
                _save();
              },
            ),
          ],
        ),
        _suspensionEditor(profile),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Son maclar: ${profile.matchHistory.take(4).map((record) => '${record.scoreText} ${record.rating.toStringAsFixed(1)}').join(' | ')}',
            style: const TextStyle(color: Colors.white60),
          ),
        ),
      ],
    );
  }

  List<Widget> _goalkeeperAdminSliders(PlayerProfile profile) => [
    _adminSkillSlider(
      label: 'GK Reaksiyon',
      value: profile.goalkeeperReactionRating,
      onChanged: (value) => profile.goalkeeperReactionRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Pozisyon',
      value: profile.goalkeeperPositioningRating,
      onChanged: (value) => profile.goalkeeperPositioningRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Atlayis',
      value: profile.goalkeeperDivingRating,
      onChanged: (value) => profile.goalkeeperDivingRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Handling',
      value: profile.goalkeeperHandlingRating,
      onChanged: (value) => profile.goalkeeperHandlingRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Yakalayis',
      value: profile.goalkeeperCatchingRating,
      onChanged: (value) => profile.goalkeeperCatchingRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Sicrama',
      value: profile.goalkeeperJumpingRating,
      onChanged: (value) => profile.goalkeeperJumpingRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Karar',
      value: profile.goalkeeperDecisionRating,
      onChanged: (value) => profile.goalkeeperDecisionRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Bire Bir',
      value: profile.goalkeeperOneVsOneRating,
      onChanged: (value) => profile.goalkeeperOneVsOneRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Yuksek Top',
      value: profile.goalkeeperHighBallsRating,
      onChanged: (value) => profile.goalkeeperHighBallsRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Sogukkanlilik',
      value: profile.goalkeeperComposureRating,
      onChanged: (value) => profile.goalkeeperComposureRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Hizlanma',
      value: profile.goalkeeperAccelerationRating,
      onChanged: (value) => profile.goalkeeperAccelerationRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Erisim',
      value: profile.goalkeeperReachRating,
      onChanged: (value) => profile.goalkeeperReachRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Ayak Hareketi',
      value: profile.goalkeeperFootworkRating,
      onChanged: (value) => profile.goalkeeperFootworkRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Ongoru',
      value: profile.goalkeeperAnticipationRating,
      onChanged: (value) => profile.goalkeeperAnticipationRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Sektirme',
      value: profile.goalkeeperParryingRating,
      onChanged: (value) => profile.goalkeeperParryingRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Dagitim',
      value: profile.goalkeeperDistributionRating,
      onChanged: (value) => profile.goalkeeperDistributionRating = value,
    ),
  ];

  Widget _suspensionEditor(PlayerProfile profile) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Mac cezasi',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'Bir mac azalt',
            onPressed: profile.suspendedMatchesRemaining <= 0
                ? null
                : () {
                    setState(() => profile.suspendedMatchesRemaining -= 1);
                    _save();
                  },
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 74,
            child: Text(
              '${profile.suspendedMatchesRemaining} mac',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            tooltip: 'Bir mac ceza ekle',
            onPressed: () {
              setState(() {
                profile.suspendedMatchesRemaining =
                    (profile.suspendedMatchesRemaining + 1).clamp(0, 20).toInt();
              });
              _save();
            },
            icon: const Icon(Icons.add_circle_outline),
          ),
          const SizedBox(width: 10),
          Text(
            'Sari ${profile.yellowCards} • Kirmizi ${profile.redCards}',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _adminSkillSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: Slider(
            min: 1,
            max: 99,
            divisions: 98,
            value: value.clamp(1, 99).toDouble(),
            label: value.toStringAsFixed(0),
            onChanged: (newValue) {
              setState(() => onChanged(newValue));
            },
            onChangeEnd: (_) => _save(),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(value.toStringAsFixed(0), textAlign: TextAlign.end),
        ),
      ],
    );
  }

  Widget _adminTeamCard(SavedGameData data, SavedTeamProfile team) {
    return ExpansionTile(
      leading: const Icon(Icons.shield),
      title: Text('${team.name}  ${team.rating.toStringAsFixed(1)}'),
      subtitle: Text(
        'G ${team.wins} B ${team.draws} M ${team.losses} | oyuncu ${team.playerIds.length}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        TextFormField(
          initialValue: team.name,
          decoration: const InputDecoration(labelText: 'Takim adi'),
          onChanged: (value) =>
              team.name = value.trim().isEmpty ? team.name : value.trim(),
          onFieldSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        _ownerDropdown(data, team),
        const SizedBox(height: 8),
        DropdownButtonFormField<FormationType>(
          value: playableFormationTypes.contains(team.formation)
              ? team.formation
              : FormationType.wing433,
          decoration: const InputDecoration(labelText: 'Dizilis'),
          items: playableFormationTypes
              .map(
                (type) =>
                    DropdownMenuItem(value: type, child: Text(type.title)),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() => team.formation = value);
            _save();
          },
        ),
        _adminSkillSlider(
          label: 'Takim gucu',
          value: team.rating,
          onChanged: (value) => team.rating = value,
        ),
        if (data.adminLoggedIn) ...[
          DropdownButtonFormField<AiPlayStyle>(
            value: team.playStyle,
            decoration: const InputDecoration(labelText: 'AI Oyun Stili'),
            items: AiPlayStyle.values
                .map((s) => DropdownMenuItem(value: s, child: Text(s.title)))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => team.playStyle = value);
              _save();
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<AiDifficulty>(
            value: team.aiDifficulty,
            decoration: const InputDecoration(labelText: 'AI Zorlugu'),
            items: AiDifficulty.values
                .map(
                  (difficulty) => DropdownMenuItem(
                    value: difficulty,
                    child: Text(difficulty.title),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => team.aiDifficulty = value);
              _save();
            },
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            team.matchHistory.isEmpty
                ? 'Mac kaydi yok'
                : team.matchHistory
                      .take(5)
                      .map(
                        (record) =>
                            '${record.scoreText} ${record.result} ${record.ratingAfter.toStringAsFixed(1)}',
                      )
                      .join(' | '),
            style: const TextStyle(color: Colors.white60),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Reset the team's win/draw/loss record and history without
            // touching the squad.
            OutlinedButton.icon(
              onPressed: () => _adminResetTeamRecord(team),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xffffd34d),
                side: BorderSide(
                  color: const Color(0xffffd34d).withValues(alpha: 0.45),
                ),
              ),
              icon: const Icon(Icons.scoreboard_outlined, size: 17),
              label: const Text('Skor sifirla'),
            ),
            const SizedBox(width: 8),
            team.isDeleted
                ? OutlinedButton.icon(
                    onPressed: () {
                      setState(() => team.isDeleted = false);
                      _save();
                    },
                    icon: const Icon(Icons.restore),
                    label: const Text('Takimi geri getir'),
                  )
                : FilledButton.tonalIcon(
                    onPressed: () => _deleteTeam(team),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Takimi sil'),
                  ),
          ],
        ),
      ],
    );
  }

  /// Zeros the team's record (wins/draws/losses/matches) and its recent
  /// match history. The squad and rating stay untouched.
  Future<void> _adminResetTeamRecord(SavedTeamProfile team) async {
    final ok = await _confirmDialog(
      'Skoru sifirla',
      '${team.name} takiminden: G${team.wins} B${team.draws} M${team.losses} '
      'kaydi ve mac gecmisi silinecek. Devam edilsin mi?',
    );
    if (ok != true || !mounted) return;
    setState(() {
      team.wins = 0;
      team.draws = 0;
      team.losses = 0;
      team.matchHistory.clear();
    });
    await _save();
    _showMessage('${team.name} skoru sifirlandi');
  }

  /// Quick team creation from the admin page. The new team is owned by the
  /// currently active account and starts empty (players added later).
  Future<void> _adminCreateTeam(SavedGameData data) async {
    final name = _adminNewTeamController.text.trim();
    if (name.isEmpty) {
      _showMessage('Takim adi bos olamaz');
      return;
    }
    if (data.teams.any((t) => !t.isDeleted && t.name == name)) {
      _showMessage('Bu isimde bir takim zaten var');
      return;
    }
    final team = SavedTeamProfile.create(
      ownerAccountId: data.activeAccountId,
      name: name,
      playerIds: const [],
    );
    setState(() => data.teams.add(team));
    _adminNewTeamController.clear();
    await _save();
    _showMessage('$name takimi olusturuldu');
  }

  Future<void> _deleteTeam(SavedTeamProfile team) async {
    final data = _data;
    if (data == null) return;
    if (data.activeTeams.length <= 1 && !team.isDeleted) {
      _showMessage('En az bir aktif takim kalmali');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Takimi Sil'),
        content: Text(
          '${team.name} takimini silmek istediginize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      team.isDeleted = true;
      data.transferRequests.removeWhere(
        (request) => request.targetTeamId == team.id,
      );
    });
    await _save();
  }

  Widget _teamSummary(SavedGameData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: ListView(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xff1d3a5f), Color(0xff0d1f33)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.groups_2, color: Color(0xffffd34d)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'İki takım panosu — kadro ve forma',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _summaryBlock(data.blueTeam, data.bluePlayerIds, data),
          const SizedBox(height: 6),
          _jerseySelector(data.blueTeam, _blueKitIndex, (i) {
            setState(() => _blueKitIndex = i);
            _save();
          }, 'Mavi'),
          const SizedBox(height: 10),
          _lineupEditor(data.blueTeam, data),
          const Divider(height: 26),
          _summaryBlock(data.redTeam, data.redPlayerIds, data),
          const SizedBox(height: 6),
          _jerseySelector(data.redTeam, _redKitIndex, (i) {
            setState(() => _redKitIndex = i);
            _save();
          }, 'Kirmizi'),
          const SizedBox(height: 10),
          _lineupEditor(data.redTeam, data),
          const SizedBox(height: 14),
          const Text(
            'Ilk 11 tam olmadan mac baslamaz. Yeni eklenen oyuncunun boyu 1.70-1.95 m arasinda rastgele atanir.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _jerseySelector(
    SavedTeamProfile team,
    int selectedIndex,
    ValueChanged<int> onChanged,
    String label,
  ) {
    final kits = team.jerseyKits.isEmpty
        ? JerseyFactory.defaultKits()
        : team.jerseyKits;
    final value = selectedIndex.clamp(0, kits.length - 1).toInt();
    return DropdownButtonFormField<int>(
      value: value,
      isDense: true,
      decoration: InputDecoration(labelText: '$label forma'),
      items: [
        for (var i = 0; i < kits.length; i++)
          DropdownMenuItem<int>(
            value: i,
            child: Row(
              children: [
                _kitSwatch(kits[i].shirtColor),
                const SizedBox(width: 6),
                _kitSwatch(kits[i].shortsColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(kits[i].name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      onChanged: (index) {
        if (index == null) {
          return;
        }
        team.activeKitIndex = index;
        onChanged(index);
      },
    );
  }

  Widget _kitSwatch(Color color) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
      ),
    );
  }

  Widget _summaryBlock(
    SavedTeamProfile team,
    Set<String> ids,
    SavedGameData data,
  ) {
    final selected = data.players
        .where((profile) => ids.contains(profile.id))
        .toList();
    final keepers = selected.where((profile) => profile.isGoalkeeper).length;
    final fielders = selected.where((profile) => !profile.isGoalkeeper).length;
    final valid = keepers >= 1 && fielders >= 10;
    final ownerReady = data.isTeamOwnerLoggedIn(team);
    final isAdmin = data.adminLoggedIn;
    final ownerMatches = data.accounts
        .where((account) => account.id == team.ownerAccountId)
        .toList();
    final ownerName = ownerMatches.isEmpty ? null : ownerMatches.first.username;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                team.name,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            if (isAdmin)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 18,
                ),
                onPressed: () => _deleteTeam(team),
                tooltip: 'Takimi sil',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'Oyuncu: ${selected.length}  Deger: ${team.rating.toStringAsFixed(1)}',
        ),
        Text(
          'Galibiyet: ${team.wins}, Maglubiyet: ${team.losses}, Beraberlik: ${team.draws}',
        ),
        Text(
          'Sahip: ${ownerName ?? 'Secilmedi'} (${ownerReady ? 'giris var' : 'giris yok'})',
        ),
        Text('Kaleci: $keepers, saha: $fielders'),
        Text(
          valid ? 'Maca hazir' : '10 saha oyuncusu ve 1 kaleci gerekli',
          style: TextStyle(
            color: valid ? Colors.greenAccent : Colors.orangeAccent,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          selected.take(7).map((profile) => profile.name).join(', '),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  Future<void> _openVisualFormationEditor(
    SavedTeamProfile team,
    SavedGameData data,
  ) async {
    team.ensureLineupDefaults(data.players);
    final presetNameController = TextEditingController();
    final searchController = TextEditingController();
    String? selectedPlayerId;
    String search = '';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final plan = formationPlan(team.formation);
          final members = data.players
              .where(
                (player) =>
                    team.playerIds.contains(player.id) &&
                    (search.isEmpty ||
                        player.name.toLowerCase().contains(search)),
              )
              .toList()
            ..sort((a, b) {
              if (a.isGoalkeeper != b.isGoalkeeper) {
                return a.isGoalkeeper ? -1 : 1;
              }
              return b.effectiveOverall.compareTo(a.effectiveOverall);
            });
          final selectedMatches = data.players.where(
            (player) => player.id == selectedPlayerId,
          );
          final selectedPlayer =
              selectedMatches.isEmpty ? null : selectedMatches.first;
          return Dialog(
            backgroundColor: const Color(0xff08140f),
            insetPadding: const EdgeInsets.all(18),
            child: SizedBox(
              width: 1180,
              height: 760,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xff103d2d), Color(0xff111b22)],
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.account_tree,
                          color: Color(0xffffd34d),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${team.name} • Gorsel Dizilis Editoru',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 18),
                        SizedBox(
                          width: 280,
                          child: DropdownButtonFormField<FormationType>(
                            value: playableFormationTypes.contains(team.formation)
                                ? team.formation
                                : FormationType.wing433,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Once dizilisi sec',
                            ),
                            items: [
                              for (final formation in playableFormationTypes)
                                DropdownMenuItem(
                                  value: formation,
                                  child: Text(
                                    formation.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() {
                                _setSelectedTeamFormation(team, data, value);
                                team.activeFormationPresetId = null;
                                team.ensureLineupDefaults(data.players);
                              });
                            },
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Kaydet ve kapat',
                          onPressed: () async {
                            team.ensureLineupDefaults(data.players);
                            await _save();
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 260,
                          child: DropdownButtonFormField<String>(
                            value: team.savedFormations.any(
                              (preset) =>
                                  preset.id == team.activeFormationPresetId,
                            )
                                ? team.activeFormationPresetId
                                : null,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Kayitli takim dizilisi',
                            ),
                            items: [
                              for (final preset in team.savedFormations)
                                DropdownMenuItem(
                                  value: preset.id,
                                  child: Text(
                                    preset.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (presetId) {
                              if (presetId == null) return;
                              final preset = team.savedFormations.firstWhere(
                                (item) => item.id == presetId,
                              );
                              setDialogState(() {
                                team.applyFormationPreset(preset);
                                _setSelectedTeamFormation(
                                  team,
                                  data,
                                  team.formation,
                                );
                                team.ensureLineupDefaults(data.players);
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: presetNameController,
                            decoration: const InputDecoration(
                              labelText: 'Dizilis kayit adi',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () {
                            final name = presetNameController.text.trim();
                            if (name.isEmpty) {
                              _showMessage('Dizilis icin bir ad yaz');
                              return;
                            }
                            team.ensureLineupDefaults(data.players);
                            if (team.starterPlayerIds.length != 11 ||
                                team.slotByPlayerId.length != 11) {
                              _showMessage(
                                'Kaydetmeden once 11 daireyi de doldur',
                              );
                              return;
                            }
                            setDialogState(() {
                              team.saveCurrentFormation(name);
                              presetNameController.clear();
                            });
                            _save();
                          },
                          icon: const Icon(Icons.save),
                          label: const Text('Takima kaydet'),
                        ),
                        if (team.activeFormationPresetId != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Kayitli dizilisi sil',
                            onPressed: () {
                              setDialogState(() {
                                team.savedFormations.removeWhere(
                                  (preset) =>
                                      preset.id == team.activeFormationPresetId,
                                );
                                team.activeFormationPresetId = null;
                              });
                              _save();
                            },
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          'Ilk 11: ${team.starterPlayerIds.length}/11',
                          style: TextStyle(
                            color: team.starterPlayerIds.length == 11
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 7,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 10, 14),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final pitchWidth = constraints.maxWidth;
                                final pitchHeight = constraints.maxHeight;
                                return Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xff087a36),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white70,
                                      width: 2,
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: pitchWidth / 2 - 1,
                                        top: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 2,
                                          color: Colors.white38,
                                        ),
                                      ),
                                      Positioned(
                                        left: pitchWidth / 2 - 58,
                                        top: pitchHeight / 2 - 58,
                                        child: Container(
                                          width: 116,
                                          height: 116,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white38,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                      for (var slotIndex = 0;
                                          slotIndex < plan.spots.length;
                                          slotIndex++)
                                        _formationSlot(
                                          team: team,
                                          data: data,
                                          plan: plan,
                                          slotIndex: slotIndex,
                                          pitchWidth: pitchWidth,
                                          pitchHeight: pitchHeight,
                                          selectedPlayerId: selectedPlayerId,
                                          onSelected: (playerId) {
                                            setDialogState(
                                              () => selectedPlayerId = playerId,
                                            );
                                          },
                                          onDrop: (profile) {
                                            setDialogState(() {
                                              _assignPlayerToFormationSlot(
                                                team,
                                                profile,
                                                slotIndex,
                                              );
                                              selectedPlayerId = profile.id;
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 5,
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(0, 0, 14, 14),
                            decoration: BoxDecoration(
                              color: const Color(0xff0d1a16),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: TextField(
                                    controller: searchController,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.search),
                                      labelText: 'Oyuncu ara ve sahaya surukle',
                                      isDense: true,
                                    ),
                                    onChanged: (value) => setDialogState(
                                      () => search = value.trim().toLowerCase(),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: ListView.builder(
                                    itemCount: members.length,
                                    itemBuilder: (context, index) {
                                      final player = members[index];
                                      final slot = team.slotByPlayerId[player.id];
                                      return Draggable<PlayerProfile>(
                                        data: player,
                                        feedback: Material(
                                          color: Colors.transparent,
                                          child: _dragPlayerCard(player),
                                        ),
                                        childWhenDragging: Opacity(
                                          opacity: 0.35,
                                          child: _rosterPlayerTile(
                                            player,
                                            slot,
                                            selectedPlayerId == player.id,
                                          ),
                                        ),
                                        child: InkWell(
                                          onTap: () => setDialogState(
                                            () => selectedPlayerId = player.id,
                                          ),
                                          child: _rosterPlayerTile(
                                            player,
                                            slot,
                                            selectedPlayerId == player.id,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  flex: 2,
                                  child: selectedPlayer == null
                                      ? const Center(
                                          child: Text(
                                            'Tum istatistikleri gormek icin oyuncuya tikla',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white54,
                                            ),
                                          ),
                                        )
                                      : _formationPlayerStats(selectedPlayer),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Oyuncuyu tutup daireye birak. Dolu daireye birakirsan oyuncular yer degistirir.',
                            style: TextStyle(color: Colors.white60),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            setDialogState(() {
                              team
                                ..slotByPlayerId.clear()
                                ..starterPlayerIds.clear()
                                ..activeFormationPresetId = null;
                            });
                          },
                          child: const Text('Sahayı temizle'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () async {
                            team.ensureLineupDefaults(data.players);
                            await _save();
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                          icon: const Icon(Icons.check),
                          label: const Text('Uygula ve kapat'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    presetNameController.dispose();
    searchController.dispose();
    if (mounted) setState(() {});
  }

  Widget _formationSlot({
    required SavedTeamProfile team,
    required SavedGameData data,
    required FormationPlan plan,
    required int slotIndex,
    required double pitchWidth,
    required double pitchHeight,
    required String? selectedPlayerId,
    required ValueChanged<String> onSelected,
    required ValueChanged<PlayerProfile> onDrop,
  }) {
    final spot = plan.spots[slotIndex];
    final assigned = team.slotByPlayerId.entries.where(
      (entry) => entry.value == slotIndex,
    );
    PlayerProfile? player;
    if (assigned.isNotEmpty) {
      final matches = data.players.where(
        (profile) => profile.id == assigned.first.key,
      );
      if (matches.isNotEmpty) player = matches.first;
    }
    final left = (18 + spot.x * (pitchWidth - 100)).clamp(
      0.0,
      pitchWidth - 84,
    ).toDouble();
    final top = (18 + spot.y * (pitchHeight - 90)).clamp(
      0.0,
      pitchHeight - 64,
    ).toDouble();
    return Positioned(
      left: left,
      top: top,
      width: 84,
      height: 64,
      child: DragTarget<PlayerProfile>(
        onWillAcceptWithDetails: (details) =>
            details.data.isGoalkeeper == spot.role.isGoalkeeper &&
            !details.data.isUnavailable &&
            team.playerIds.contains(details.data.id),
        onAcceptWithDetails: (details) => onDrop(details.data),
        builder: (context, candidates, rejected) {
          final highlighted = candidates.isNotEmpty;
          final content = AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highlighted
                  ? const Color(0xffffd34d)
                  : player == null
                  ? Colors.black.withValues(alpha: 0.30)
                  : player.id == selectedPlayerId
                  ? const Color(0xffffd34d).withValues(alpha: 0.88)
                  : const Color(0xff102019).withValues(alpha: 0.94),
              border: Border.all(
                color: highlighted
                    ? Colors.white
                    : player == null
                    ? Colors.white54
                    : Colors.white,
                width: highlighted ? 3 : 1.5,
              ),
              boxShadow: [
                if (player != null)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 8,
                  ),
              ],
            ),
            alignment: Alignment.center,
            child: player == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add, size: 18, color: Colors.white70),
                      Text(
                        spot.role.code,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${player.number ?? spot.number}',
                        style: TextStyle(
                          color: player.id == selectedPlayerId
                              ? Colors.black
                              : const Color(0xffffd34d),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Text(
                          player.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: player.id == selectedPlayerId
                                ? Colors.black
                                : Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${spot.role.code} • ${player.effectiveOverall.round()}',
                        style: TextStyle(
                          color: player.id == selectedPlayerId
                              ? Colors.black87
                              : Colors.white60,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
          );
          if (player == null) return content;
          final assignedPlayer = player;
          return Draggable<PlayerProfile>(
            data: assignedPlayer,
            feedback: Material(
              color: Colors.transparent,
              child: _dragPlayerCard(assignedPlayer),
            ),
            childWhenDragging: Opacity(opacity: 0.28, child: content),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onSelected(assignedPlayer.id),
              child: content,
            ),
          );
        },
      ),
    );
  }

  void _setSelectedTeamFormation(
    SavedTeamProfile team,
    SavedGameData data,
    FormationType formation,
  ) {
    team.formation = formation;
    if (team.id == data.blueTeamId) {
      data.blueFormation = formation;
    }
    if (team.id == data.redTeamId) {
      data.redFormation = formation;
    }
  }

  void _assignPlayerToFormationSlot(
    SavedTeamProfile team,
    PlayerProfile profile,
    int newSlot,
  ) {
    final plan = formationPlan(team.formation);
    if (newSlot < 0 || newSlot >= plan.spots.length) return;
    if (profile.isGoalkeeper != plan.spots[newSlot].role.isGoalkeeper) return;
    final oldSlot = team.slotByPlayerId[profile.id];
    String? occupyingPlayerId;
    for (final entry in team.slotByPlayerId.entries) {
      if (entry.value == newSlot && entry.key != profile.id) {
        occupyingPlayerId = entry.key;
        break;
      }
    }
    if (occupyingPlayerId != null) {
      if (oldSlot != null) {
        team.slotByPlayerId[occupyingPlayerId] = oldSlot;
        team.starterPlayerIds.add(occupyingPlayerId);
        team.roleByPlayerId[occupyingPlayerId] = plan.spots[oldSlot].role;
      } else {
        team.slotByPlayerId.remove(occupyingPlayerId);
        team.starterPlayerIds.remove(occupyingPlayerId);
      }
    }
    team
      ..slotByPlayerId[profile.id] = newSlot
      ..starterPlayerIds.add(profile.id)
      ..roleByPlayerId[profile.id] = plan.spots[newSlot].role
      ..activeFormationPresetId = null;
    if (team.starterPlayerIds.length > 11) {
      final removable = team.starterPlayerIds.firstWhere(
        (id) => !team.slotByPlayerId.containsKey(id),
        orElse: () => '',
      );
      if (removable.isNotEmpty) team.starterPlayerIds.remove(removable);
    }
  }

  Widget _dragPlayerCard(PlayerProfile player) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xff102019),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xffffd34d)),
      ),
      child: Text(
        '${player.name} • OVR ${player.effectiveOverall.round()}',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _rosterPlayerTile(
    PlayerProfile player,
    int? slot,
    bool selected,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xffffd34d).withValues(alpha: 0.17)
            : Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? const Color(0xffffd34d) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Icon(
            player.isGoalkeeper ? Icons.back_hand : Icons.person,
            color: player.isGoalkeeper
                ? const Color(0xffffd34d)
                : Colors.white70,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  'OVR ${player.effectiveOverall.round()} • Sut ${player.shootingRating.round()} • Pas ${player.passingRating.round()} • Hiz ${player.speedRating.round()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 9),
                ),
              ],
            ),
          ),
          Text(
            slot == null ? 'YEDEK' : 'SLOT ${slot + 1}',
            style: TextStyle(
              color: slot == null ? Colors.white38 : Colors.greenAccent,
              fontWeight: FontWeight.w800,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _formationPlayerStats(PlayerProfile player) {
    final passPercent = player.passes == 0
        ? 0
        : (player.successfulPasses * 100 / player.passes).round();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            player.name,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xffffd34d),
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 10,
            runSpacing: 7,
            children: [
              _formationStat('Forma no', player.number ?? 0),
              _formationStat('OVR', player.overallRating.round()),
              _formationStat('Efektif OVR', player.effectiveOverall.round()),
              _formationStat('Sut', player.shootingRating.round()),
              _formationStat('Bitiricilik', player.finishingRating.round()),
              _formationStat('Sut gucu', player.shotPowerRating.round()),
              _formationStat('Uzaktan sut', player.longShotsRating.round()),
              _formationStat('Falso', player.curveRating.round()),
              _formationStat('Sogukkanlilik', player.composureRating.round()),
              _formationStat('Denge', player.balanceRating.round()),
              _formationStat('Zayif ayak', '${player.weakFootRating}/5'),
              _formationStat('Pas gucu', player.passingRating.round()),
              _formationStat('Kaleci gucu', player.goalkeepingRating.round()),
              if (player.isGoalkeeper) ...[
                _formationStat('GK Reaksiyon', player.goalkeeperReactionRating.round()),
                _formationStat('GK Pozisyon', player.goalkeeperPositioningRating.round()),
                _formationStat('GK Atlayis', player.goalkeeperDivingRating.round()),
                _formationStat('GK Handling', player.goalkeeperHandlingRating.round()),
                _formationStat('GK Yakalayis', player.goalkeeperCatchingRating.round()),
                _formationStat('GK Sicrama', player.goalkeeperJumpingRating.round()),
                _formationStat('GK Karar', player.goalkeeperDecisionRating.round()),
                _formationStat('GK Bire Bir', player.goalkeeperOneVsOneRating.round()),
                _formationStat('GK Yuksek Top', player.goalkeeperHighBallsRating.round()),
                _formationStat('GK Erisim', player.goalkeeperReachRating.round()),
                _formationStat('GK Ongoru', player.goalkeeperAnticipationRating.round()),
                _formationStat('GK Sektirme', player.goalkeeperParryingRating.round()),
                _formationStat('GK Dagitim', player.goalkeeperDistributionRating.round()),
              ],
              _formationStat('Hiz gucu', player.speedRating.round()),
              _formationStat('Enerji gucu', player.staminaRating.round()),
              _formationStat('Dayaniklilik', player.dayaniklilikGucu.round()),
              _formationStat('Zeka', player.zekaGucu.round()),
              _formationStat('Boy', (player.heightMeters * 100).round()),
              _formationStat('Mac', player.matchesPlayed),
              _formationStat('Dakika', player.minutesPlayed),
              _formationStat('Gol', player.goals),
              _formationStat('Asist', player.assists),
              _formationStat('Pas', player.passes),
              _formationStat('Basarili pas', player.successfulPasses),
              _formationStat('Pas %', passPercent),
              _formationStat('Dripling', player.dribbles),
              _formationStat('Basarili dripling', player.successfulDribbles),
              _formationStat('Mudahale', player.tackles),
              _formationStat('Sut', player.shots),
              _formationStat('Isabetli sut', player.shotsOnTarget),
              _formationStat('Kacan firsat', player.missedChances),
              _formationStat('Uzaklastirma', player.clearances),
              _formationStat('Kurtaris', player.saves),
              _formationStat('Yaptigi faul', player.foulsCommitted),
              _formationStat('Aldigi faul', player.foulsReceived),
              _formationStat('Sari', player.yellowCards),
              _formationStat('Kirmizi', player.redCards),
              _formationStat('Puan', player.points.toStringAsFixed(1)),
              _formationStat('Fitness', '%${(player.fitness * 100).round()}'),
              _formationStat('Sakatlik gunu', player.injuredDaysRemaining),
              _formationStat(
                'Ceza maci',
                player.suspendedMatchesRemaining,
              ),
            ],
          ),
          if (player.isUnavailable) ...[
            const SizedBox(height: 8),
            Text(
              player.isInjured
                  ? 'SAKAT: ${player.injuredDaysRemaining} gun'
                  : 'CEZALI: ${player.suspendedMatchesRemaining} mac',
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _formationStat(String label, Object value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _lineupEditor(SavedTeamProfile team, SavedGameData data) {
    final allTeamPlayers = data.players
        .where((profile) => team.playerIds.contains(profile.id))
        .toList();
    final query = (_lineupSearchByTeam[team.id] ?? '').trim().toLowerCase();
    final players = allTeamPlayers
        .where(
          (profile) => query.isEmpty ||
              profile.name.toLowerCase().contains(query) ||
              (profile.number?.toString().contains(query) ?? false),
        )
        .toList();
    final starters = allTeamPlayers
        .where((profile) => team.starterPlayerIds.contains(profile.id))
        .length;
    final canEdit = data.isTeamOwnerLoggedIn(team) || data.adminLoggedIn;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${team.name} ilk 11: $starters/11${canEdit ? '' : ' | sahip giris yok'}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: canEdit
                      ? () => _openVisualFormationEditor(team, data)
                      : null,
                  icon: const Icon(Icons.account_tree, size: 17),
                  label: const Text('Gorsel dizilis'),
                ),
                const SizedBox(width: 8),
                Text(
                  'Degisiklik 5',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 19),
                labelText: 'Kadroda oyuncu ara',
                isDense: true,
              ),
              onChanged: (value) => setState(
                () => _lineupSearchByTeam[team.id] = value,
              ),
            ),
          ),
          SizedBox(
            height: 250,
            child: players.isEmpty
                ? const Center(child: Text('Bu takimda oyuncu yok'))
                : ListView.builder(
                    itemCount: players.length,
                    itemBuilder: (context, index) {
                      final profile = players[index];
                      final isStarter = team.starterPlayerIds.contains(
                        profile.id,
                      );
                      final allowedRoles = profile.isGoalkeeper
                          ? const [PlayerRole.goalkeeper]
                          : PlayerRole.values
                                .where((role) => !role.isGoalkeeper)
                                .toList();
                      final role =
                          allowedRoles.contains(team.roleByPlayerId[profile.id])
                          ? team.roleByPlayerId[profile.id]!
                          : allowedRoles.first;
                      return SizedBox(
                        height: 44,
                        child: Row(
                          children: [
                            Checkbox(
                              value: isStarter,
                              onChanged: canEdit
                                  ? (value) {
                                      setState(() {
                                        if (value == true) {
                                          if (profile.isUnavailable) {
                                            return;
                                          }
                                          if (team.starterPlayerIds.length <
                                              11) {
                                            team.starterPlayerIds.add(
                                              profile.id,
                                            );
                                          }
                                        } else {
                                          team.starterPlayerIds.remove(
                                            profile.id,
                                          );
                                        }
                                        team.activeFormationPresetId = null;
                                      });
                                      _save();
                                    }
                                  : null,
                            ),
                            SizedBox(
                              width: 34,
                              child: Text(
                                '#${profile.number ?? index + 1}',
                                style: TextStyle(
                                  color: profile.isUnavailable
                                      ? const Color(0xffff6b6b)
                                      : null,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          profile.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            // Injured and suspended players
                                            // are always red in the lineup
                                            // (مطلب: المصابين والمعاقبين بالاحمر).
                                            color: profile.isUnavailable
                                                ? const Color(0xffff6b6b)
                                                : null,
                                            fontWeight: profile.isUnavailable
                                                ? FontWeight.w900
                                                : null,
                                          ),
                                        ),
                                      ),
                                      if (profile.isSuspended) ...[
                                        const SizedBox(width: 6),
                                        _statusBadge(
                                          'Cezalı ${profile.suspendedMatchesRemaining} maç',
                                          const Color(0xffff6b6b),
                                        ),
                                      ] else if (profile.isInjured) ...[
                                        const SizedBox(width: 6),
                                        _statusBadge(
                                          'Sakat ${profile.injuredDaysRemaining} gün',
                                          const Color(0xffff6b6b),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    'OVR:${profile.overallRating.toStringAsFixed(0)} DY:${profile.dayaniklilikGucu.toStringAsFixed(0)} ZK:${profile.zekaGucu.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 150,
                              child: DropdownButton<PlayerRole>(
                                value: role,
                                isExpanded: true,
                                underline: const SizedBox.shrink(),
                                items: allowedRoles
                                    .map(
                                      (role) => DropdownMenuItem(
                                        value: role,
                                        child: Text(role.turkishName),
                                      ),
                                    )
                                    .toList(),
                                onChanged: canEdit
                                    ? (value) {
                                        if (value == null) {
                                          return;
                                        }
                                        setState(() {
                                          if (!isStarter) {
                                            team
                                              ..roleByPlayerId[profile.id] = value
                                              ..activeFormationPresetId = null;
                                            return;
                                          }
                                          final plan = formationPlan(
                                            team.formation,
                                          );
                                          final matchingSlots = List<int>.generate(
                                            plan.spots.length,
                                            (slot) => slot,
                                          ).where(
                                            (slot) =>
                                                plan.spots[slot].role == value,
                                          );
                                          if (matchingSlots.isEmpty) return;
                                          final occupiedSlots = team
                                              .slotByPlayerId
                                              .entries
                                              .where(
                                                (entry) =>
                                                    entry.key != profile.id,
                                              )
                                              .map((entry) => entry.value)
                                              .toSet();
                                          final emptyMatches = matchingSlots.where(
                                            (slot) =>
                                                !occupiedSlots.contains(slot),
                                          );
                                          _assignPlayerToFormationSlot(
                                            team,
                                            profile,
                                            emptyMatches.isNotEmpty
                                                ? emptyMatches.first
                                                : matchingSlots.first,
                                          );
                                        });
                                        _save();
                                      }
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _adminPanelDecoration(Color accent) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: 0.08),
          const Color(0xff0c1713),
          const Color(0xff08110d),
        ],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: accent.withValues(alpha: 0.28), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [
          Color(0xff11201a),
          Color(0xff0b1512),
          Color(0xff0a1310),
        ],
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: const Color(0xffd4af37).withValues(alpha: 0.18),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

/// Bouncing football loading splash: the ball hops on a soft shadow in
/// a loop while the match is being prepared.
class _LoadingBall extends StatefulWidget {
  const _LoadingBall({this.caption});

  final String? caption;

  @override
  State<_LoadingBall> createState() => _LoadingBallState();
}

class _LoadingBallState extends State<_LoadingBall>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // Ease-in on the way down so the ball "hits" the ground.
            final t = Curves.easeIn.transform(_controller.value);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: Offset(0, -46 * (1 - t)),
                  child: const Icon(
                    Icons.sports_soccer,
                    size: 58,
                    color: Color(0xfff5d67b),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: 46 - 14 * t,
                  height: 9,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.30 + t * 0.25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        Text(
          widget.caption ?? 'Yukleniyor...',
          style: const TextStyle(
            color: Color(0xfff5d67b),
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Gentle attention pulse on the start-match button: a soft breathing
/// scale loop that stops while the match is loading.
class _StartPulse extends StatefulWidget {
  const _StartPulse({required this.child, this.paused = false});

  final Widget child;
  final bool paused;

  @override
  State<_StartPulse> createState() => _StartPulseState();
}

class _StartPulseState extends State<_StartPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void didUpdateWidget(covariant _StartPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused && _controller.isAnimating) {
      _controller.stop();
    } else if (!widget.paused && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.paused) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(scale: 1 + _controller.value * 0.035, child: child);
      },
      child: widget.child,
    );
  }
}

/// Compact icon-only button with a tooltip for the admin header actions.
