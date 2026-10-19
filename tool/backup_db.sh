#!/bin/sh
# 운영 DB 백업 (public·room 스키마 통째 — 같은 프로젝트를 쓰는 다른 앱 테이블도 같이 뜬다).
# 결과는 backups/ 에 쌓인다(.gitignore 됨 — 실명·전화번호가 들어 있으니 저장소에 넣지 말 것).
#
#   sh tool/backup_db.sh
#
# DB 주소는 물어본다: 대시보드 → [Connect] → Session pooler 의 URI 에 DB 비밀번호를 채운 것.
# 되살리기: psql "<주소>" -f backups/<파일>.sql  (빈 DB 나 새 프로젝트에)
set -eu
PG=/opt/homebrew/opt/postgresql@17/bin
url=${SUPABASE_DB_URL:-}
if [ -z "$url" ]; then
  printf 'DB 주소 (대시보드에서 복사한 그대로, [YOUR-PASSWORD] 포함): '
  read -r url
fi
# 비밀번호는 주소에 넣지 않고 따로 받는다 — 특수문자(@ # / ? %)가 있으면 주소가 깨진다.
case "$url" in *'[YOUR-PASSWORD]'*)
  url=$(printf '%s' "$url" | sed 's/:\[YOUR-PASSWORD\]//')
  printf 'DB 비밀번호 (화면에 안 보임): '
  stty -echo; read -r PGPASSWORD; stty echo; echo
  export PGPASSWORD
esac
mkdir -p backups
out="backups/db-$(date +%Y%m%d-%H%M%S).sql"
"$PG/pg_dump" "$url" --schema=public --schema=room --file="$out"
echo "백업 완료: $out ($(wc -c < "$out" | tr -d ' ') bytes)"
# 테이블별 행 수 — 옮긴 뒤 다시 떠서 같은지 비교한다.
awk '/^COPY /{t=$2; n=0; next} /^\\\.$/{if (t ~ /(gatherings|registrations|room_plans|gathering_admins|admins)$/) print t, n; t=""; next} t!=""{n++}' "$out"
