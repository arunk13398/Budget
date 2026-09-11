import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionService {
  static const String _encryptionKeyStr = 'WidgetLearningAppKey_1234567890!'; // Must be 32 chars
  static final _key = encrypt.Key.fromUtf8(_encryptionKeyStr);
  static final _iv = encrypt.IV.fromUtf8('WidgetIV_1234567'); // 16 bytes constant IV
  static final _encrypter = encrypt.Encrypter(encrypt.AES(_key));

  static String encryptData(String plainText) {
    if (plainText.isEmpty) return plainText;
    try {
      final encrypted = _encrypter.encrypt(plainText, iv: _iv);
      return encrypted.base64;
    } catch (e) {
      print('Encryption error: $e');
      return plainText;
    }
  }

  static String decryptData(String encryptedText) {
    if (encryptedText.isEmpty) return encryptedText;
    try {
      final decrypted = _encrypter.decrypt64(encryptedText, iv: _iv);
      return decrypted;
    } catch (e) {
      // Return original text if it fails to decrypt (meaning it wasn't encrypted to begin with)
      // This is helpful for migrating from unencrypted to encrypted data.
      return encryptedText;
    }
  }

  /// Multi-threaded background isolate decryption & JSON decoding to avoid blocking main UI thread
  static Future<Map<String, String>> decryptAndParseMapInIsolate(String encryptedText) async {
    if (encryptedText.isEmpty) return {};
    return await compute(_decryptAndParseMapIsolateBody, encryptedText);
  }

  /// Multi-threaded background isolate JSON encoding & AES encryption
  static Future<String> parseAndEncryptMapInIsolate(Map<String, dynamic> mapData) async {
    return await compute(_parseAndEncryptMapIsolateBody, mapData);
  }
}

Map<String, String> _decryptAndParseMapIsolateBody(String encryptedText) {
  final decrypted = EncryptionService.decryptData(encryptedText);
  try {
    final decoded = jsonDecode(decrypted);
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return {};
  } catch (_) {
    try {
      final decoded = jsonDecode(encryptedText);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      return {};
    } catch (_) {
      return {};
    }
  }
}

String _parseAndEncryptMapIsolateBody(Map<String, dynamic> mapData) {
  final jsonString = jsonEncode(mapData);
  return EncryptionService.encryptData(jsonString);
}
