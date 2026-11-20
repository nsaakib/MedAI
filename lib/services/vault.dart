import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Encrypted account-specific local files; only the key/token use OS secure storage.
class Vault {
  static const secure = FlutterSecureStorage();
  final cipher = AesGcm.with256bits();
  Future<SecretKey> key(String user) async {
    final existing = await secure.read(key: 'vault_key_$user');
    if (existing != null) return SecretKey(base64Decode(existing));
    final generated = await cipher.newSecretKey();
    await secure.write(
      key: 'vault_key_$user',
      value: base64Encode(await generated.extractBytes()),
    );
    return generated;
  }

  Future<File> file(String user) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(user))
      throw StateError('Invalid account identifier');
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/medai_$user.vault');
  }

  Future<Map<String, dynamic>?> read(String user) async {
    final f = await file(user);
    if (!await f.exists()) return null;
    final box = SecretBox.fromConcatenation(
      await f.readAsBytes(),
      nonceLength: 12,
      macLength: 16,
    );
    final bytes = await cipher.decrypt(box, secretKey: await key(user));
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  }

  Future<void> write(String user, Map<String, dynamic> data) async {
    final encrypted = await cipher.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: await key(user),
    );
    final f = await file(user), tmp = File('${(await file(user)).path}.tmp');
    await tmp.writeAsBytes(encrypted.concatenation(), flush: true);
    if (Platform.isWindows && await f.exists()) await f.delete();
    await tmp.rename(f.path);
  }

  Future<void> session(Map<String, dynamic>? value) async {
    if (value == null) {
      await secure.delete(key: 'medai_session');
    } else {
      await secure.write(key: 'medai_session', value: jsonEncode(value));
    }
  }

  Future<Map<String, dynamic>?> readSession() async {
    final s = await secure.read(key: 'medai_session');
    return s == null ? null : Map<String, dynamic>.from(jsonDecode(s) as Map);
  }
}
