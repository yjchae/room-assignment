// 공지 알림톡 발송 (Supabase Edge Function). 기획: PLAN_NOTICE.md §5.
//
// 왜 서버를 거치나: 전화번호로 카카오톡을 보내는 길은 알림톡뿐이고, 알림톡은 대행사 비밀키가
// 있어야 한다. 비밀키는 브라우저·앱에 둘 수 없다. 그래서 여기서만 들고 있는다.
//
// 배포 (CI 에 넣지 않는다 — 쓰게 되는 날 한 번 돌린다):
//   supabase functions deploy send-notice-kakao
//   supabase secrets set ALIMTALK_ENDPOINT=... ALIMTALK_TOKEN=... ALIMTALK_TEMPLATE=...
//
// 셋 중 하나라도 없으면 NOT_CONFIGURED 를 돌려준다. 앱은 그걸 받아
// "[메시지 복사]로 단톡방에 보내세요"로 안내한다 — 설정 전에도 앱은 멀쩡히 돌아간다.
//
// 대행사 API 의 요청 모양은 회사마다 다르다. 여기서 그걸 단정하지 않고,
// ALIMTALK_ENDPOINT 로 아래 모양의 JSON 을 POST 하기만 한다. 대행사 형식에 맞추는 일은
// 계약 후에 그 주소(대행사 API 또는 그 앞에 둔 내 어댑터)에서 한다.
//
//   { "template": "<ALIMTALK_TEMPLATE>", "message": "<본문>", "phones": ["01012345678", ...] }
//
// 돌려받길 기대하는 것: { "sent": <성공 건수> }. 없으면 보낸 번호 수로 친다.

// SUPABASE_URL / SUPABASE_ANON_KEY 는 Edge Function 런타임이 넣어 준다.
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

const fail = (code: string, status = 400) => json({ error: code }, status);

/// 부르는 사람의 JWT 그대로 REST 를 친다 — 권한은 이 함수가 아니라 RLS 가 판단한다.
function rest(path: string, auth: string, init: RequestInit = {}) {
  return fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: ANON_KEY,
      Authorization: auth,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return fail('METHOD_NOT_ALLOWED', 405);

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth || !SUPABASE_URL || !ANON_KEY) return fail('FORBIDDEN', 401);

  // 운영자만. schema.sql 의 is_admin() 을 그대로 쓴다 — 판단 기준이 둘이면 어긋난다.
  const who = await rest('rpc/is_admin', auth, { method: 'POST', body: '{}' });
  if (!who.ok || (await who.json()) !== true) return fail('FORBIDDEN', 403);

  let body: {
    notice_id?: string;
    target?: string;
    phones?: string[];
    message?: string;
  };
  try {
    body = await req.json();
  } catch {
    return fail('INVALID_INPUT');
  }

  const message = (body.message ?? '').trim();
  const noticeId = body.notice_id ?? '';
  const target = body.target ?? 'all';
  // 숫자만 남기고, 같은 번호는 한 번만. 대행사에 보낼 때 하이픈은 걷어낸다.
  const phones = [
    ...new Set(
      (body.phones ?? [])
        .map((p) => String(p).replace(/[^0-9]/g, ''))
        .filter((p) => /^01[0-9]{8,9}$/.test(p)),
    ),
  ];
  if (!noticeId || !message) return fail('INVALID_INPUT');
  if (phones.length === 0) return fail('NO_TARGET');

  const endpoint = Deno.env.get('ALIMTALK_ENDPOINT') ?? '';
  const token = Deno.env.get('ALIMTALK_TOKEN') ?? '';
  const template = Deno.env.get('ALIMTALK_TEMPLATE') ?? '';
  if (!endpoint || !token || !template) return fail('NOT_CONFIGURED');

  let sent = 0;
  try {
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        Authorization: token,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ template, message, phones }),
    });
    if (!res.ok) {
      console.error('알림톡 대행사 응답 실패', res.status, await res.text());
      return fail('SEND_FAILED', 502);
    }
    const out = await res.json().catch(() => ({}));
    sent = typeof out?.sent === 'number' ? out.sent : phones.length;
  } catch (e) {
    console.error('알림톡 대행사 호출 실패', e);
    return fail('SEND_FAILED', 502);
  }

  // 기록도 부른 사람 권한으로 남긴다 (RLS 가 운영자만 허용). 기록이 실패해도 이미 보낸 건 보낸 것이다.
  const log = await rest('notice_sends', auth, {
    method: 'POST',
    body: JSON.stringify({
      notice_id: noticeId,
      channel: 'alimtalk',
      target,
      count: sent,
    }),
  });
  if (!log.ok) console.error('보낸 기록 실패', log.status, await log.text());

  return json({ sent });
});
