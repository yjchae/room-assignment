// 공지 모델과 메시지 만들기. 화면 없이 도는 부분만 본다 (기획: PLAN_NOTICE.md).
import 'package:flutter_test/flutter_test.dart';
import 'package:room_assignment/gathering.dart';

Gathering g() => Gathering(
  id: 'g1',
  name: '가을수련회',
  start: DateTime(2026, 10, 9),
  end: DateTime(2026, 10, 11),
);

Notice notice({
  String id = 'n1',
  String title = '준비물 안내',
  String body = '세면도구를 챙겨 오세요.',
  bool pinned = false,
  bool published = true,
  DateTime? at,
}) => Notice(
  id: id,
  gatheringId: 'g1',
  title: title,
  body: body,
  pinned: pinned,
  published: published,
  createdAt: at ?? DateTime(2026, 9, 10),
);

Registration reg(String id, String phone, RegStatus status, int people) =>
    Registration(
      id: id,
      gatheringId: 'g1',
      phone: phone,
      people: [
        for (var i = 0; i < people; i++)
          Person(name: '$id-$i', gender: 'M', birthYear: 1990),
      ],
      status: status,
      createdAt: DateTime(2026, 9, 10),
    );

void main() {
  group('공지 메시지', () {
    test('집회 이름 · 제목 · 본문 · 공지 링크 순서', () {
      final m = noticeMessage(g(), notice());
      expect(m, startsWith('[가을수련회] 준비물 안내\n'));
      expect(m, contains('세면도구를 챙겨 오세요.'));
      expect(m, contains('?g=g1&n=n1'));
      // 카카오톡에 그대로 붙여넣는 글이라 꾸밈이 들어가면 안 된다.
      expect(m, isNot(contains('**')));
      expect(m, isNot(contains('|')));
    });

    test('본문이 비면 빈 줄이 겹치지 않는다', () {
      final m = noticeMessage(g(), notice(body: ''));
      expect(m, isNot(contains('\n\n\n')));
      expect(m.split('\n').first, '[가을수련회] 준비물 안내');
    });

    test('앞뒤 공백은 정리한다', () {
      final m = noticeMessage(g(), notice(title: '  공지  ', body: '  본문  '));
      expect(m, startsWith('[가을수련회] 공지\n'));
      expect(m, contains('\n본문\n'));
    });
  });

  group('공지 링크', () {
    test('저장한 공지는 그 공지가 펼쳐지는 주소', () {
      expect(noticeLink(g(), notice()), endsWith('?g=g1&n=n1'));
    });

    test('아직 저장 안 한 공지는 집회 페이지 주소 그대로', () {
      expect(noticeLink(g(), notice(id: '')), endsWith('?g=g1'));
      expect(noticeMessage(g(), notice(id: '')), contains('?g=g1'));
    });
  });

  group('공지 정렬', () {
    test('고정이 먼저, 그다음 최신순', () {
      final sorted = sortedNotices([
        notice(id: 'a', at: DateTime(2026, 9, 12)),
        notice(id: 'b', at: DateTime(2026, 9, 10), pinned: true),
        notice(id: 'c', at: DateTime(2026, 9, 14)),
      ]);
      expect([for (final n in sorted) n.id], ['b', 'c', 'a']);
    });
  });

  group('보낼 대상', () {
    final regs = [
      reg('r1', '01012345678', RegStatus.pending, 2),
      reg('r2', '01099998888', RegStatus.confirmed, 1),
      reg('r3', '01077776666', RegStatus.cancelled, 3),
      reg('r4', '01011112222', RegStatus.confirmed, 4),
    ];

    test('전체는 취소를 뺀다', () {
      expect(noticeTargets(regs, NoticeTarget.all).length, 3);
      expect(noticeTargets(regs, NoticeTarget.confirmed).length, 2);
      expect(noticeTargets(regs, NoticeTarget.pending).length, 1);
    });

    test('번호는 신청 순서대로, 숫자만 (서버로 그대로 보낸다)', () {
      expect(noticePhones(regs, NoticeTarget.confirmed), [
        '01099998888',
        '01011112222',
      ]);
    });

    test('같은 번호가 여러 건이어도 한 번만', () {
      final twice = [
        reg('r1', '01012345678', RegStatus.cancelled, 1),
        reg('r2', '01012345678', RegStatus.pending, 1),
      ];
      expect(noticePhones(twice, NoticeTarget.all), ['01012345678']);
    });

    test('무료 집회면 대상 이름이 확정·대기로 바뀐다', () {
      expect(NoticeTarget.confirmed.labelFor(free: false), '입금확인');
      expect(NoticeTarget.confirmed.labelFor(free: true), '확정');
      expect(NoticeTarget.all.labelFor(free: true), '전체');
    });
  });

  group('서버 행 읽고 쓰기', () {
    test('toRow 는 id·시각을 넣지 않고 공백을 정리한다', () {
      final row = notice(title: ' 제목 ', body: ' 본문 ').toRow();
      expect(row['title'], '제목');
      expect(row['body'], '본문');
      expect(row.containsKey('id'), isFalse);
      expect(row.containsKey('created_at'), isFalse);
    });

    test('fromRow: 빠진 칸은 기본값 (published 는 기본 공개)', () {
      final n = Notice.fromRow({
        'id': 'n9',
        'gathering_id': 'g1',
        'title': '공지',
        'created_at': '2026-09-10T01:00:00Z',
      });
      expect(n.body, '');
      expect(n.pinned, isFalse);
      expect(n.published, isTrue);
      expect(n.updatedAt, isNull);
    });

    test('돌린 기록 한 줄', () {
      final s = NoticeSend.fromRow({
        'channel': 'copy',
        'target': 'confirmed',
        'count': 32,
        'sent_at': '2026-09-15T05:03:00Z',
      });
      expect(s.summary(free: false), '메시지 복사 · 입금확인 32명');
      expect(s.summary(free: true), '메시지 복사 · 확정 32명');
    });

    test('채널은 셋 다 복사 — 돈이 드는 통로는 없다', () {
      expect(NoticeChannel.values.map((c) => c.name), [
        'copy',
        'phones',
        'link',
      ]);
    });

    test('모르는 값이 와도 죽지 않는다', () {
      final s = NoticeSend.fromRow({'channel': '비둘기', 'target': '아무나'});
      expect(s.channel, NoticeChannel.copy);
      expect(s.target, NoticeTarget.all);
    });
  });
}
