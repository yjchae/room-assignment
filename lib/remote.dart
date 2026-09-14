/// 서버(Supabase) 호출 모음. 관리자 앱과 신청 웹이 같이 쓴다 — dart:io 금지.
library;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'gathering.dart';

/// 화면은 이 전역만 부른다. 테스트는 [Remote] 를 상속한 가짜로 바꿔 끼운다.
Remote remote = Remote();

/// 비밀번호 재설정 메일의 링크로 들어왔다. 첫 화면이 새 비밀번호 입력으로 바뀐다.
final passwordRecovery = ValueNotifier(false);

class Remote {
  /// [init] 이 끝났는가. 테스트나 서버 준비에 실패했을 때 false — 이때 서버 호출은 [RemoteError].
  static bool ready = false;

  static Future<void> init() async {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
    ready = true;
    // 지난 이벤트도 다시 흘려주는 스트림이라, initialize 중에 링크를 처리했어도 여기서 받는다.
    Supabase.instance.client.auth.onAuthStateChange.listen(
      (s) {
        if (s.event == AuthChangeEvent.passwordRecovery) {
          passwordRecovery.value = true;
        }
      },
      onError: (Object e) => debugPrint('인증 링크 처리 실패: $e'), // 만료된 링크 등
    );
  }

  SupabaseClient get _db {
    if (!ready) {
      throw const RemoteError('서버에 연결되지 않았습니다. 인터넷 연결을 확인하고 앱을 다시 켜세요.');
    }
    return Supabase.instance.client;
  }

  // --- 운영자 로그인 --------------------------------------------------------

  /// 로그인한 운영자 이메일. 로그인 전이면 null.
  String? get adminEmail =>
      ready ? Supabase.instance.client.auth.currentUser?.email : null;

  bool get signedIn =>
      ready && Supabase.instance.client.auth.currentUser != null;

  /// 로그인. `admins` 에 없는 계정이면 바로 로그아웃하고 에러.
  Future<void> signIn(String email, String password) async {
    await _db.auth.signInWithPassword(email: email.trim(), password: password);
    if (await _db.rpc('is_admin') != true) {
      await _db.auth.signOut();
      throw const RemoteError('아직 승인되지 않은 계정입니다. 기존 운영자에게 승인을 요청하세요.');
    }
  }

  /// 운영자 가입 신청. 계정만 만들고 바로 로그아웃 — 기존 운영자가 승인해야 쓸 수 있다.
  /// 대시보드에서 메일 확인을 켜 두었으면 확인 메일의 링크도 눌러야 로그인된다.
  Future<void> signUp(String name, String email, String password) async {
    await _db.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'name': name.trim()},
      emailRedirectTo: adminSiteUrl,
    );
    await _db.auth.signOut();
  }

  /// 승인을 기다리는 가입 신청. 운영자만.
  Future<List<AdminRequest>> adminRequests() async {
    final rows = await _db.rpc('admin_requests') as List;
    return [
      for (final r in rows)
        (
          id: '${r['id']}',
          email: '${r['email'] ?? ''}',
          name: '${r['name'] ?? ''}',
          at: DateTime.parse('${r['created_at']}').toLocal(),
        ),
    ];
  }

  Future<void> approveAdmin(String userId) async {
    await _db.rpc('approve_admin', params: {'p_user': userId});
  }

  /// 거절하면 그 계정이 지워진다.
  Future<void> rejectAdmin(String userId) async {
    await _db.rpc('reject_admin', params: {'p_user': userId});
  }

  Future<void> signOut() => _db.auth.signOut();

  /// 비밀번호 재설정 메일. 링크를 누르면 운영자 웹이 열리고 새 비밀번호를 정한다.
  /// 없는 이메일이어도 에러가 안 난다 (계정 유무를 흘리지 않으려는 Supabase 동작).
  /// 링크는 요청한 그 브라우저에서 열어야 한다 (PKCE — 확인값이 그 브라우저에만 있다).
  Future<void> sendPasswordReset(String email) =>
      _db.auth.resetPasswordForEmail(email.trim(), redirectTo: adminSiteUrl);

  /// 비밀번호 변경. [current] 가 있으면 그 비밀번호로 다시 로그인해 본인 확인부터.
  /// 재설정 메일 링크로 들어왔을 땐 null — 메일 링크가 본인 확인이다.
  Future<void> changePassword(String? current, String next) async {
    if (current != null) {
      try {
        await _db.auth.signInWithPassword(
          email: adminEmail ?? '',
          password: current,
        );
      } on AuthException catch (e) {
        if (e.message.contains('Invalid login credentials')) {
          throw const RemoteError('지금 비밀번호가 다릅니다.');
        }
        rethrow;
      }
    }
    await _db.auth.updateUser(UserAttributes(password: next));
  }

  // --- 집회 ------------------------------------------------------------------

  Future<List<Gathering>> gatherings() async {
    final rows = await _db
        .from('gatherings')
        .select()
        .order('start_date', ascending: false);
    return [for (final r in rows) Gathering.fromRow(r)];
  }

  Future<Gathering?> gathering(String id) async {
    final r = await _db.from('gatherings').select().eq('id', id).maybeSingle();
    return r == null ? null : Gathering.fromRow(r);
  }

  /// 새 집회(id 가 '')면 만들고, 아니면 고친다. 서버에 저장된 결과를 돌려준다.
  Future<Gathering> saveGathering(Gathering g) async {
    final t = _db.from('gatherings');
    final r = g.id.isEmpty
        ? await t.insert(g.toRow()).select().single()
        : await t.update(g.toRow()).eq('id', g.id).select().single();
    return Gathering.fromRow(r);
  }

  /// 집회 삭제. 신청도 같이 지워진다(DB cascade).
  Future<void> deleteGathering(Gathering g) async {
    await _db.from('gatherings').delete().eq('id', g.id);
    await deleteImage(g.posterUrl);
    await deleteImage(g.backgroundUrl);
  }

  /// 집회별 진행 중인 신청 수 (취소 제외). 운영자만.
  Future<Map<String, ({int total, int confirmed})>> registrationCounts() async {
    final rows = await _db
        .from('registrations')
        .select('gathering_id, status')
        .neq('status', 'cancelled');
    final out = <String, ({int total, int confirmed})>{};
    for (final r in rows) {
      final id = '${r['gathering_id']}';
      final c = out[id] ?? (total: 0, confirmed: 0);
      out[id] = (
        total: c.total + 1,
        confirmed: c.confirmed + (r['status'] == 'confirmed' ? 1 : 0),
      );
    }
    return out;
  }

  // --- 이미지 ----------------------------------------------------------------

  static const _bucket = 'gathering-images';

  /// 줄여 둔 JPEG 을 올리고 공개 주소를 돌려준다. 파일명에 시각을 넣어 교체할 때마다 새 이름 —
  /// 브라우저·CDN 이 옛 이미지를 붙들고 있을 일이 없어 캐시를 1년으로 둘 수 있다.
  Future<String> uploadImage(
    String gatheringId,
    ImageKind kind,
    Uint8List jpeg,
  ) async {
    final path =
        '$gatheringId/${kind.name}-${DateTime.now().millisecondsSinceEpoch}.jpg';
    final b = _db.storage.from(_bucket);
    await b.uploadBinary(
      path,
      jpeg,
      fileOptions: const FileOptions(
        contentType: 'image/jpeg',
        cacheControl: '31536000',
      ),
    );
    return b.getPublicUrl(path);
  }

  /// 올려둔 이미지 삭제. 실패해도 넘어간다 (주인 없는 파일 하나 남는 것뿐).
  Future<void> deleteImage(String? url) async {
    final i = url?.indexOf('/$_bucket/') ?? -1;
    if (url == null || i < 0) return;
    try {
      await _db.storage.from(_bucket).remove([
        url.substring(i + _bucket.length + 2),
      ]);
    } catch (e) {
      debugPrint('이미지 삭제 실패: $e');
    }
  }

  // --- 신청 (운영자) ----------------------------------------------------------

  Future<List<Registration>> registrations(String gatheringId) async {
    final rows = await _db
        .from('registrations')
        .select()
        .eq('gathering_id', gatheringId)
        .order('created_at');
    return [for (final r in rows) Registration.fromRow(r)];
  }

  /// 운영자가 신청의 일부 칸(상태·입금액·메모 등)을 고친다.
  Future<Registration> patchRegistration(
    String id,
    Map<String, dynamic> fields,
  ) async {
    final r = await _db
        .from('registrations')
        .update(fields)
        .eq('id', id)
        .select()
        .single();
    return Registration.fromRow(r);
  }

  /// 신청을 입금 내역째 지운다. 되돌릴 수 없다.
  Future<void> deleteRegistration(String id) async {
    final rows = await _db.from('registrations').delete().eq('id', id).select();
    // 운영자가 아니면 RLS 가 에러 없이 0건만 지운다.
    if (rows.isEmpty) throw const RemoteError('삭제하지 못했습니다. 운영자로 다시 로그인해 보세요.');
  }

  Future<void> resetPin(String registrationId, String pin) async {
    await _db.rpc(
      'reset_pin',
      params: {'p_registration': registrationId, 'p_pin': pin},
    );
  }

  // --- 방배정 (운영자) --------------------------------------------------------

  /// 집회의 방배정 문서와 그 버전. 아직 저장한 적 없으면 null.
  Future<({Map<String, dynamic> data, int version})?> roomPlan(
    String gatheringId,
  ) async {
    final r = await _db
        .from('room_plans')
        .select('data, version')
        .eq('gathering_id', gatheringId)
        .maybeSingle();
    return r == null
        ? null
        : (
            data: Map<String, dynamic>.from(r['data'] as Map),
            version: (r['version'] as num).toInt(),
          );
  }

  /// 방배정 저장. [version] = 마지막으로 읽은 버전(서버에 아직 없으면 0). 새 버전을 돌려준다.
  /// 그사이 다른 기기가 저장했으면 CONFLICT 에러 ([isConflict]).
  Future<int> saveRoomPlan(
    String gatheringId,
    Map<String, dynamic> data,
    int version,
  ) async => ((await _db.rpc(
    'save_room_plan',
    params: {'p_gathering': gatheringId, 'p_data': data, 'p_version': version},
  )) as num).toInt();

  // --- 신청 (신청자, 로그인 없음) ----------------------------------------------

  /// 신청하고 신청 id 를 돌려준다.
  Future<String> submit(
    String gatheringId, {
    required String phone,
    required String pin,
    required List<Person> people,
    String? depositor,
    String? memo,
    required int quoted,
  }) async {
    final id = await _db.rpc(
      'submit_registration',
      params: {
        ..._key(gatheringId, phone, pin),
        ..._body(people, depositor, memo, quoted),
      },
    );
    return '$id';
  }

  /// 휴대폰+PIN 으로 조회. 틀리면 null.
  Future<Registration?> lookup(
    String gatheringId,
    String phone,
    String pin,
  ) async => _reg(
    await _db.rpc('lookup_registration', params: _key(gatheringId, phone, pin)),
  );

  /// 입금대기일 때 수정. 틀리면 null.
  Future<Registration?> updateMine(
    String gatheringId,
    String phone,
    String pin, {
    required List<Person> people,
    String? depositor,
    String? memo,
    required int quoted,
  }) async => _reg(
    await _db.rpc(
      'update_registration',
      params: {
        ..._key(gatheringId, phone, pin),
        ..._body(people, depositor, memo, quoted),
      },
    ),
  );

  /// 입금대기일 때 취소. 틀리면 null.
  Future<Registration?> cancelMine(
    String gatheringId,
    String phone,
    String pin,
  ) async => _reg(
    await _db.rpc('cancel_registration', params: _key(gatheringId, phone, pin)),
  );

  Map<String, dynamic> _key(String gatheringId, String phone, String pin) => {
    'p_gathering': gatheringId,
    'p_phone': digitsOnly(phone),
    'p_pin': pin,
  };

  Map<String, dynamic> _body(
    List<Person> people,
    String? depositor,
    String? memo,
    int quoted,
  ) => {
    'p_people': [for (final p in people) p.toJson()],
    'p_depositor': depositor,
    'p_memo': memo,
    'p_quoted': quoted,
  };

  Registration? _reg(Object? j) => j is Map ? Registration.fromRow(j) : null;
}

/// 운영자 가입 신청 한 건 ([Remote.adminRequests]).
typedef AdminRequest = ({String id, String email, String name, DateTime at});

class RemoteError implements Exception {
  const RemoteError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 서버 에러의 원문 메시지.
String _raw(Object e) => switch (e) {
  PostgrestException(:final message) => message,
  AuthException(:final message) => message,
  RemoteError(:final message) => message,
  _ => '$e',
};

/// 다른 기기가 먼저 저장해서 거절됐는가 ([Remote.saveRoomPlan]).
bool isConflict(Object e) => _raw(e).contains('CONFLICT');

/// 서버 에러 → 화면에 보일 문장. 서버 함수가 던지는 코드는 supabase/schema.sql 맨 위 참고.
String errorText(Object e) {
  final raw = _raw(e);
  const known = {
    'CONFLICT': '다른 기기에서 먼저 저장했습니다. 집회를 다시 열어 최신 내용을 불러오세요.',
    'CLOSED': '지금은 신청을 받지 않습니다.',
    'INVALID_PHONE': '휴대폰번호를 확인하세요. (010으로 시작하는 숫자)',
    'INVALID_PIN': 'PIN은 숫자 4자리입니다.',
    'INVALID_PEOPLE': '참석자는 1~20명까지 입력할 수 있습니다.',
    'INVALID_TEXT': '입금자명은 50자, 메모는 1000자까지입니다.',
    'INVALID_QUOTED': '금액을 계산하지 못했습니다. 새로고침 후 다시 시도하세요.',
    'ALREADY_REGISTERED': '이 번호로 이미 신청하셨습니다. [신청 조회]에서 수정하세요.',
    'TOO_MANY_ATTEMPTS':
        'PIN을 여러 번 틀려 30분간 조회가 잠겼습니다. 잠시 후 다시 시도하거나 담당자에게 문의하세요.',
    'NOT_EDITABLE': '입금이 확인됐거나 취소된 신청은 바꿀 수 없습니다. 담당자에게 문의하세요.',
    'FORBIDDEN': '운영자만 할 수 있습니다.',
    'NOT_FOUND': '신청을 찾지 못했습니다.',
    'registrations_active_phone': '같은 번호로 진행 중인 다른 신청이 있어 되돌릴 수 없습니다.',
    'invalid input syntax for type uuid': '잘못된 링크입니다. 받은 링크를 다시 확인하세요.',
    'Invalid login credentials': '이메일 또는 비밀번호가 다릅니다.',
    'User already registered': '이미 가입된 이메일입니다. 승인을 기다리는 중이면 기존 운영자에게 알리세요.',
    'Signups not allowed': '지금은 가입을 받지 않습니다. 기존 운영자에게 문의하세요.',
    'Password should': '비밀번호가 너무 짧거나 쉽습니다. 더 길게 정하세요.',
    'different from the old password': '지금 쓰는 비밀번호와 다르게 정하세요.',
    'rate limit': '메일을 너무 자주 요청했습니다. 잠시 후 다시 시도하세요.',
    'For security purposes': '메일을 너무 자주 요청했습니다. 잠시 후 다시 시도하세요.',
  };
  for (final k in known.entries) {
    if (raw.contains(k.key)) return k.value;
  }
  if (RegExp(
    'SocketException|ClientException|Failed host lookup|Connection (refused|closed|reset)|XMLHttpRequest',
  ).hasMatch(raw)) {
    return '서버에 연결하지 못했습니다. 인터넷 연결을 확인하세요.';
  }
  return raw;
}

// ---------------------------------------------------------------------------
// 이미지 줄이기 (기획서 §2.3). 무료 요금제엔 이미지 자동 변환이 없어 올리기 전에 직접 줄인다.
// ---------------------------------------------------------------------------

enum ImageKind {
  poster('포스터', 900, 80, 250 * 1024),
  background('배경', 960, 60, 80 * 1024);

  const ImageKind(this.label, this.maxWidth, this.quality, this.maxBytes);
  final String label;
  final int maxWidth;
  final int quality;
  final int maxBytes;
}

/// [kind] 규칙대로 줄여 JPEG 로 만든다. 읽을 수 없는 파일이면 null.
/// 목표 용량을 넘으면 품질을 10씩 낮춘다 (최저 50).
Uint8List? shrinkImage(Uint8List bytes, ImageKind kind) {
  img.Image? im;
  try {
    im = img.decodeImage(bytes);
  } catch (_) {
    return null; // 깨진 파일은 null 대신 예외를 던지는 디코더가 있다
  }
  if (im == null) return null;
  im = img.bakeOrientation(im); // 휴대폰 사진이 옆으로 누운 채 올라가지 않게
  if (im.width > kind.maxWidth) {
    im = img.copyResize(
      im,
      width: kind.maxWidth,
      interpolation: img.Interpolation.average,
    );
  }
  if (im.hasAlpha) {
    // JPEG 엔 투명이 없다. 흰 바탕에 얹지 않으면 투명한 곳이 검게 나온다.
    final bg = img.Image(width: im.width, height: im.height)
      ..clear(img.ColorRgb8(255, 255, 255));
    im = img.compositeImage(bg, im);
  }
  var q = kind.quality;
  var out = img.encodeJpg(im, quality: q);
  while (out.length > kind.maxBytes && q > 50) {
    q -= 10;
    out = img.encodeJpg(im, quality: q);
  }
  return out;
}

/// [shrinkImage] 를 별도 isolate 에서. 큰 사진은 1~2초 걸려서 화면이 멈추지 않게.
Future<Uint8List?> shrinkImageInBackground(Uint8List bytes, ImageKind kind) =>
    compute(_shrink, (bytes, kind));

Uint8List? _shrink((Uint8List, ImageKind) m) => shrinkImage(m.$1, m.$2);
