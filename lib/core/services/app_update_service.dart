import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
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

  /// GitHub variant supports in-app updates directly from GitHub Releases.
  /// Play Store variants are excluded per Google Play Store update policy.
  static bool get isUpdateSupported => appFlavor != 'playstore';

  static String? _cachedVersion;

  /// Gets the currently installed app version (e.g., '1.0.1').
  Future<String> getCurrentVersion() async {
    if (_cachedVersion != null) return _cachedVersion!;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _cachedVersion = packageInfo.version;
      return _cachedVersion!;
    } catch (_) {
      return '1.0.1';
    }
  }

  /// Checks GitHub Releases for a newer version of the application.
  Future<AppUpdateInfo?> checkForUpdate({String? customToken}) async {
    if (kIsWeb || !isUpdateSupported) return null;

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

  /// Initiates downloading/installing the updated APK via the system browser/downloader.
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
