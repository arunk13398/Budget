import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final String releaseNotes;
  final String downloadUrl;
  final String releaseUrl;
  final DateTime? publishedAt;

  const AppUpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.releaseUrl,
    this.publishedAt,
  });
}

class AppUpdateService {
  static const String repoOwner = 'arunk13398';
  static const String repoName = 'Budget';
  static const String releasesApiUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  /// In-app updates are supported across all builds directly from GitHub releases.
  static bool get isUpdateSupported => !kIsWeb;

  static String? _cachedVersion;

  /// Gets the currently installed app version (e.g., '1.0.1').
  Future<String> getCurrentVersion() async {
    if (_cachedVersion != null) return _cachedVersion!;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _cachedVersion = packageInfo.version;
      return _cachedVersion!;
    } catch (_) {
      return '1.0.6';
    }
  }

  /// Checks GitHub Releases for a newer version of the application.
  Future<AppUpdateInfo?> checkForUpdate({String? customToken}) async {
    if (kIsWeb) return null;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      final headers = <String, String>{
        'Accept': 'application/vnd.github.v3+json',
      };
      if (customToken != null && customToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $customToken';
      }

      final response = await http
          .get(Uri.parse(releasesApiUrl), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tagName = (data['tag_name'] as String? ?? '').trim();
        final releaseName = (data['name'] as String? ?? tagName).trim();
        final releaseNotes = (data['body'] as String? ?? '').trim();
        final releaseUrl = (data['html_url'] as String? ?? '').trim();
        final publishedAtStr = data['published_at'] as String?;
        final publishedAt =
            publishedAtStr != null ? DateTime.tryParse(publishedAtStr) : null;

        // Clean up the tag (e.g., 'v1.0.1' -> '1.0.1')
        final cleanTag = tagName.startsWith('v') || tagName.startsWith('V')
            ? tagName.substring(1)
            : tagName;

        final assets = (data['assets'] as List<dynamic>? ?? []);
        String downloadUrl = '';

        // Prioritize finding the .apk file from assets
        for (final asset in assets) {
          if (asset is Map<String, dynamic>) {
            final name = (asset['name'] as String? ?? '').toLowerCase();
            final url = asset['browser_download_url'] as String? ?? '';
            if (name.endsWith('.apk')) {
              downloadUrl = url;
              // Prefer github-specific APK if available
              if (name.contains('github')) {
                break;
              }
            }
          }
        }

        // Fallback to release page if no direct APK asset is found
        if (downloadUrl.isEmpty) {
          downloadUrl = releaseUrl;
        }

        final hasUpdate = _isNewer(cleanTag, currentVersion, currentBuildNumber);

        return AppUpdateInfo(
          hasUpdate: hasUpdate,
          currentVersion: currentVersion,
          latestVersion: cleanTag,
          releaseName: releaseName,
          releaseNotes: releaseNotes,
          downloadUrl: downloadUrl,
          releaseUrl: releaseUrl,
          publishedAt: publishedAt,
        );
      } else if (response.statusCode == 404) {
        debugPrint(
            'AppUpdateService: Releases endpoint returned 404 (Repo might be private or has no releases yet).');
      } else {
        debugPrint(
            'AppUpdateService: GitHub API returned status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('AppUpdateService: Error checking for update: $e');
    }

    return null;
  }

  static const MethodChannel _channel =
      MethodChannel('com.budget.planning/notifications');

  http.Client? _activeDownloadClient;

  /// Downloads the APK directly inside the app without browser redirect.
  Future<void> downloadApk({
    required String downloadUrl,
    required void Function(double progress, int receivedBytes, int totalBytes)
        onProgress,
    required void Function(String filePath) onDone,
    required void Function(String error) onError,
  }) async {
    try {
      cancelDownload();
      _activeDownloadClient = http.Client();

      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers['User-Agent'] = 'SpenderPro-AppUpdate';

      final response = await _activeDownloadClient!.send(request);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        Directory saveDir;
        try {
          final extDirs = await getExternalCacheDirectories();
          if (extDirs != null && extDirs.isNotEmpty) {
            saveDir = extDirs.first;
          } else {
            saveDir = await getTemporaryDirectory();
          }
        } catch (_) {
          saveDir = await getTemporaryDirectory();
        }
        final filePath = '${saveDir.path}/SpenderPro-update.apk';
        final file = File(filePath);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }

        final sink = file.openWrite();
        final totalBytes = response.contentLength ?? 0;
        int receivedBytes = 0;

        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          final progress = totalBytes > 0 ? (receivedBytes / totalBytes) : 0.0;
          onProgress(progress, receivedBytes, totalBytes);
        }

        await sink.flush();
        await sink.close();
        _activeDownloadClient = null;

        onDone(filePath);
      } else {
        _activeDownloadClient = null;
        onError('Download failed: HTTP ${response.statusCode}');
      }
    } catch (e) {
      _activeDownloadClient = null;
      onError('Download error: $e');
    }
  }

  /// Cancels active download if user dismisses or cancels.
  void cancelDownload() {
    try {
      _activeDownloadClient?.close();
      _activeDownloadClient = null;
    } catch (_) {}
  }

  /// Triggers native Android Package Installer for the downloaded APK.
  Future<bool> installDownloadedApk(String filePath) async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('installApk', {
          'filePath': filePath,
        });
        return result ?? false;
      } catch (e) {
        debugPrint('AppUpdateService: Error installing APK: $e');
        return false;
      }
    }
    return false;
  }

  /// Opens Google Play Protect settings in Google Play Store.
  Future<void> openPlayProtectSettings() async {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('openPlayProtectSettings');
      } catch (e) {
        debugPrint('AppUpdateService: Error opening Play Protect: $e');
      }
    }
  }

  /// Fallback: Initiates downloading/installing the updated APK via the system browser.
  Future<bool> launchUpdate(String url) async {
    try {
      final uri = Uri.parse(url);
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('AppUpdateService: Error launching update URL: $e');
      return false;
    }
  }

  /// Compares semantic versions (e.g., '1.0.1' > '1.0.0')
  bool _isNewer(String remoteTag, String localVersion, int localBuildNumber) {
    try {
      // Handle build numbers if formatted as '1.0.0+2'
      String remoteVer = remoteTag;
      int remoteBuild = 0;
      if (remoteTag.contains('+')) {
        final parts = remoteTag.split('+');
        remoteVer = parts[0];
        remoteBuild = int.tryParse(parts[1]) ?? 0;
      }

      final remoteParts =
          remoteVer.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final localParts =
          localVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLength = remoteParts.length > localParts.length
          ? remoteParts.length
          : localParts.length;

      for (int i = 0; i < maxLength; i++) {
        final r = i < remoteParts.length ? remoteParts[i] : 0;
        final l = i < localParts.length ? localParts[i] : 0;
        if (r > l) return true;
        if (r < l) return false;
      }

      // If semantic versions match, compare build numbers
      if (remoteBuild > localBuildNumber) {
        return true;
      }
    } catch (e) {
      debugPrint('AppUpdateService: Error parsing version comparison: $e');
    }
    return false;
  }
}
