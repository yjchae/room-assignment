/// 서버 주소와 공개용 키.
///
/// 공개용(publishable) 키라 공개 저장소에 올라가도 된다 — 실제 권한은 supabase/schema.sql 의
/// RLS 가 막는다. service_role / secret 키는 절대 여기에 넣지 않는다.
library;

const supabaseUrl = 'https://ecztyjelwvboqzormzuq.supabase.co';
const supabaseKey = 'sb_publishable_qOXsKfCm4KVbpUE34nVbVA_HWRPfUSz';

/// 신청 웹 주소 (GitHub Pages, .github/workflows/deploy-web.yml).
const publicSiteUrl = 'https://yjchae.github.io/room-assignment/';

/// 운영자 웹 주소. 비밀번호 재설정 메일의 링크가 여기로 온다 —
/// Supabase 대시보드 → Authentication → URL Configuration → Redirect URLs 에 등록해야 한다.
const adminSiteUrl = '${publicSiteUrl}admin/';

/// 카톡으로 공유할 신청 링크.
String applyLink(String gatheringId) => '$publicSiteUrl?g=$gatheringId';
