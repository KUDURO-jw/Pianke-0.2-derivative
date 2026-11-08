import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:random_movie/services/local_data_guard.dart';
import 'package:random_movie/services/backup_service.dart';
import 'package:random_movie/services/backup_snapshot.dart';
import 'package:random_movie/services/webdav_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 同步方向：自动判断 / 强制上传 / 强制下载。
enum WebDavSyncDirection { automatic, upload, download }

/// 同步动作：无需操作 / 上传 / 下载 / 冲突。
enum WebDavSyncAction { none, upload, download, conflict }

/// 同步过程状态。
enum WebDavSyncState { idle, working, success, conflict, failure }

/// 冲突时用户的选择：保留本地 / 保留云端。
enum WebDavConflictChoice { local, remote }

class SyncDecision {
  final WebDavSyncAction action;
  final bool localChanged;
  final bool remoteChanged;

  const SyncDecision({
    required this.action,
    required this.localChanged,
    required this.remoteChanged,
  });
}

class SyncPlanner {
  const SyncPlanner._();

  static SyncDecision decide({
    required String localChecksum,
    required String? remoteChecksum,
    required String? baseLocalChecksum,
    required String? baseRemoteChecksum,
  }) {
    if (remoteChecksum == localChecksum) {
      return const SyncDecision(
        action: WebDavSyncAction.none,
        localChanged: false,
        remoteChanged: false,
      );
    }

    final localChanged = baseLocalChecksum == null
        ? true
        : localChecksum != baseLocalChecksum;
    final remoteChanged = remoteChecksum == null
        ? baseRemoteChecksum != null
        : baseRemoteChecksum == null || remoteChecksum != baseRemoteChecksum;

    if (remoteChecksum == null) {
      return SyncDecision(
        action: remoteChanged && localChanged
            ? WebDavSyncAction.conflict
            : WebDavSyncAction.upload,
        localChanged: localChanged,
        remoteChanged: remoteChanged,
      );
    }
    if (localChanged && remoteChanged) {
      return SyncDecision(
        action: WebDavSyncAction.conflict,
        localChanged: true,
        remoteChanged: true,
      );
    }
    return SyncDecision(
      action: localChanged
          ? WebDavSyncAction.upload
          : WebDavSyncAction.download,
      localChanged: localChanged,
      remoteChanged: remoteChanged,
    );
  }
}

abstract interface class SyncCredentialStore {
  Future<String?> readPassword();
  Future<void> writePassword(String password);
  Future<void> deletePassword();
}

class SecureSyncCredentialStore implements SyncCredentialStore {
  static const _key = 'pianke_webdav_application_password';
  final FlutterSecureStorage _storage;

  SecureSyncCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> readPassword() => _storage.read(key: _key);

  @override
  Future<void> writePassword(String password) =>
      _storage.write(key: _key, value: password);

  @override
  Future<void> deletePassword() => _storage.delete(key: _key);
}

class WebDavSyncConfig {
  final String account;
  final String remoteDirectory;
  final bool hasPassword;

  const WebDavSyncConfig({
    required this.account,
    required this.remoteDirectory,
    required this.hasPassword,
  });
}

class SyncInspection {
  final BackupSnapshot local;
  final WebDavBackup? remote;
  final SyncDecision decision;

  const SyncInspection({
    required this.local,
    required this.remote,
    required this.decision,
  });
}

class WebDavSyncOutcome {
  final WebDavSyncState state;
  final WebDavSyncAction action;
  final String message;
  final SyncInspection? inspection;

  const WebDavSyncOutcome({
    required this.state,
    required this.action,
    required this.message,
    this.inspection,
  });

  bool get isSuccess => state == WebDavSyncState.success;
  bool get isConflict => state == WebDavSyncState.conflict;
}

class WebDavSyncService extends ChangeNotifier {
  static Future<WebDavSyncService>? _shared;
  static Future<WebDavSyncService> shared() => _shared ??= _createShared();
  static Future<WebDavSyncService> _createShared() async => WebDavSyncService(
    backup: BackupService(StorageService()),
    preferences: await SharedPreferences.getInstance(),
  );

  bool get isRunning => _running;
  DateTime? get lastSuccessAt =>
      DateTime.tryParse(_prefs.getString(_lastSyncKey) ?? '');
  String get statusMessage => _running
      ? '正在同步…'
      : _prefs.getString('pianke_webdav_last_message') ??
            (hasPendingConflict ? '有待处理的同步冲突' : '尚未同步');
  bool get lastAttemptFailed =>
      _prefs.getBool('pianke_webdav_last_failed') ?? false;

  Future<void> recordFailure(String message) async {
    await _prefs.setString('pianke_webdav_last_message', message);
    await _prefs.setBool('pianke_webdav_last_failed', true);
    notifyListeners();
  }

  static const _accountKey = 'pianke_webdav_account';
  static const _directoryKey = 'pianke_webdav_directory';
  static const _baseLocalKey = 'pianke_webdav_base_local_checksum';
  static const _baseRemoteKey = 'pianke_webdav_base_remote_checksum';
  static const _lastSyncKey = 'pianke_webdav_last_sync_at';
  static const _pendingConflictKey = 'pianke_webdav_pending_conflict';

  final SyncBackupStore _backup;
  final WebDavClient _client;
  final SharedPreferences _prefs;
  final SyncCredentialStore _credentials;
  bool _running = false;

  WebDavSyncService({
    required SyncBackupStore backup,
    required SharedPreferences preferences,
    WebDavClient? client,
    SyncCredentialStore? credentials,
  }) : _backup = backup,
       _prefs = preferences,
       _client = client ?? WebDavClient(),
       _credentials = credentials ?? SecureSyncCredentialStore();

  Future<WebDavSyncConfig> readConfig() async {
    final account = _prefs.getString(_accountKey) ?? '';
    final directory = _prefs.getString(_directoryKey) ?? 'Pianke';
    final password = await _credentials.readPassword();
    return WebDavSyncConfig(
      account: account,
      remoteDirectory: directory,
      hasPassword: password?.isNotEmpty == true,
    );
  }

  Future<void> saveConfig({
    required String account,
    required String remoteDirectory,
    String? applicationPassword,
  }) async {
    await _prefs.setString(_accountKey, account.trim());
    await _prefs.setString(
      _directoryKey,
      remoteDirectory.trim().replaceAll('\\', '/'),
    );
    if (applicationPassword != null) {
      if (applicationPassword.isEmpty) {
        await _credentials.deletePassword();
      } else {
        await _credentials.writePassword(applicationPassword);
      }
    }
  }

  bool get hasPendingConflict => _prefs.getBool(_pendingConflictKey) ?? false;

  Future<WebDavConfig> _loadWebDavConfig() async {
    final config = await readConfig();
    final password = await _credentials.readPassword();
    final webDavConfig = WebDavConfig(
      account: config.account,
      applicationPassword: password ?? '',
      remoteDirectory: config.remoteDirectory,
    );
    if (!webDavConfig.isComplete) {
      throw const WebDavException('请先配置坚果云账号、应用密码和远程目录');
    }
    return webDavConfig;
  }

  Future<void> testConnection() async {
    await _client.testConnection(await _loadWebDavConfig());
  }

  Future<SyncInspection> inspect({WebDavProgress? onProgress}) async {
    final config = await _loadWebDavConfig();
    final local = await _backup.createSyncSnapshot();
    final remote = await _client.download(config, onProgress: onProgress);
    final decision = SyncPlanner.decide(
      localChecksum: local.checksum,
      remoteChecksum: remote?.snapshot.checksum,
      baseLocalChecksum: _prefs.getString(_baseLocalKey),
      baseRemoteChecksum: _prefs.getString(_baseRemoteKey),
    );
    return SyncInspection(local: local, remote: remote, decision: decision);
  }

  Future<WebDavSyncOutcome> synchronize({
    WebDavSyncDirection direction = WebDavSyncDirection.automatic,
    WebDavConflictChoice? conflictChoice,
    WebDavProgress? onProgress,
    SyncInspection? expectedInspection,
  }) async {
    if (_running) {
      return const WebDavSyncOutcome(
        state: WebDavSyncState.failure,
        action: WebDavSyncAction.none,
        message: '已有同步任务正在进行',
      );
    }

    _running = true;
    notifyListeners();
    try {
      final outcome = await _performSync(
        direction: direction,
        conflictChoice: conflictChoice,
        onProgress: onProgress,
        expectedInspection: expectedInspection,
      );
      await _prefs.setString('pianke_webdav_last_message', outcome.message);
      await _prefs.setBool(
        'pianke_webdav_last_failed',
        outcome.state == WebDavSyncState.failure,
      );
      return outcome;
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<WebDavSyncOutcome> _performSync({
    required WebDavSyncDirection direction,
    WebDavConflictChoice? conflictChoice,
    WebDavProgress? onProgress,
    SyncInspection? expectedInspection,
  }) async {
    try {
      final inspection = await inspect(onProgress: onProgress);
      if (expectedInspection != null &&
          (expectedInspection.local.checksum != inspection.local.checksum ||
              expectedInspection.remote?.snapshot.checksum !=
                  inspection.remote?.snapshot.checksum)) {
        throw const WebDavException('预览后数据已变化，请重新确认本地和云端版本');
      }
      var action = inspection.decision.action;
      if (direction == WebDavSyncDirection.upload) {
        action = WebDavSyncAction.upload;
      } else if (direction == WebDavSyncDirection.download) {
        action = WebDavSyncAction.download;
      }

      if (action == WebDavSyncAction.none) {
        await _saveBase(inspection.local, inspection.remote?.snapshot);
        return WebDavSyncOutcome(
          state: WebDavSyncState.success,
          action: action,
          message: '本地和云端数据已经是最新',
          inspection: inspection,
        );
      }

      if (inspection.decision.action == WebDavSyncAction.conflict &&
          conflictChoice == null) {
        await _prefs.setBool(_pendingConflictKey, true);
        return WebDavSyncOutcome(
          state: WebDavSyncState.conflict,
          action: action,
          message: '本地和云端都发生了变化，请选择要保留的一侧',
          inspection: inspection,
        );
      }

      if (inspection.decision.action == WebDavSyncAction.conflict &&
          conflictChoice != null) {
        action = conflictChoice == WebDavConflictChoice.local
            ? WebDavSyncAction.upload
            : WebDavSyncAction.download;
      }

      final config = await _loadWebDavConfig();
      if (action == WebDavSyncAction.upload) {
        await _client.upload(config, inspection.local, onProgress: onProgress);
        await _saveBase(inspection.local, inspection.local);
        return WebDavSyncOutcome(
          state: WebDavSyncState.success,
          action: action,
          message: '已上传最新备份',
          inspection: inspection,
        );
      }

      final remote = inspection.remote;
      if (remote == null) {
        throw const WebDavException('云端没有可恢复的备份');
      }
      // 覆盖前先落一份本机兜底备份：恢复是不可撤回操作，
      // 一旦用户选错一侧，还能从文档目录里找回上一次数据。
      // 兜底失败（磁盘满、权限异常等）不应阻断恢复本身，因此单独吞掉。
      String? safetyBackup;
      try {
        safetyBackup = await _backup.createLocalSafetyBackup();
      } catch (_) {
        // 兜底备份失败，继续执行恢复。
      }
      final latestLocal = await _backup.createSyncSnapshot();
      if (LocalDataGuard.isEditing ||
          latestLocal.checksum != inspection.local.checksum) {
        throw const WebDavException('本地正在编辑或已变化，已停止覆盖，请稍后重试');
      }
      await _backup.restoreSyncSnapshot(remote.snapshot);
      await _saveBase(remote.snapshot, remote.snapshot);
      return WebDavSyncOutcome(
        state: WebDavSyncState.success,
        action: action,
        message: safetyBackup == null
            ? '已从云端恢复，但覆盖前安全备份未能保存'
            : '已从云端恢复最新备份，原数据已保存到本机安全备份',
        inspection: inspection,
      );
    } on BackupSnapshotException catch (error) {
      return WebDavSyncOutcome(
        state: WebDavSyncState.failure,
        action: WebDavSyncAction.none,
        message: error.message,
      );
    } on WebDavException catch (error) {
      return WebDavSyncOutcome(
        state: WebDavSyncState.failure,
        action: WebDavSyncAction.none,
        message: error.message,
      );
    } catch (_) {
      return const WebDavSyncOutcome(
        state: WebDavSyncState.failure,
        action: WebDavSyncAction.none,
        message: '同步失败，请稍后重试',
      );
    }
  }

  Future<WebDavSyncOutcome> synchronizeAutomatically({
    WebDavProgress? onProgress,
  }) async {
    if (LocalDataGuard.isEditing || _running) {
      return const WebDavSyncOutcome(
        state: WebDavSyncState.idle,
        action: WebDavSyncAction.none,
        message: '编辑完成后再同步',
      );
    }
    WebDavSyncConfig config;
    try {
      config = await readConfig();
    } catch (_) {
      const message = '无法读取同步配置，请在设置中检查后重试';
      await recordFailure(message);
      return const WebDavSyncOutcome(
        state: WebDavSyncState.failure,
        action: WebDavSyncAction.none,
        message: message,
      );
    }
    if (LocalDataGuard.isEditing || _running) {
      return const WebDavSyncOutcome(
        state: WebDavSyncState.idle,
        action: WebDavSyncAction.none,
        message: '编辑完成后再同步',
      );
    }
    if (!config.hasPassword || config.account.trim().isEmpty) {
      return const WebDavSyncOutcome(
        state: WebDavSyncState.idle,
        action: WebDavSyncAction.none,
        message: '未配置坚果云同步',
      );
    }
    return synchronize(onProgress: onProgress);
  }

  Future<void> clearPendingConflict() =>
      _prefs.setBool(_pendingConflictKey, false);

  Future<void> _saveBase(BackupSnapshot local, BackupSnapshot? remote) async {
    await _prefs.setString(_baseLocalKey, local.checksum);
    await _prefs.setString(_baseRemoteKey, remote?.checksum ?? local.checksum);
    await _prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
    await _prefs.setBool(_pendingConflictKey, false);
  }
}
