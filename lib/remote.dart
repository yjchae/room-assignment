/// 서버(Supabase) 호출 모음. 관리자 앱과 신청 웹이 같이 쓴다 — dart:io 금지.
library;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'gathering.dart';
import 'models.dart' show Duty, DutyTask;

/// 화면은 이 전역만 부른다. 테스트는 [Remote] 를 상속한 가짜로 바꿔 끼운다.
Remote remote = Remote();

/// 비밀번호 재설정 메일의 링크로 들어왔다. 첫 화면이 새 비밀번호 입력으로 바뀐다.
final passwordRecovery = ValueNotifier(false);

class Remote {
  /// [init] 이 끝났는가. 테스트나 서버 준비에 실패했을 때 false — 이때 서버 호출은 [RemoteError].
  static bool ready = false;

  static Future<void> init() async {
    // 같은 프로젝트를 다른 앱도 쓰므로 이 앱 테이블·함수는 room 스키마에 있다 (supabase/schema.sql).
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseKey,
      postgrestOptions: const PostgrestClientOptions(schema: 'room'),
    );
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

  /// 로그인. 초대 링크로 왔으면 [invite] 집회의 운영자로 등록한다. 들어올 수 없는 계정이면
  /// 바로 로그아웃하고 에러 ([enter]).
  Future<void> signIn(String email, String password, {String? invite}) async {
    await _db.auth.signInWithPassword(email: email.trim(), password: password);
    await enter(invite: invite);
  }

  /// 로그인한 계정을 이 앱에 들인다. 같은 Supabase 계정을 다른 앱도 쓰므로 이 앱 가입자인지
  /// 서버(enter_app)가 가린다. 가입 직후 첫 로그인이면 서버가 여기서 가입자 표에 넣는다.
  /// 들어올 수 없으면 로그아웃하고 [RemoteError].
  Future<void> enter({String? invite}) async {
    try {
      if (invite != null) await _db.rpc('join_app', params: {'p_invite': invite});
      final s = await _db.rpc('enter_app');
      if (s == 'ok') return;
      throw RemoteError(switch (s) {
        'pending' => '가입 신청을 확인하고 있습니다. 전체 운영자가 승인하면 로그인할 수 있습니다.',
        'waiting' => '초대받은 집회의 집회관리자가 승인하면 로그인할 수 있습니다. 집회관리자에게 알리세요.',
        'rejected' => '가입 신청이 승인되지 않았습니다. 집회 담당자에게 문의하세요.',
        'helper' => '맡은 집회가 없습니다. 집회 담당자에게 초대 링크를 다시 받으세요.',
        _ => '이 앱에 가입하지 않은 계정입니다. 아래 [운영자 가입 신청]으로 먼저 가입하세요.',
      });
    } catch (_) {
      await _db.auth.signOut();
      rethrow;
    }
  }

  /// 로그인한 사람이 무엇을 할 수 있는지. [full] 이면 모든 집회, 아니면 [gatherings] 에 있는
  /// 집회만 관리한다. [canCreate] = 새 집회를 만들 수 있음(전체 운영자, 또는 승인된 가입자가 하나).
  /// [configures] = 그중 집회 설정까지 고치는 집회(만든 집회 + 보조운영자). 나머지는 운영스탭이다.
  /// [owned] = 내가 만든 집회(집회관리자). 집회 삭제와 운영자 승인·역할·해제는 여기와 [full] 만.
  ///
  /// 로그인 전이면 [RemoteError] — "맡은 집회가 하나도 없다"와 구별해야 한다.
  /// 둘을 같은 값으로 돌려주면 세션이 풀렸을 때 집회 목록이 빈 채로 "운영자 등록을 요청하세요"가 뜬다.
  Future<AdminScope> scope() async {
    if (!signedIn) {
      throw const RemoteError('로그인이 풀렸습니다. 오른쪽 위 [운영자 로그인]으로 다시 로그인하세요.');
    }
    // 서로 기다릴 필요가 없는 조회라 한꺼번에 보낸다. Future.wait 는 첫 에러를 그대로 던진다.
    final r = await Future.wait<dynamic>([
      _db.rpc('is_admin'),
      _db.rpc('can_create'),
      _db.rpc('my_gatherings'),
      _owned(),
    ]);
    final full = r[0] == true;
    final gatherings = {for (final g in r[2] as List) '$g'};
    fullAdmin = full;
    return (
      full: full,
      canCreate: r[1] == true,
      gatherings: gatherings,
      configures: full ? gatherings : await _configured(gatherings),
      owned: r[3] as Set<String>,
    );
  }

  /// 내가 만든 집회. gatherings 는 누구나 읽으므로 따로 서버 함수가 필요 없다.
  Future<Set<String>> _owned() async {
    final me = _db.auth.currentUser?.id;
    if (me == null) return {};
    final rows = await _db.from('gatherings').select('id').eq('created_by', me);
    return {for (final r in rows) '${r['id']}'};
  }

  /// ponytail: 역할(schema.sql 의 gathering_admins.role)을 넣기 전 DB 에는 my_configured 가 없다.
  ///           그때는 모두가 설정까지 고쳤으니 맡은 집회 전부로 친다. 막는 건 어차피 서버 RLS 다.
  ///           모든 운영 DB 에 schema.sql 을 다시 돌린 뒤에는 이 대비를 지워도 된다.
  Future<Set<String>> _configured(Set<String> mine) async {
    try {
      final rows = await _db.rpc('my_configured') as List;
      return {for (final g in rows) '$g'};
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202') return mine; // 함수 없음
      rethrow;
    }
  }

  /// 마지막 [scope] 결과의 [AdminScope.full]. 계정 메뉴의 [운영자 승인]을 가린다.
  bool fullAdmin = false;

  // --- 집회별 운영자 --------------------------------------------------------

  /// 이 집회의 운영자들 (전체 운영자는 빠진다 — 그들은 모든 집회를 관리한다).
  Future<List<GatheringAdmin>> gatheringAdmins(String gatheringId) async {
    final rows =
        await _db.rpc(
              'gathering_admin_list',
              params: {'p_gathering': gatheringId},
            )
            as List;
    return [
      for (final r in rows)
        (
          userId: '${r['user_id']}',
          email: '${r['email'] ?? ''}',
          role: GatheringRole.of(r['role']),
          // 승인 칸이 없던 DB 는 모두 승인된 운영자였다.
          approved: r['approved'] != false,
        ),
    ];
  }

  /// 이메일로 계정을 찾아 이 집회의 운영자로 등록한다. 계정이 없으면 에러(NO_ACCOUNT).
  Future<void> addGatheringAdmin(String gatheringId, String email) async {
    await _db.rpc(
      'add_gathering_admin',
      params: {'p_gathering': gatheringId, 'p_email': email.trim()},
    );
  }

  /// 이 집회의 운영자 초대 링크. [renew] 면 새 코드로 바꿔 예전 링크를 막는다.
  Future<String> gatheringInvite(String gatheringId, {bool renew = false}) async {
    final code = await _db.rpc(
      'gathering_invite',
      params: {'p_gathering': gatheringId, 'p_renew': renew},
    );
    return inviteLink('$code');
  }

  /// 초대 링크로 들어온 사람을 승인한다(운영스탭으로 시작). 집회관리자만(FORBIDDEN).
  Future<void> approveGatheringAdmin(String gatheringId, String userId) async {
    await _db.rpc(
      'approve_gathering_admin',
      params: {'p_gathering': gatheringId, 'p_user': userId},
    );
  }

  /// 집회별 운영자의 역할을 바꾼다. 집회관리자만 부를 수 있다(FORBIDDEN).
  Future<void> setGatheringAdminRole(
    String gatheringId,
    String userId,
    GatheringRole role,
  ) async {
    await _db.rpc(
      'set_gathering_admin_role',
      params: {
        'p_gathering': gatheringId,
        'p_user': userId,
        'p_role': role.name,
      },
    );
  }

  Future<void> removeGatheringAdmin(String gatheringId, String userId) async {
    await _db.rpc(
      'remove_gathering_admin',
      params: {'p_gathering': gatheringId, 'p_user': userId},
    );
  }

  /// 운영자 가입. 계정을 만들어 이 앱 가입자로 넣고 로그아웃한다. 초대 링크([invite])로 왔으면
  /// 바로 그 집회의 승인 대기 운영자가 되고(집회 설정의 운영자 목록에 곧장 보이고 집회관리자가
  /// 승인), 아니면 전체 운영자가 승인해야 집회관리자로 집회를 하나 만들 수 있다.
  /// 메일 확인을 켜 둔 서버면 가입 순간엔 로그인이 안 되므로, data 의 room_signup·room_invite 를
  /// 서버 enter_app 이 첫 로그인 때 읽어 같은 일을 한다.
  ///
  /// 같은 이메일로 다른 앱(같은 Supabase 프로젝트) 계정이 이미 있으면 새 계정이 안 생긴다.
  /// 그때는 입력한 비밀번호로 그 계정에 로그인해 이 앱에 가입시킨다.
  Future<void> signUp(
    String name,
    String email,
    String password, {
    String? invite,
  }) async {
    var signedIn = false;
    try {
      final res = await _db.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'name': name.trim(), 'room_signup': 'true', 'room_invite': ?invite},
        emailRedirectTo: adminSiteUrl,
      );
      signedIn = res.session != null;
      // 메일 확인을 켜 두면 이미 있는 주소도 에러 없이 identities 가 빈 가짜 계정을 돌려준다.
      if (res.user?.identities?.isEmpty ?? false) throw const _AlreadyExists();
    } on Object catch (e) {
      if (e is! _AlreadyExists &&
          !(e is AuthException && e.code == 'user_already_exists')) {
        rethrow;
      }
      try {
        await _db.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
      } on AuthException {
        throw const RemoteError(
          '이미 가입된 이메일입니다(같은 서버를 쓰는 다른 서비스 포함). 그 계정의 비밀번호를 입력하세요.',
        );
      }
      signedIn = true;
    }
    try {
      if (signedIn) await _db.rpc('join_app', params: {'p_invite': invite});
    } finally {
      await _db.auth.signOut();
    }
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

  /// 거절해도 계정은 남는다(다른 앱도 쓰는 계정일 수 있다). 이 앱에만 못 들어온다.
  Future<void> rejectAdmin(String userId) async {
    await _db.rpc('reject_admin', params: {'p_user': userId});
  }

  Future<void> signOut() {
    fullAdmin = false;
    return _db.auth.signOut();
  }

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
  /// 이미지를 먼저 지운다 — 저장소 정책(room.configures)이 집회관리자를 집회 행의 created_by 로
  /// 알아보므로, 행을 먼저 지우면 집회관리자는 이미지를 못 지워 공개 버킷에 남는다.
  Future<void> deleteGathering(Gathering g) async {
    await deleteImage(g.posterUrl);
    await deleteImage(g.backgroundUrl);
    await _db.from('gatherings').delete().eq('id', g.id);
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

  /// 운영자가 대신 받는 신청 (전화·현장 접수). 신청을 받지 않는 중에도 된다. 신청 id.
  Future<String> adminSubmit(
    String gatheringId, {
    required String phone,
    required String pin,
    required List<Person> people,
    String? depositor,
    String? memo,
    required int quoted,
  }) async => '${await _db.rpc('admin_add_registration', params: {
    ..._key(gatheringId, phone, pin),
    ..._body(people, depositor, memo, quoted),
  })}';

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

  // --- 스탭 페이지 (담당구역 할 일, 로그인 없음) --------------------------------

  /// 휴대폰+PIN 으로 내 담당구역과 할 일을 읽는다. 틀리면 null, 맡은 구역이 없으면 빈 목록.
  Future<({String name, List<StaffDuty> duties})?> lookupDuties(
    String gatheringId,
    String phone,
    String pin,
  ) async {
    final j = await _db.rpc(
      'lookup_duties',
      params: _key(gatheringId, phone, pin),
    );
    if (j is! Map) return null;
    return (
      name: '${j['name'] ?? ''}',
      duties: [
        for (final d in (j['duties'] as List? ?? []))
          if (d is Map)
            (
              duty: Duty.fromJson(Map<String, dynamic>.from(d)),
              members: [for (final m in (d['members'] as List? ?? [])) '$m'],
            ),
      ],
    );
  }

  /// 내 담당구역의 할 일 표를 통째로 저장한다. 휴대폰+PIN 이 틀리면 false.
  Future<bool> saveDutyItems(
    String gatheringId,
    String phone,
    String pin, {
    required String dutyId,
    required List<DutyTask> items,
  }) async =>
      await _db.rpc(
        'save_duty_items',
        params: {
          ..._key(gatheringId, phone, pin),
          'p_duty': dutyId,
          'p_items': [for (final t in items) t.toJson()],
        },
      ) !=
      null;

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

/// [Remote.signUp] 안에서만: 이미 있는 이메일.
class _AlreadyExists {
  const _AlreadyExists();
}

/// 스탭 페이지가 보는 내 담당구역 한 곳. [members] 는 같이 배정된 사람 이름.
typedef StaffDuty = ({Duty duty, List<String> members});

/// 운영자 가입 신청 한 건 ([Remote.adminRequests]).
typedef AdminRequest = ({String id, String email, String name, DateTime at});

/// 로그인한 사람의 권한 범위 ([Remote.scope]).
typedef AdminScope = ({
  bool full,
  bool canCreate,
  Set<String> gatherings,
  Set<String> configures,
  Set<String> owned,
});

/// 초대 링크로 들어온 집회별 운영자의 역할. 이름이 곧 서버 값(gathering_admins.role)이다.
/// 그 위의 집회관리자(집회를 만든 사람)와 수퍼어드민은 역할이 아니라 [AdminScope] 로 가린다.
enum GatheringRole {
  /// 보조운영자 — 집회 설정까지 고친다. 집회 삭제·운영자 관리는 못 한다.
  assistant('보조운영자'),

  /// 운영스탭 — 신청·참석자·방·방배정·담당구역만. 집회 설정은 못 연다.
  staff('운영스탭');

  const GatheringRole(this.label);
  final String label;

  /// 서버 값을 읽는다. 역할 칸이 없던 DB 는 모두 설정까지 고쳤다(첫 판 이름 manager 도 같다).
  static GatheringRole of(Object? v) => v == 'staff' ? staff : assistant;
}

/// 집회 하나에 등록된 운영자 ([Remote.gatheringAdmins]). [approved] 가 false 면 승인 대기.
typedef GatheringAdmin = ({
  String userId,
  String email,
  GatheringRole role,
  bool approved,
});

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
    'INVALID_ITEMS': '할 일은 200줄까지 적을 수 있습니다. 줄을 줄여서 저장하세요.',
    'ALREADY_REGISTERED': '이 번호로 이미 신청하셨습니다. [신청 조회]에서 수정하세요.',
    'TOO_MANY_ATTEMPTS':
        'PIN을 여러 번 틀려 30분간 조회가 잠겼습니다. 잠시 후 다시 시도하거나 담당자에게 문의하세요.',
    'NOT_EDITABLE': '입금이 확인됐거나 취소된 신청은 바꿀 수 없습니다. 담당자에게 문의하세요.',
    'FORBIDDEN': '권한이 없습니다. 맡은 담당구역이 맞는지, 이 집회의 운영자인지 확인하세요.',
    'NO_ACCOUNT':
        '그 이메일로 가입한 계정이 없습니다. 위 [초대 링크 복사]로 링크를 보내 가입하게 하세요.',
    'BAD_INVITE': '초대 링크가 틀렸거나 새 링크로 바뀌었습니다. 집회 담당자에게 새 링크를 받으세요.',
    'INVALID_ROLE': '운영자 역할은 보조운영자나 운영스탭 중 하나만 고를 수 있습니다.',
    // 로그인 없이(anon) 운영자 전용 테이블을 건드렸다 — 세션이 끊겼거나 로그인 전이다.
    'permission denied for table': '로그인이 풀렸습니다. 오른쪽 위 [운영자 로그인]으로 다시 로그인한 뒤 집회를 다시 여세요.',
    'NOT_FOUND': '신청을 찾지 못했습니다.',
    'registrations_active_phone': '같은 번호로 진행 중인 다른 신청이 있어 되돌릴 수 없습니다.',
    'invalid input syntax for type uuid': '잘못된 링크입니다. 받은 링크를 다시 확인하세요.',
    'Invalid login credentials': '이메일 또는 비밀번호가 다릅니다.',
    'Email not confirmed':
        '아직 메일 확인이 안 된 계정입니다. 집회 담당자에게 알리세요.',
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
