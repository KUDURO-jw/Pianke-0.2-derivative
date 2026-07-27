import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:random_movie/config/api_config.dart';

class AppUpdateInfo {
  final String versionName;
  final int? versionCode;
  final String title;
  final List<String> changelog;
  final String downloadUrl;
  final bool forceUpdate;

  const AppUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.title,
    required this.changelog,
    required this.downloadUrl,
    required this.forceUpdate,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final rawChangelog = json['changelog'];
    return AppUpdateInfo(
      versionName: json['versionName']?.toString().trim() ?? '',
      versionCode: _parseInt(json['versionCode']),
      title: json['title']?.toString().trim() ?? '',
      changelog: rawChangelog is List
          ? rawChangelog
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList()
          : const [],
      downloadUrl: json['downloadUrl']?.toString().trim() ?? '',
      forceUpdate: json['forceUpdate'] == true,
    );
  }

  String get displayTitle => title.isNotEmpty ? title : '发现新版本 $versionName';

  static int? _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class UpdateCheckResult {
  final PackageInfo current;
  final AppUpdateInfo? update;

  const UpdateCheckResult({required this.current, required this.update});

  bool get hasUpdate => update != null;
}

class UpdateService {
  final Dio _dio;

  UpdateService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: ApiConfig.defaultHeaders,
              responseType: ResponseType.json,
            ),
          );

  Future<UpdateCheckResult> checkForUpdate() async {
    final current = await PackageInfo.fromPlatform();
    final url = ApiConfig.updateManifestUrl.trim();
    if (url.isEmpty) {
      throw const UpdateCheckException('更新地址未配置');
    }

    final response = await _dio.getUri(Uri.parse(url));
    final data = response.data;
    if (data is! Map) {
      throw const UpdateCheckException('更新清单格式不正确');
    }

    final info = AppUpdateInfo.fromJson(Map<String, dynamic>.from(data));
    if (info.versionName.isEmpty) {
      throw const UpdateCheckException('更新清单缺少版本号');
    }

    return UpdateCheckResult(
      current: current,
      update: _isRemoteNewer(current, info) ? info : null,
    );
  }

  bool _isRemoteNewer(PackageInfo current, AppUpdateInfo remote) {
    final currentCode = int.tryParse(current.buildNumber);
    if (currentCode != null && remote.versionCode != null) {
      return remote.versionCode! > currentCode;
    }
    return _compareVersion(remote.versionName, current.version) > 0;
  }

  int _compareVersion(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var i = 0; i < length; i++) {
      final l = i < leftParts.length ? leftParts[i] : 0;
      final r = i < rightParts.length ? rightParts[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  List<int> _versionParts(String version) {
    final core = version.split('+').first.split('-').first;
    return core
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }
}

class UpdateCheckException implements Exception {
  final String message;

  const UpdateCheckException(this.message);

  @override
  String toString() => message;
}
