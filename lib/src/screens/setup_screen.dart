import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
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
  final TextEditingController _newTeamController = TextEditingController();
  final TextEditingController _blueNameController = TextEditingController();
  final TextEditingController _redNameController = TextEditingController();
  final FocusNode _keyboardFocus = FocusNode();
  final Set<LogicalKeyboardKey> _pressedKeys = <LogicalKeyboardKey>{};
  SavedGameData? _data;
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
  // Yeni oyuncular yonetim sayfasi durumu (مطلب: صفحة لاعبين بالإدارة).
  String _managePlayerSearch = '';
  String _managePlayerCountryFilter = 'all';
  final Set<String> _manageSelectedIds = <String>{};
  final TextEditingController _manageNewPlayerController =
      TextEditingController();
  String? _adminQualityTeamId;
  bool _manageNewIsGoalkeeper = false;
  final TextEditingController _importPathsController = TextEditingController();
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
    _newTeamController.dispose();
    _blueNameController.dispose();
    _manageNewPlayerController.dispose();
    _importPathsController.dispose();
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
    // The selected match teams must ALWAYS reference real active teams by
    // their ids — never by list order (مطلب: الفريق الظاهر هو نفسه
    // المحدد فعلياً، والمرجع معرّف الفريق وليس ترتيب القائمة).
    _sanitizeTeamSelection(data);
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

  /// Repairs the blue/red selection when a stored team id no longer points
  /// to an active team (deleted teams etc.). Everything is resolved by
  /// TEAM ID — the list order is never used as a reference, so the team
  /// shown in the dropdowns is exactly the team passed to the match
  /// (مطلب: لا يعتمد على الترتيب، والمعرّف هو المرجع الوحيد).
  void _sanitizeTeamSelection(SavedGameData data) {
    final active = data.activeTeams;
    if (active.isEmpty) {
      return;
    }
    bool isActive(String id) => active.any((team) => team.id == id);
    if (!isActive(data.blueTeamId)) {
      final owned = data.ownedTeams;
      final pick = owned.isNotEmpty ? owned.first : active.first;
      data.blueTeamId = pick.id;
      data.bluePlayerIds = Set.of(pick.playerIds);
      data.blueFormation = pick.formation;
      _bluePlayStyle = pick.playStyle;
      _blueKitIndex = pick.activeKitIndex;
    }
    if (!isActive(data.redTeamId)) {
      final owned = data.ownedTeams;
      final pick = owned.firstWhere(
        (team) => team.id != data.blueTeamId,
        orElse: () => active.firstWhere(
          (team) => team.id != data.blueTeamId,
          orElse: () => active.first,
        ),
      );
      data.redTeamId = pick.id;
      data.redPlayerIds = Set.of(pick.playerIds);
      data.redFormation = pick.formation;
      _redPlayStyle = pick.playStyle;
      _redKitIndex = pick.activeKitIndex;
    }
  }

  Future<void> _save() async {
    final data = _data;
    if (data == null) {
      return;
    }
    // Never persist a selection pointing at a missing team.
    _sanitizeTeamSelection(data);
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

  /// Country picker fed EXCLUSIVELY by the countries catalogue — the list
  /// contains only countries added on the countries page (مطلب: لا دول
  /// افتراضية ولا دول غير موجودة في الكتالوج). Returns null on cancel.
  Future<String?> _pickCatalogCountry(SavedGameData data, String title) async {
    var picked = 'غير محدد';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff0e1c17),
          title: Text(title),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: data.countries.contains(picked)
                      ? picked
                      : 'غير محدد',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Takim ulkesi',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'غير محدد',
                      child: Text('Belirsiz'),
                    ),
                    for (final country in data.countries)
                      DropdownMenuItem(value: country, child: Text(country)),
                  ],
                  onChanged: (value) => setDialogState(
                    () => picked = value ?? 'غير محدد',
                  ),
                ),
                if (data.countries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Henuz ulke eklenmedi — once Ulkeler sayfasindan '
                      'ulke ekleyin.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xffffd34d),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Vazgec'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff00d084),
                foregroundColor: const Color(0xff00130c),
              ),
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return null;
    return picked;
  }

  Future<void> _addTeam() async {
    final data = _data;
    if (data == null || _newTeamController.text.trim().isEmpty) {
      return;
    }
    // Country is chosen from the catalogue ONLY — countries added on the
    // countries page, nothing else (مطلب: قائمة الدول من الكتالوج فقط).
    var pickedCountry = 'غير محدد';
    if (data.countries.isNotEmpty) {
      final picked = await _pickCatalogCountry(data, 'Ulke sec');
      if (picked == null || !mounted) return;
      pickedCountry = picked;
    }
    final team = SavedTeamProfile.create(
      ownerAccountId: data.activeAccountId,
      name: _newTeamController.text,
      playerIds: const [],
    );
    setState(() {
      team.country = pickedCountry;
      data.teams.add(team);
      data.blueTeamId = team.id;
      data.bluePlayerIds = Set.of(team.playerIds);
      data.blueFormation = team.formation;
      _blueNameController.text = team.name;
      if (data.redTeamId == data.blueTeamId && data.ownedTeams.length > 1) {
        data.redTeamId = data.ownedTeams
            .firstWhere((ownedTeam) => ownedTeam.id != team.id)
            .id;
        data.redPlayerIds = Set.of(data.redTeam.playerIds);
        data.redFormation = data.redTeam.formation;
        _redNameController.text = data.redTeam.name;
      }
      _newTeamController.clear();
    });
    await _save();
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
                              final team = data.teams.firstWhere(
                                (team) => team.id == id,
                                orElse: () => data.activeTeams.first,
                              );
                              // Copy the squad set — aliasing the team's own
                              // set would leak edits across selections.
                              setState(() {
                                data.blueTeamId = team.id;
                                data.bluePlayerIds = Set.of(team.playerIds);
                                data.blueFormation = team.formation;
                                _bluePlayStyle = team.playStyle;
                                _blueKitIndex = team.activeKitIndex;
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
                              final team = data.teams.firstWhere(
                                (team) => team.id == id,
                                orElse: () => data.activeTeams.first,
                              );
                              setState(() {
                                data.redTeamId = team.id;
                                data.redPlayerIds = Set.of(team.playerIds);
                                data.redFormation = team.formation;
                                _redPlayStyle = team.playStyle;
                                _redKitIndex = team.activeKitIndex;
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
          // Oyuncu ekleme ve ice aktarma artik YALNIZCA yonetim sayfasinda
          // (مطلب: اضافة لاعبين جدد فقط من طرف الإدارة).
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

  /// Removes anything written between brackets from a player name —
  /// the team is shown separately in brackets instead
  /// (مطلب: يشيل أي شي داخل قوسين من اسم اللاعب).
  String _cleanPlayerName(String name) {
    return name
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]|\{[^}]*\}'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Display label: clean name + (team name); players with no team show
  /// (Satılık) — for sale (مطلب: جنب كل لاعب اسم فريقه داخل قوسين،
  /// واللي بدون فريق يظهر للبيع).
  String _playerDisplayLabel(SavedGameData data, PlayerProfile profile) {
    final team = _teamForPlayer(data, profile);
    final name = _cleanPlayerName(profile.name);
    return team == null ? '$name (Satılık)' : '$name (${team.name})';
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
                        _playerDisplayLabel(data, profile),
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
    // «Ülkeler» and «Formalar» are visible with the regular admin password;
    // only the player-settings tab still needs the kimo@ full access
    // (مطلب: الدول والقمصان تظهر بكلمة المرور العادية).
    final subTab = _adminSubTab == 2 && !data.adminFullAccess ? 0 : _adminSubTab;
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
              // Ülkeler ve Formalar normal yonetici sifresiyle acilir.
              _adminNavItem(
                icon: Icons.public,
                label: 'Ülkeler',
                count: _distinctCountryCount(data),
                selected: subTab == 4,
                accent: accent,
                onTap: () => setState(() => _adminSubTab = 4),
              ),
              _adminNavItem(
                icon: Icons.sports_soccer,
                label: 'Formalar',
                count: data.teams.where((t) => !t.isDeleted).length,
                selected: subTab == 5,
                accent: accent,
                onTap: () => setState(() => _adminSubTab = 5),
              ),
              _adminNavItem(
                icon: Icons.manage_accounts,
                label: 'Oyuncu yonetimi',
                count: data.players.length,
                selected: subTab == 6,
                accent: accent,
                onTap: () => setState(() => _adminSubTab = 6),
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
                4 => _adminCountriesTab(data),
                5 => _adminKitsTab(data),
                6 => _adminManagePlayersTab(data),
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
      ...data.countries,
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
            FilledButton.icon(
              onPressed: () => _addCountryNew(data),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff00d084),
                foregroundColor: const Color(0xff00130c),
              ),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Ülke ekle', style: TextStyle(fontSize: 12)),
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
                      // Ülke islemleri: yeniden adlandir ve sil
                      // (مطلب: تعديل وحذف واضافة دولة بسهولة).
                      trailing: country == 'غير محدد'
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Yeniden adlandır',
                                  icon: const Icon(Icons.edit, size: 16),
                                  onPressed: () =>
                                      _renameCountry(data, country),
                                ),
                                IconButton(
                                  tooltip: 'Ülkeyi sil',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () =>
                                      _deleteCountry(data, country),
                                ),
                              ],
                            ),
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
    // Only countries added from the countries page are offered —
    // never implicit or default countries (مطلب: فقط دول الكتالوج).
    final suggestions = <String>{
      if (data != null) ...data.countries,
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
              OutlinedButton.icon(
                onPressed: canDelete ? () => _deleteKit(team, index) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: BorderSide(
                    color: Colors.redAccent.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 30),
                ),
                icon: const Icon(Icons.delete_outline, size: 14),
                label: const Text('Sil', style: TextStyle(fontSize: 11)),
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

  /// Kit color row: label + current color + a button opening the FULL
  /// color picker — any color, no limited palette
  /// (مطلب: اختار اللون اللي بدي ياه بلا حدود).
  Widget _kitColorPicker(
    String label,
    Color current,
    ValueChanged<Color> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            width: 34,
            height: 22,
            decoration: BoxDecoration(
              color: current,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.white30),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () async {
              final picked = await _colorPickerDialog(current);
              if (picked != null) onChanged(picked);
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 30),
            ),
            child: const Text('Renk seç', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  /// Full-featured color picker: hue/saturation/brightness sliders, hex
  /// input and quick palette — returns the chosen color.
  Future<Color?> _colorPickerDialog(Color current) {
    final hsv = HSVColor.fromColor(current);
    var hue = hsv.hue;
    var sat = hsv.saturation;
    var val = hsv.value;
    Color fromHsv() => HSVColor.fromAHSV(1, hue, sat, val).toColor();
    String hexOf(Color c) =>
        '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    final hexController = TextEditingController(text: hexOf(current));
    return showDialog<Color>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void syncHex(Color c) {
            hexController.text = hexOf(c);
          }

          return AlertDialog(
            backgroundColor: const Color(0xff0e1c17),
            title: const Text('Renk seç'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: fromHsv(),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white30),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Ton (Hue): ${hue.round()}°',
                      style: const TextStyle(fontSize: 11)),
                  Slider(
                    value: hue,
                    min: 0,
                    max: 360,
                    onChanged: (v) => setDialogState(() {
                      hue = v;
                      syncHex(fromHsv());
                    }),
                  ),
                  Text('Doygunluk: ${(sat * 100).round()}%',
                      style: const TextStyle(fontSize: 11)),
                  Slider(
                    value: sat,
                    min: 0,
                    max: 1,
                    onChanged: (v) => setDialogState(() {
                      sat = v;
                      syncHex(fromHsv());
                    }),
                  ),
                  Text('Parlaklık: ${(val * 100).round()}%',
                      style: const TextStyle(fontSize: 11)),
                  Slider(
                    value: val,
                    min: 0,
                    max: 1,
                    onChanged: (v) => setDialogState(() {
                      val = v;
                      syncHex(fromHsv());
                    }),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: hexController,
                          decoration: const InputDecoration(
                            labelText: 'Hex (#RRGGBB)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (text) {
                            final parsed = _parseHexColor(text);
                            if (parsed != null) {
                              setDialogState(() {
                                final h = HSVColor.fromColor(parsed);
                                hue = h.hue;
                                sat = h.saturation;
                                val = h.value;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final color in _kitPalette)
                        GestureDetector(
                          onTap: () => setDialogState(() {
                            final h = HSVColor.fromColor(color);
                            hue = h.hue;
                            sat = h.saturation;
                            val = h.value;
                            syncHex(color);
                          }),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(fromHsv()),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff00d084),
                  foregroundColor: const Color(0xff00130c),
                ),
                child: const Text('Tamam'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Parses #RGB / #RRGGBB / #AARRGGBB text into a Color.
  Color? _parseHexColor(String text) {
    var hex = text.trim().replaceFirst('#', '');
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return null;
    return Color(value);
  }

  // =====================================================================
  // Yönetim — Oyuncu yönetimi (مطلب جديد): صفحة لاعبين بكلمة المرور
  // العادية: تعديل الاسم، حذف، تغيير البلد، تحديد جماعي + فرز حسب الدولة،
  // إضافة لاعب يدوياً واستيراد عدة ملفات TXT (كل ملف = فريق).
  // =====================================================================

  Widget _adminManagePlayersTab(SavedGameData data) {
    final query = _managePlayerSearch.trim().toLowerCase();
    bool matches(PlayerProfile player) {
      final okSearch = query.isEmpty ||
          _cleanPlayerName(player.name).toLowerCase().contains(query) ||
          (player.number?.toString().contains(query) ?? false);
      if (!okSearch) return false;
      return switch (_managePlayerCountryFilter) {
        'has' => player.country != 'غير محدد',
        'none' => player.country == 'غير محدد',
        _ => true,
      };
    }

    final players = data.players.where(matches).toList()
      ..sort((a, b) =>
          _cleanPlayerName(a.name).compareTo(_cleanPlayerName(b.name)));
    final selectedVisible =
        players.where((p) => _manageSelectedIds.contains(p.id)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _adminSectionHeader(
          icon: Icons.manage_accounts,
          accent: const Color(0xff00d084),
          title: 'Oyuncu yönetimi — إدارة اللاعبين',
          subtitle:
              'Isim, ulke ve pozisyon duzenle — coklu secim ile toplu ulke '
              'atama veya silme',
        ),
        const SizedBox(height: 10),
        // ---------- Search + filter + add/import ----------
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (value) =>
                    setState(() => _managePlayerSearch = value),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Oyuncu ara...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 175,
              child: DropdownButtonFormField<String>(
                value: _managePlayerCountryFilter,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Ülke filtresi',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text('Tüm oyuncular', style: TextStyle(fontSize: 12)),
                  ),
                  DropdownMenuItem(
                    value: 'has',
                    child: Text('Ülkesi seçili', style: TextStyle(fontSize: 12)),
                  ),
                  DropdownMenuItem(
                    value: 'none',
                    child: Text('Ülkesi yok', style: TextStyle(fontSize: 12)),
                  ),
                ],
                onChanged: (value) => setState(
                  () => _managePlayerCountryFilter = value ?? 'all',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _importTeamsFromTxtDialog,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffffd34d),
                foregroundColor: const Color(0xff241a00),
              ),
              icon: const Icon(Icons.upload_file, size: 16),
              label: const Text('TXT içe aktar', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // ---------- Manual add ----------
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _manageNewPlayerController,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Yeni oyuncu adı',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _manageAddPlayer(data),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: _manageNewIsGoalkeeper,
              label: const Text('Kaleci', style: TextStyle(fontSize: 11)),
              onSelected: (value) =>
                  setState(() => _manageNewIsGoalkeeper = value),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _manageAddPlayer(data),
              icon: const Icon(Icons.person_add_alt_1, size: 16),
              label: const Text('Ekle', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // ---------- Bulk bar ----------
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              Text(
                'Seçili: ${_manageSelectedIds.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Color(0xff9fe8bd),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: players.isEmpty
                    ? null
                    : () => setState(() {
                          _manageSelectedIds
                            ..clear()
                            ..addAll(players.map((p) => p.id));
                        }),
                child: const Text('Görünenleri seç', style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: _manageSelectedIds.isEmpty
                    ? null
                    : () => setState(() => _manageSelectedIds.clear()),
                child: const Text('Temizle', style: TextStyle(fontSize: 11)),
              ),
              const Spacer(),
              if (selectedVisible > 0) ...[
                OutlinedButton.icon(
                  onPressed: () => _bulkAssignCountry(data),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                  ),
                  icon: const Icon(Icons.flag_outlined, size: 14),
                  label: Text(
                    'Ülke ata ($selectedVisible)',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: () => _bulkDeletePlayers(data),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(
                      color: Colors.redAccent.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 14),
                  label: Text(
                    'Sil ($selectedVisible)',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        // ---------- Player list ----------
        Expanded(
          child: players.isEmpty
              ? const Center(
                  child: Text(
                    'Sonuç yok',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 14),
                  itemCount: players.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 5),
                  itemBuilder: (context, index) =>
                      _managePlayerRow(data, players[index]),
                ),
        ),
      ],
    );
  }

  /// One player row in the management list: select, rename, country,
  /// position and delete.
  Widget _managePlayerRow(SavedGameData data, PlayerProfile profile) {
    final selected = _manageSelectedIds.contains(profile.id);
    final hasCountry = profile.country != 'غير محدد';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xff00d084).withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? const Color(0xff00d084).withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: (value) => setState(() {
              if (value == true) {
                _manageSelectedIds.add(profile.id);
              } else {
                _manageSelectedIds.remove(profile.id);
              }
            }),
          ),
          Icon(
            profile.isGoalkeeper ? Icons.back_hand : Icons.directions_run,
            size: 15,
            color: profile.isGoalkeeper
                ? const Color(0xffffd34d)
                : Colors.white38,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _playerDisplayLabel(data, profile),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
          // ---- Country chip ----
          ActionChip(
            avatar: Icon(
              hasCountry ? Icons.flag : Icons.flag_outlined,
              size: 13,
              color: hasCountry
                  ? const Color(0xff00d084)
                  : const Color(0xffffd34d),
            ),
            label: Text(
              countryLabel(profile.country),
              style: const TextStyle(fontSize: 10.5),
            ),
            onPressed: () => _assignCountry(
              profile.country,
              title: profile.name,
              onPicked: (country, {required bool includePlayers}) {
                setState(() => profile.country = country);
                _save();
              },
            ),
          ),
          const SizedBox(width: 4),
          // ---- Position ----
          SizedBox(
            width: 118,
            child: DropdownButtonFormField<String>(
              value: _roleGroupOf(data, profile),
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'gk', child: Text('Kaleci', style: TextStyle(fontSize: 10.5))),
                DropdownMenuItem(value: 'def', child: Text('Defans', style: TextStyle(fontSize: 10.5))),
                DropdownMenuItem(value: 'mid', child: Text('Orta saha', style: TextStyle(fontSize: 10.5))),
                DropdownMenuItem(value: 'att', child: Text('Forvet', style: TextStyle(fontSize: 10.5))),
              ],
              onChanged: (value) {
                if (value == null) return;
                _setPlayerRoleGroup(data, profile, value);
              },
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'İsmi düzenle',
            icon: const Icon(Icons.edit, size: 16),
            onPressed: () => _renamePlayerDialog(data, profile),
          ),
          IconButton(
            tooltip: 'Sil',
            icon: const Icon(
              Icons.delete_outline,
              size: 16,
              color: Colors.redAccent,
            ),
            onPressed: () async {
              _manageSelectedIds
                ..clear()
                ..add(profile.id);
              await _bulkDeletePlayers(data);
            },
          ),
        ],
      ),
    );
  }

  /// Current role group of a player inside his team.
  String _roleGroupOf(SavedGameData data, PlayerProfile profile) {
    if (profile.isGoalkeeper) return 'gk';
    final team = _teamForPlayer(data, profile);
    final role = team?.roleByPlayerId[profile.id];
    if (role == null) return 'mid';
    if (role.isDefender ||
        role == PlayerRole.leftBack ||
        role == PlayerRole.rightBack ||
        role == PlayerRole.centerBackLeft ||
        role == PlayerRole.centerBackRight ||
        role == PlayerRole.sweeper ||
        role == PlayerRole.leftWingBack ||
        role == PlayerRole.rightWingBack) {
      return 'def';
    }
    if (role.isAttacker) return 'att';
    return 'mid';
  }

  /// Sets where a player plays (مطلب: تحديد وين اللاعب بيلعب).
  void _setPlayerRoleGroup(
    SavedGameData data,
    PlayerProfile profile,
    String group,
  ) {
    final team = _teamForPlayer(data, profile);
    if (team == null) {
      _showMessage('Önce oyuncuya takım atayın');
      return;
    }
    setState(() {
      final wasGoalkeeper = profile.isGoalkeeper;
      profile.isGoalkeeper = group == 'gk';
      final role = switch (group) {
        'gk' => PlayerRole.goalkeeper,
        'def' => PlayerRole.centerBackLeft,
        'att' => PlayerRole.striker,
        _ => PlayerRole.midfieldLeft,
      };
      team.roleByPlayerId[profile.id] = role;
      // Slot positions may no longer match — let the lineup re-place him.
      team.slotByPlayerId.remove(profile.id);
      if (group == 'gk' && !wasGoalkeeper) {
        team.starterPlayerIds.add(profile.id);
      }
    });
    _save();
  }

  /// Renames a player (مطلب: تعديل اسم اللاعب من الإدارة).
  Future<void> _renamePlayerDialog(
    SavedGameData data,
    PlayerProfile profile,
  ) async {
    final controller = TextEditingController(text: profile.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xff0e1c17),
        title: const Text('İsmi düzenle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Oyuncu adı',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff00d084),
              foregroundColor: const Color(0xff00130c),
            ),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    setState(() => profile.name = newName.trim());
    await _save();
  }

  /// Adds a single player from the management page (addition is admin-only
  // مطلب: اضافة لاعبين فقط من الإدارة).
  Future<void> _manageAddPlayer(SavedGameData data) async {
    final name = _manageNewPlayerController.text.trim();
    if (name.isEmpty) {
      _showMessage('Oyuncu adı boş olamaz');
      return;
    }
    final profile = PlayerProfile.generated(
      name: _cleanPlayerName(name),
      isGoalkeeper: _manageNewIsGoalkeeper,
    );
    setState(() {
      data.players.add(profile);
      _manageNewPlayerController.clear();
      _manageNewIsGoalkeeper = false;
    });
    await _save();
    _showMessage('Oyuncu eklendi');
  }

  /// Bulk country assignment for the selected players
  /// (مطلب: تحديد اكثر من لاعب وتعيين دولة جماعياً).
  Future<void> _bulkAssignCountry(SavedGameData data) async {
    await _assignCountry(
      'غير محدد',
      title: '${_manageSelectedIds.length} oyuncu',
      onPicked: (country, {required bool includePlayers}) {
        setState(() {
          for (final player in data.players) {
            if (_manageSelectedIds.contains(player.id)) {
              player.country = country;
            }
          }
        });
        _save();
        _showMessage(
          '${_manageSelectedIds.length} oyuncuya ülke atandi: '
          '${countryLabel(country)}',
        );
      },
    );
  }

  /// Bulk delete for the selected players with confirmation
  /// (مطلب: حذف جماعي).
  Future<void> _bulkDeletePlayers(SavedGameData data) async {
    if (_manageSelectedIds.isEmpty) return;
    final ok = await _confirmDialog(
      'Oyuncuları sil',
      '${_manageSelectedIds.length} oyuncu kalıcı olarak silinecek. '
      'Emin misiniz?',
    );
    if (ok != true || !mounted) return;
    setState(() {
      data.players
          .removeWhere((player) => _manageSelectedIds.contains(player.id));
      data.bluePlayerIds.removeWhere(_manageSelectedIds.contains);
      data.redPlayerIds.removeWhere(_manageSelectedIds.contains);
      data.transferRequests.removeWhere(
        (request) => _manageSelectedIds.contains(request.playerId),
      );
      for (final team in data.teams) {
        team.playerIds.removeWhere(_manageSelectedIds.contains);
        team.starterPlayerIds.removeWhere(_manageSelectedIds.contains);
        for (final id in _manageSelectedIds) {
          team.roleByPlayerId.remove(id);
          team.slotByPlayerId.remove(id);
        }
      }
      _manageSelectedIds.clear();
    });
    await _save();
    _showMessage('Oyuncular silindi');
  }

  // =====================================================================
  // TXT takım içe aktarma (مطلب: كل ملف = فريق باسمه، عدة ملفات بسرعة،
  // عشوائي أو اختيار يدوي للمراكز، والحارس مكتوب جنبه GK).
  // =====================================================================

  /// Import dialog: pick several TXT files (or paste paths), then choose
  /// quality + position mode. Each file name becomes the team name.
  Future<void> _importTeamsFromTxtDialog() async {
    final data = _data;
    if (data == null) return;
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff0e1c17),
          title: const Text('TXT içe aktar — her dosya bir takım'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Her satır bir oyuncu. Dosya adı = takım adı. '
                  'Kalecinin yanına GK yazın.',
                  style: TextStyle(fontSize: 11.5, color: Colors.white60),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final files = await _pickTxtFiles();
                    if (files == null || files.isEmpty) return;
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop(files);
                    }
                  },
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('Dosyaları seç...'),
                ),
                const Divider(height: 20),
                TextField(
                  controller: _importPathsController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'veya dosya yollarını yapıştır (her satıra bir yol)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                final paths = _importPathsController.text
                    .split('\n')
                    .map((line) => line.trim())
                    .where((line) => line.isNotEmpty)
                    .toList();
                Navigator.of(dialogContext).pop(paths);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffffd34d),
                foregroundColor: const Color(0xff241a00),
              ),
              child: const Text('İçe aktar'),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    _importPathsController.clear();
    await _runTeamImport(data, result);
  }

  /// Native multi-file picker (Windows). Returns chosen .txt paths.
  Future<List<String>?> _pickTxtFiles() async {
    try {
      const type = XTypeGroup(
        label: 'Metin dosyaları',
        extensions: ['txt'],
      );
      final files = await openFiles(
        acceptedTypeGroups: [type],
        confirmButtonText: 'Seç',
      );
      return files.map((file) => file.path).toList();
    } catch (_) {
      _showMessage('Dosya secici acilamadi — yollari elle yapistirin');
      return null;
    }
  }

  /// Runs the whole multi-file import: parse, ask quality + positions,
  /// create teams and players.
  Future<void> _runTeamImport(SavedGameData data, List<String> paths) async {
    final rng = math.Random();
    // ---------- Parse files ----------
    final parsed = <({String teamName, List<({String name, bool isGk})> players})>[];
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) {
        _showMessage('Dosya bulunamadı: $path');
        continue;
      }
      final baseName = path
          .replaceAll('\\', '/')
          .split('/')
          .last
          .replaceAll(RegExp(r'\.[^.]+$'), '')
          .trim();
      final teamName = baseName.isEmpty ? 'Takım ${parsed.length + 1}' : baseName;
      final lines = await file.readAsLines();
      final players = <({String name, bool isGk})>[];
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final lower = line.toLowerCase();
        final isGk = lower.contains('gk') || lower.contains('kaleci');
        final name = _cleanPlayerName(
          line
              .replaceAll(RegExp(r'\bGK\b', caseSensitive: false), '')
              .replaceAll(RegExp('kaleci', caseSensitive: false), '')
              .replaceAll(',', ' ')
              .trim(),
        );
        if (name.isEmpty) continue;
        players.add((name: name, isGk: isGk));
      }
      if (players.isEmpty) continue;
      parsed.add((teamName: teamName, players: players));
    }
    if (parsed.isEmpty || !mounted) {
      _showMessage('İçe aktarılacak oyuncu bulunamadı');
      return;
    }

    // Quality choice was removed on purpose: new players always arrive with
    // random default ratings — changing a squad's strength is ONLY possible
    // from the hidden kimo@ admin page (مطلب: خيارات القوة فقط في السري).
    // ---------- Position mode ----------
    final manual = await _choosePositionModeDialog();
    if (manual == null || !mounted) return;

    // ---------- Phase 2: role plan per team (index -> plan code) ----------
    const attCycle = ['att1', 'att2', 'att3'];
    const midCycle = ['mid1', 'mid2', 'mid3', 'mid4'];
    const defCycle = ['def1', 'def2', 'def3', 'def4'];
    final rolePlans = <List<String>>[];
    for (final entry in parsed) {
      final roles = List<String>.filled(entry.players.length, 'mid2');
      final fieldIdx = <int>[];
      for (var i = 0; i < entry.players.length; i++) {
        if (entry.players[i].isGk) {
          roles[i] = 'gk';
        } else {
          fieldIdx.add(i);
        }
      }
      if (manual && fieldIdx.isNotEmpty) {
        // Ask: attackers first, then midfielders, then defenders
        // (مطلب: يحدد المهاجمين بعدين التالي والتالي).
        var pool = [...fieldIdx];
        var cancelled = false;
        for (final (title, cycle) in [
          ('Forvetler — المهاجمون', attCycle),
          ('Orta saha — الوسط', midCycle),
          ('Defans — الدفاع', defCycle),
        ]) {
          if (pool.isEmpty) break;
          final picked = await _multiPickNamesDialog(
            '${entry.teamName} — $title',
            [for (final i in pool) entry.players[i].name],
          );
          if (picked == null) {
            cancelled = true;
            break;
          }
          // [picked] holds DIALOG positions — map them back through [pool] so
          // duplicated names never drag their twins along.
          final pickedPlayerIdx = {
            for (final d in picked)
              if (d >= 0 && d < pool.length) pool[d],
          };
          var k = 0;
          final remaining = <int>[];
          for (final i in pool) {
            if (pickedPlayerIdx.contains(i)) {
              roles[i] = cycle[k % cycle.length];
              k++;
            } else {
              remaining.add(i);
            }
          }
          pool = remaining;
        }
        if (cancelled || !mounted) return;
        // Whatever is left becomes defenders.
        var k = 0;
        for (final i in pool) {
          roles[i] = defCycle[k % defCycle.length];
          k++;
        }
      } else if (fieldIdx.isNotEmpty) {
        // Random: distribute attackers / mids / defenders by ratio.
        final shuffled = [...fieldIdx]..shuffle(rng);
        final n = shuffled.length;
        final attackers = math.max(1, (n * 0.28).round());
        final mids = math.max(1, (n * 0.36).round());
        for (var k = 0; k < n; k++) {
          if (k < attackers) {
            roles[shuffled[k]] = attCycle[k % attCycle.length];
          } else if (k < attackers + mids) {
            roles[shuffled[k]] = midCycle[(k - attackers) % midCycle.length];
          } else {
            roles[shuffled[k]] =
                defCycle[(k - attackers - mids) % defCycle.length];
          }
        }
      }
      rolePlans.add(roles);
    }

    // ---------- Phase 3: create teams + players ----------
    var totalAdded = 0;
    var teamsCreated = 0;
    setState(() {
      for (var e = 0; e < parsed.length; e++) {
        final entry = parsed[e];
        final roles = rolePlans[e];
        // Team: reuse an existing one with the same name or create it.
        SavedTeamProfile team;
        final existing = data.teams
            .where((t) => !t.isDeleted && t.name == entry.teamName)
            .cast<SavedTeamProfile?>()
            .firstWhere((t) => true, orElse: () => null);
        if (existing != null) {
          team = existing;
        } else {
          team = SavedTeamProfile.create(
            ownerAccountId: data.activeAccountId,
            name: entry.teamName,
            playerIds: const [],
          );
          data.teams.add(team);
          teamsCreated++;
        }
        final hadPlayers = team.playerIds.isNotEmpty;
        // Squad pace: one base speed per team, small jitter — players end
        // up with similar speeds between 60 and 92
        // (مطلب: سرعات متقاربة بين 60 و92).
        final teamSpeedBase = 60 + rng.nextDouble() * 32;
        for (var i = 0; i < entry.players.length; i++) {
          final p = entry.players[i];
          final speed =
              (teamSpeedBase + rng.nextDouble() * 8 - 4).clamp(60, 92);
          final profile = PlayerProfile.generated(
            name: p.name,
            isGoalkeeper: roles[i] == 'gk',
            random: rng,
            speedValue: speed.toDouble(),
          );
          data.players.add(profile);
          team.playerIds.add(profile.id);
          team.roleByPlayerId[profile.id] = _roleFromPlan(roles[i]);
          totalAdded++;
        }
        if (!hadPlayers) {
          _autoFillStarters(team, data);
        }
      }
    });
    await _save();
    _showMessage(
      '$totalAdded oyuncu eklendi, $teamsCreated takım oluşturuldu',
    );
  }

  /// Multi-pick dialog: returns the set of chosen names, or null when the
  /// user cancels. Used by the manual position selection of the import.
  /// Selection is INDEX based, not name based — if two players share the
  /// same name only the exact row the user ticks is picked, never every
  /// duplicate (مطلب: الاسم المكرر ما ينحدد مع كل المكررين).
  Future<Set<int>?> _multiPickNamesDialog(
    String title,
    List<String> names,
  ) async {
    final chosen = <int>{};
    // Count duplicates so repeated names get a visible "#2" marker —
    // computed once, before the dialog, so rebuilds stay deterministic.
    final counts = <String, int>{};
    for (final name in names) {
      counts[name] = (counts[name] ?? 0) + 1;
    }
    final occurrenceNumbers = <int>[];
    final seen = <String, int>{};
    for (final name in names) {
      occurrenceNumbers.add(seen[name] = (seen[name] ?? 0) + 1);
    }
    return showDialog<Set<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff0e1c17),
          title: Text(title),
          content: SizedBox(
            width: 420,
            height: 380,
            child: ListView(
              children: [
                for (var i = 0; i < names.length; i++)
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: (counts[names[i]] ?? 0) < 2
                        ? Text(
                            names[i],
                            style: const TextStyle(fontSize: 12.5),
                          )
                        : Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: names[i]),
                                TextSpan(
                                  text: '  #${occurrenceNumbers[i]}',
                                  style: const TextStyle(
                                    color: Color(0xffffd34d),
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                    value: chosen.contains(i),
                    onChanged: (value) => setDialogState(() {
                      if (value == true) {
                        chosen.add(i);
                      } else {
                        chosen.remove(i);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop({...chosen}),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff00d084),
                foregroundColor: const Color(0xff00130c),
              ),
              child: const Text('Tamam (Seçilenler)'),
            ),
          ],
        ),
      ),
    );
  }

  /// Fills the starting eleven of a freshly imported team: goalkeepers
  /// first, then outfield players up to eleven.
  void _autoFillStarters(SavedTeamProfile team, SavedGameData data) {
    final roster = <PlayerProfile>[];
    for (final id in team.playerIds) {
      for (final p in data.players) {
        if (p.id == id) {
          roster.add(p);
          break;
        }
      }
    }
    roster.sort(
      (a, b) => (a.isGoalkeeper ? 0 : 1).compareTo(b.isGoalkeeper ? 0 : 1),
    );
    team.starterPlayerIds
      ..clear()
      ..addAll(roster.take(11).map((p) => p.id));
  }

  /// Re-rolls EVERY player of the chosen team for a quality tier
  /// (مطلب سري: فريق كامل ممتاز/جيد/متوسط/سيئ). Dayanıklılık stays high
  /// (60-99) and the whole squad shares one speed band (60-92) with tiny
  /// jitter so players run at similar pace.
  Future<void> _applyTeamQuality(SavedGameData data, String tier) async {
    final team = data.teams
        .where((t) => t.id == _adminQualityTeamId)
        .cast<SavedTeamProfile?>()
        .firstWhere((t) => true, orElse: () => null);
    if (team == null) return;
    final ok = await _confirmDialog(
      'Takım kalitesini değiştir',
      '${team.name} takımındaki tüm oyuncuların yetenekleri yeniden '
      'oluşturulacak. Devam edilsin mi?',
    );
    if (ok != true || !mounted) return;
    final rng = math.Random();
    final speedBase = 60 + rng.nextDouble() * 32;
    var changed = 0;
    setState(() {
      for (final id in team.playerIds) {
        for (final player in data.players) {
          if (player.id != id) continue;
          final speed =
              (speedBase + rng.nextDouble() * 8 - 4).clamp(60, 92);
          player.applyQualityTier(
            _qualityBase(tier, rng),
            rng,
            speedValue: speed.toDouble(),
          );
          changed++;
          break;
        }
      }
    });
    await _save();
    _showMessage('$changed oyuncunun yetenekleri güncellendi');
  }

  double _qualityBase(String quality, math.Random rng) {
    return switch (quality) {
      'mukemmel' => 84 + rng.nextDouble() * 8,
      'iyi' => 72 + rng.nextDouble() * 8,
      'orta' => 60 + rng.nextDouble() * 8,
      'kotu' => 44 + rng.nextDouble() * 10,
      _ => 48 + rng.nextDouble() * 28,
    };
  }

  PlayerRole _roleFromPlan(String plan) {
    return switch (plan) {
      'gk' => PlayerRole.goalkeeper,
      'att1' => PlayerRole.striker,
      'att2' => PlayerRole.leftWing,
      'att3' => PlayerRole.rightWing,
      'mid1' => PlayerRole.attackingMidfielder,
      'mid2' => PlayerRole.midfieldLeft,
      'mid3' => PlayerRole.midfieldRight,
      'mid4' => PlayerRole.defensiveMidfielder,
      'def1' => PlayerRole.centerBackLeft,
      'def2' => PlayerRole.centerBackRight,
      'def3' => PlayerRole.leftBack,
      'def4' => PlayerRole.rightBack,
      _ => PlayerRole.midfieldLeft,
    };
  }

  Future<bool?> _choosePositionModeDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xff0e1c17),
        title: const Text('Pozisyonlar nasıl belirlensin?'),
        content: const Text(
          'Kaleciler zaten GK işaretinden anlaşılır. '
          'Diğer oyuncuların pozisyonlarını kim belirlesin?',
          style: TextStyle(fontSize: 12.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Rastgele'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff00d084),
              foregroundColor: const Color(0xff00130c),
            ),
            child: const Text('Ben seçeceğim'),
          ),
        ],
      ),
    );
  }

  Widget _adminPlayersTab(SavedGameData data) {
    // Keep the quality-team dropdown valid if a team was deleted meanwhile.
    if (_adminQualityTeamId != null &&
        !data.teams.any((t) => !t.isDeleted && t.id == _adminQualityTeamId)) {
      _adminQualityTeamId = null;
    }
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
          // ---------- Team quality roller (kimo@ مطلب: فريق كامل ممتاز
          // أو جيد أو متوسط أو سيئ) ----------
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.stars,
                    size: 16,
                    color: Color(0xffffd34d),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Takım kalitesi:',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String>(
                      value: _adminQualityTeamId,
                      isDense: true,
                      hint: const Text('Takım seç', style: TextStyle(fontSize: 11)),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final team in data.activeTeams)
                          DropdownMenuItem(
                            value: team.id,
                            child: Text(
                              team.name,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _adminQualityTeamId = value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  for (final (tier, label, color) in const [
                    ('mukemmel', 'Mükemmel', Color(0xff2ee59d)),
                    ('iyi', 'İyi', Color(0xff7ab8ff)),
                    ('orta', 'Orta', Color(0xffffd34d)),
                    ('kotu', 'Kötü', Color(0xffff6b6b)),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: OutlinedButton(
                        onPressed: _adminQualityTeamId == null
                            ? null
                            : () => _applyTeamQuality(data, tier),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: color,
                          side: BorderSide(color: color.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 28),
                        ),
                        child: Text(label, style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                ],
              ),
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
          _adminBulkToolbar(data),
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

  /// Bulk admin tools (kimo@ only) — redesigned into two clean cards,
  /// no countries section here anymore (مطلب: صفحة مرتبة بلا ازدحام
  /// وقسم الدول راح من هون نهائياً).
  Widget _adminBulkToolbar(SavedGameData data) {
    final hasSelection = _adminSelectedPlayerIds.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===================== CARD 1: market value =====================
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xffffb020).withValues(alpha: 0.30),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.payments_outlined,
                        size: 16,
                        color: Color(0xffffb020),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Piyasa degeri',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        hasSelection
                            ? '${_adminSelectedPlayerIds.length} secili'
                            : 'oyuncu secin',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: hasSelection
                              ? const Color(0xff2ee59d)
                              : const Color(0xffffb020),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: _adminValueTeamId,
                    isDense: true,
                    isExpanded: true,
                    hint: const Text(
                      'Tüm takımlar',
                      style: TextStyle(fontSize: 12),
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(),
                    ),
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final (label, factor, flat) in const [
                        ('+Büyük', 1.10, 20000000.0),
                        ('+Küçük', 1.02, 1000000.0),
                        ('-Küçük', 0.98, -1000000.0),
                        ('-Büyük', 0.90, -20000000.0),
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: OutlinedButton(
                              onPressed: hasSelection
                                  ? () => _adjustTeamValues(
                                        data,
                                        _adminValueTeamId,
                                        factor: factor,
                                        flat: flat,
                                      )
                                  : null,
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 28),
                              ),
                              child: Text(
                                label,
                                style: const TextStyle(fontSize: 10.5),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // ===================== CARD 2: attributes =====================
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xff7ab8ff).withValues(alpha: 0.30),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.tune,
                        size: 16,
                        color: Color(0xff7ab8ff),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Ozellikler',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                        ),
                      ),
                      const Spacer(),
                      if (hasSelection)
                        TextButton(
                          onPressed: () =>
                              setState(() => _adminSelectedPlayerIds.clear()),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 24),
                          ),
                          child: const Text(
                            'Secimi temizle',
                            style: TextStyle(fontSize: 10.5),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _adminBulkAttribute,
                          isDense: true,
                          isExpanded: true,
                          hint: const Text(
                            'Özellik seç',
                            style: TextStyle(fontSize: 12),
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final (key, label) in _adminAttributeChoices)
                              DropdownMenuItem(
                                value: key,
                                child: Text(
                                  label,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _adminBulkAttribute = value),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 74,
                        child: DropdownButtonFormField<int>(
                          value: _adminBulkStep,
                          isDense: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final step in const [1, 2, 3, 5, 10])
                              DropdownMenuItem(
                                value: step,
                                child: Text('±$step'),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _adminBulkStep = value ?? 1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _adminBulkAttribute == null || !hasSelection
                              ? null
                              : () => _applyBulkAttribute(1),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xff00d084),
                            foregroundColor: const Color(0xff00130c),
                            minimumSize: const Size(0, 28),
                          ),
                          icon: const Icon(Icons.add, size: 15),
                          label: const Text(
                            'Artır',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _adminBulkAttribute == null || !hasSelection
                              ? null
                              : () => _applyBulkAttribute(-1),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 28),
                          ),
                          icon: const Icon(Icons.remove, size: 15),
                          label: const Text(
                            'Azalt',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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

  /// Simple text dialog returning a trimmed string (or null).
  Future<String?> _simpleTextDialog(String title, String label) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xff0e1c17),
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff00d084),
              foregroundColor: const Color(0xff00130c),
            ),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  /// Adds a new (empty) country to the catalogue
  /// (مطلب: اضافة دولة من صفحة الدول).
  Future<void> _addCountryNew(SavedGameData data) async {
    final name = await _simpleTextDialog('Yeni ülke', 'Ülke adı');
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() {
      if (!data.countries.contains(name.trim())) {
        data.countries.add(name.trim());
      }
    });
    await _save();
    _showMessage('Ülke eklendi: ${name.trim()}');
  }

  /// Renames a country everywhere: catalogue, players and teams
  /// (مطلب: تعديل اسم دولة).
  Future<void> _renameCountry(SavedGameData data, String oldName) async {
    final newName = await _simpleTextDialog(
      'Ülkeyi yeniden adlandır — $oldName',
      'Yeni ülke adı',
    );
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    final trimmed = newName.trim();
    if (trimmed == oldName) return;
    setState(() {
      data.countries.remove(oldName);
      if (!data.countries.contains(trimmed)) {
        data.countries.add(trimmed);
      }
      for (final player in data.players) {
        if (player.country == oldName) player.country = trimmed;
      }
      for (final team in data.teams) {
        if (team.country == oldName) team.country = trimmed;
      }
    });
    await _save();
    _showMessage('Ülke adı güncellendi: $trimmed');
  }

  /// Deletes a country: its players and teams become unassigned
  /// (مطلب: حذف دولة).
  Future<void> _deleteCountry(SavedGameData data, String name) async {
    final playerCount =
        data.players.where((p) => p.country == name).length;
    final teamCount = data.teams
        .where((t) => !t.isDeleted && t.country == name)
        .length;
    final ok = await _confirmDialog(
      'Ülkeyi sil — $name',
      '$playerCount oyuncu ve $teamCount takım "Belirsiz" durumuna '
      'düşecek. Ülke silinsin mi?',
    );
    if (ok != true || !mounted) return;
    setState(() {
      data.countries.remove(name);
      for (final player in data.players) {
        if (player.country == name) player.country = 'غير محدد';
      }
      for (final team in data.teams) {
        if (team.country == name) team.country = 'غير محدد';
      }
    });
    await _save();
    _showMessage('Ülke silindi');
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
    // Catalogue-only country pick (مطلب: الدول من صفحة الدول فقط).
    var pickedCountry = 'غير محدد';
    if (data.countries.isNotEmpty) {
      final picked = await _pickCatalogCountry(data, 'Ulke sec');
      if (picked == null || !mounted) return;
      pickedCountry = picked;
    }
    final team = SavedTeamProfile.create(
      ownerAccountId: data.activeAccountId,
      name: name,
      playerIds: const [],
    );
    setState(() {
      team.country = pickedCountry;
      data.teams.add(team);
    });
    _adminNewTeamController.clear();
    await _save();
    _showMessage('$name takimi olusturuldu');
  }

  /// Full team deletion (مطلب: حذف الفريق بالكامل من الإدارة).
  /// A clear confirmation asks whether the players go with the team:
  ///  * 'withPlayers' — team AND all its players are removed for good.
  ///  * 'teamOnly'    — the team is removed, its players become free
  ///                    agents without a team.
  Future<void> _deleteTeam(SavedTeamProfile team) async {
    final data = _data;
    if (data == null) return;
    if (data.activeTeams.length <= 1 && !team.isDeleted) {
      _showMessage('En az bir aktif takim kalmali');
      return;
    }
    final squadCount = team.playerIds.length;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff0e1c17),
        title: const Text('Takimi sil'),
        content: Text(
          '${team.name} takimi kalici olarak silinecek.\n\n'
          'Takimla birlikte oyunculari da silmek istiyor musunuz?\n'
          '($squadCount oyuncu bagli)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgec'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(ctx).pop('teamOnly'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xffffd34d),
              side: const BorderSide(color: Color(0xffffd34d)),
            ),
            icon: const Icon(Icons.person_outline, size: 16),
            label: const Text(
              'Hayir, sadece takim silinsin',
              style: TextStyle(fontSize: 12),
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop('withPlayers'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            icon: const Icon(Icons.delete_forever, size: 16),
            label: const Text(
              'Evet, takim ve oyuncular silinsin',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    final squadIds = Set.of(team.playerIds);
    setState(() {
      if (choice == 'withPlayers') {
        data.players.removeWhere((player) => squadIds.contains(player.id));
        data.bluePlayerIds.removeAll(squadIds);
        data.redPlayerIds.removeAll(squadIds);
        _manageSelectedIds.removeAll(squadIds);
        _adminSelectedPlayerIds.removeAll(squadIds);
        for (final other in data.teams) {
          if (other.id == team.id) continue;
          other.playerIds.removeAll(squadIds);
          other.starterPlayerIds.removeAll(squadIds);
          for (final id in squadIds) {
            other.roleByPlayerId.remove(id);
            other.slotByPlayerId.remove(id);
          }
        }
      }
      // HARD delete — the team is gone from the database entirely.
      data.teams.removeWhere((t) => t.id == team.id);
      data.transferRequests.removeWhere(
        (request) => request.targetTeamId == team.id,
      );
      // Repair the match selection when it referenced the removed team.
      final remaining = data.activeTeams;
      if (remaining.isNotEmpty) {
        if (data.blueTeamId == team.id) {
          final pick = remaining.first;
          data.blueTeamId = pick.id;
          data.bluePlayerIds = Set.of(pick.playerIds);
          data.blueFormation = pick.formation;
          _bluePlayStyle = pick.playStyle;
          _blueKitIndex = pick.activeKitIndex;
          _blueNameController.text = pick.name;
        }
        if (data.redTeamId == team.id) {
          final pick = remaining.firstWhere(
            (t) => t.id != data.blueTeamId,
            orElse: () => remaining.first,
          );
          data.redTeamId = pick.id;
          data.redPlayerIds = Set.of(pick.playerIds);
          data.redFormation = pick.formation;
          _redPlayStyle = pick.playStyle;
          _redKitIndex = pick.activeKitIndex;
          _redNameController.text = pick.name;
        }
      }
    });
    await _save();
    _showMessage(
      choice == 'withPlayers'
          ? 'Takim ve oyunculari silindi'
          : 'Takim silindi — oyuncular takimlarindan cikarildi',
    );
  }

  /// Team data editor: rename the team and pick its country from the
  /// catalogue (only countries added on the countries page are offered —
  // مطلب: تعديل بيانات الفريق ودولته من الكتالوج فقط).
  Future<void> _editTeamDialog(SavedGameData data, SavedTeamProfile team) async {
    final nameController = TextEditingController(text: team.name);
    // The stored country is pre-selected only when it is still part of the
    // catalogue — otherwise the field falls back to "Belirsiz" so editing
    // never silently keeps a stale value (مطلب: الدولة المحفوظة تظهر صح).
    String pickedCountry = data.countries.contains(team.country)
        ? team.country
        : 'غير محدد';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff0e1c17),
          title: Text('Takimi duzenle — ${team.name}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Takim adi',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: data.countries.contains(pickedCountry)
                      ? pickedCountry
                      : 'غير محدد',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Ulke',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'غير محدد',
                      child: Text('Belirsiz'),
                    ),
                    for (final country in data.countries)
                      DropdownMenuItem(
                        value: country,
                        child: Text(country),
                      ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => pickedCountry = value ?? 'غير محدد',
                  ),
                ),
                if (data.countries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Henuz ulke eklenmedi — once Ulkeler sayfasindan '
                      'ulke ekleyin.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xffffd34d),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
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
    final newName = nameController.text.trim();
    nameController.dispose();
    if (confirmed != true || newName.isEmpty || !mounted) return;
    setState(() {
      team.name = newName;
      team.country = pickedCountry;
      // Keep the match-selection name fields in sync.
      if (data.blueTeamId == team.id) {
        data.blueName = newName;
        _blueNameController.text = newName;
      }
      if (data.redTeamId == team.id) {
        data.redName = newName;
        _redNameController.text = newName;
      }
    });
    await _save();
    _showMessage('Takim guncellendi');
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
                  Icons.edit_outlined,
                  color: Color(0xff7ab8ff),
                  size: 18,
                ),
                onPressed: () => _editTeamDialog(data, team),
                tooltip: 'Takimi duzenle',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
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
