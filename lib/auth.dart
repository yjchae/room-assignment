import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// 단일 관리자 비밀번호. 서버가 없으므로 이건 잠금화면이지 진짜 인증이 아니다.
/// ponytail: salt + SHA-256 1회. 로컬 파일을 읽을 수 있는 사람은 어차피 event.json도 읽는다.
/// 서버가 생기면 그때 제대로 된 인증으로 바꾼다.
class Auth {
  Auth({this.fileOverride});

  final File? fileOverride;
  String? _salt, _hash;

  bool get isSet => _salt != null && _hash != null;

  Future<File> _file() async {
    if (fileOverride != null) return fileOverride!;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/auth.json');
  }

  Future<void> load() async {
    final f = await _file();
    if (!await f.exists()) return;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _salt = j['salt'] as String?;
      _hash = j['hash'] as String?;
    } catch (_) {
      // 깨진 파일이면 비밀번호를 다시 설정하게 둔다. 앱이 안 켜지는 것보단 낫다.
      _salt = _hash = null;
    }
    if (_salt == null) _hash = null; // 반쪽짜리 파일 방어
  }

  Future<void> setPassword(String password) async {
    final r = Random.secure();
    _salt = base64Encode(List.generate(16, (_) => r.nextInt(256)));
    _hash = _digest(password, _salt!);
    await (await _file()).writeAsString(
      jsonEncode({'salt': _salt, 'hash': _hash}),
    );
  }

  bool check(String password) => isSet && _digest(password, _salt!) == _hash;

  static String _digest(String password, String salt) =>
      sha256.convert(utf8.encode('$salt$password')).toString();
}
