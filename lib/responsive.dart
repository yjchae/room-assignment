import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 창 크기 세 단계. 운영자 앱이 휴대폰·태블릿에서도 열리도록 기준을 여기 한 곳에 둔다.
/// 화면 코드에서 `MediaQuery` 폭을 숫자로 직접 비교하지 않는다 (PLAN_RESPONSIVE.md §2).
enum WindowSize {
  /// 휴대폰 (< 600). 메뉴는 Drawer, 표는 카드형.
  compact,

  /// 태블릿 (600 ~ 1199). 메뉴는 아이콘 레일.
  medium,

  /// 데스크톱 (≥ 1200). 지금까지의 화면 그대로.
  expanded;

  bool get isCompact => this == compact;
  bool get isExpanded => this == expanded;
}

/// 기준 폭. Material 3 창 크기 구분(600·840·1200)에서 840 은 뺐다 —
/// 방배정 화면이 [메뉴 148 + 왼쪽 카드 320 + 보드 ≈ 854]라 840~1199 에서도 데스크톱 골격이 안 들어간다.
const compactBelow = 600.0, expandedFrom = 1200.0;

/// 방배정처럼 [왼쪽 패널 | 보드] 로 나뉜 화면이 한 화면에 들어가는 본문 최소 폭.
/// 이보다 좁으면 두 단계(고르기 → 보드)로 나눈다. 셸 폭이 아니라 화면이 받은 폭(LayoutBuilder)과 비교한다.
const splitPaneFrom = 1100.0;

WindowSize windowSizeFor(double width) => width < compactBelow
    ? WindowSize.compact
    : width < expandedFrom
    ? WindowSize.medium
    : WindowSize.expanded;

WindowSize windowSizeOf(BuildContext context) =>
    windowSizeFor(MediaQuery.sizeOf(context).width);

/// 손가락으로 쓰는 기기인가. 휴대폰·태블릿 브라우저도 여기서 android/iOS 로 잡힌다.
/// 밀도(터치 영역)는 창 폭이 아니라 이걸로 정한다 — 데스크톱 창을 좁혀도 마우스라서 촘촘한 게 낫다.
bool get isTouchDevice => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.iOS => true,
  _ => false,
};

/// 터치 기기용 테마 보정. 데스크톱용 `VisualDensity.compact` 를 풀어 터치 영역 48 을 확보한다.
/// 휴대폰에서는 다이얼로그 바깥 여백(기본 40)을 16 으로 줄여 내용 폭을 넓힌다.
ThemeData adaptTheme(
  ThemeData theme, {
  required bool touch,
  required WindowSize size,
}) {
  if (!touch && !size.isCompact) return theme;
  return theme.copyWith(
    visualDensity: touch ? VisualDensity.standard : null,
    materialTapTargetSize: touch ? MaterialTapTargetSize.padded : null,
    dialogTheme: size.isCompact
        ? theme.dialogTheme.copyWith(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
          )
        : null,
  );
}
