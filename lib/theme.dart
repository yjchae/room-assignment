import 'package:flutter/material.dart';

/// 앱 전체 디자인 토큰. 색·모서리·여백은 전부 여기서만 정의한다.
/// 화면 코드에서 `Colors.red` 같은 걸 직접 쓰지 않는다 — 이름 없는 색은 관리가 안 된다.
///
/// 톤: 회색 바탕 위에 테두리 없는 둥근 흰 카드. 주 버튼·선택은 파랑 하나.
class AppColors {
  AppColors._();

  /// 주 버튼·선택·포커스.
  static const brand = Color(0xFF2E6FF2);
  static const brandSoft = Color(0xFFEAF1FF);

  /// 화면 바탕. 카드(흰색)는 테두리 없이 이 바탕과의 차이로만 떠 보인다.
  static const bg = Color(0xFFF2F4F6);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF9FAFB);

  /// 카드 안의 옅은 면(배정된 호수 알약 등).
  static const fill = Color(0xFFF2F4F6);
  static const border = Color(0xFFE5E8EB);
  static const text = Color(0xFF191F28);
  static const textMuted = Color(0xFF6B7684);

  /// 입력 힌트·비활성 글자.
  static const textFaint = Color(0xFFB0B8C1);

  /// 신청 웹에서 배경 사진 뒤에 까는 어두운 판.
  static const board = Color(0xFF24272D);

  static const danger = Color(0xFFE5484D);
  static const dangerSoft = Color(0xFFFFEEEE);
  static const warn = Color(0xFFF5A524);

  /// 밝은 바탕 위 경고 글자. [warn] 그대로는 흰 바탕에서 안 읽힌다.
  static const warnInk = Color(0xFF8A5A00);
  static const ok = Color(0xFF0E8A66);
}

/// 모서리 반경.
class Radii {
  Radii._();
  static const tile = 10.0;
  static const control = 10.0;
  static const card = 16.0;
}

/// 호수·인원처럼 값이 바뀌어도 열이 흔들리면 안 되는 숫자.
const tabular = [FontFeature.tabularFigures()];

/// 앱 전체 글꼴. pubspec.yaml 의 fonts 이름과 같아야 한다.
/// 컴포넌트 테마의 TextStyle 은 textTheme 과 합쳐지지 않아서 여기서도 글꼴을 직접 준다.
const appFont = 'Pretendard';

/// 방 한 칸의 상태. 판정은 [statusOf] 하나만 거친다.
/// 색은 옅게 두고 상태는 글자([statusText])로 말한다. 초과만 빨갛게.
enum RoomStatus {
  /// 아무도 없는 방.
  empty('공실', Color(0xFFFFFFFF), Color(0xFF8B95A1), Color(0xFFD1D6DB)),

  /// 사람은 있고 자리도 남은 방.
  partial('여유', Color(0xFFF2F4F6), Color(0xFF0E8A66), Color(0xFF20A77A)),

  /// 정원을 정확히 채운 방.
  full('만실', Color(0xFFE5E8EB), Color(0xFF4E5968), Color(0xFF8B95A1)),

  /// 정원을 넘긴 방. 막지는 않지만 눈에 띄어야 한다.
  over('초과', Color(0xFFFFEEEE), Color(0xFFE5484D), Color(0xFFE5484D));

  const RoomStatus(this.label, this.fill, this.ink, this.swatch);

  /// 타일 배경색.
  final Color fill;

  /// 타일 위 상태 글자색.
  final Color ink;

  /// 범례 점 색.
  final Color swatch;

  final String label;
}

/// 인원/정원으로 상태를 정한다. 화면마다 조건문을 새로 쓰지 않는다.
RoomStatus statusOf({required int used, required int capacity}) {
  if (used <= 0) return RoomStatus.empty;
  if (used > capacity) return RoomStatus.over;
  if (used == capacity) return RoomStatus.full;
  return RoomStatus.partial;
}

/// 타일에 적는 상태 글자. "2자리" / "만실" / "1명 초과" / "빈 방".
String statusText({required int used, required int capacity}) =>
    switch (statusOf(used: used, capacity: capacity)) {
      RoomStatus.empty => '빈 방',
      RoomStatus.partial => '${capacity - used}자리',
      RoomStatus.full => '만실',
      RoomStatus.over => '${used - capacity}명 초과',
    };

String genderLabel(String g) => g == 'M' ? '남' : '여';

Color genderColor(String g) =>
    g == 'M' ? const Color(0xFF3563C9) : const Color(0xFFC8407A);

OutlineInputBorder _inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(Radii.control),
  borderSide: BorderSide(color: c, width: w),
);

ButtonStyle _buttonShape() => ButtonStyle(
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
  ),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 16, vertical: 13),
  ),
  textStyle: const WidgetStatePropertyAll(
    TextStyle(
      fontFamily: appFont,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
  ),
);

/// Material 3 기본 자간(+0.25 등)은 라틴 글자 기준이라 한글이 헐거워 보인다. 전부 살짝 조인다.
TextTheme _tighten(TextTheme t) {
  TextStyle? f(TextStyle? s) => s?.copyWith(letterSpacing: -0.2);
  return TextTheme(
    displayLarge: f(t.displayLarge),
    displayMedium: f(t.displayMedium),
    displaySmall: f(t.displaySmall),
    headlineLarge: f(t.headlineLarge),
    headlineMedium: f(t.headlineMedium),
    headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge),
    titleMedium: f(t.titleMedium),
    titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge),
    bodyMedium: f(t.bodyMedium),
    bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge),
    labelMedium: f(t.labelMedium),
    labelSmall: f(t.labelSmall),
  );
}

/// 선택되면 [on], 아니면 [off]. 테마의 상태별 색은 전부 이걸로 만든다.
WidgetStateProperty<Color> _whenSelected(Color on, Color off) =>
    WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.selected) ? on : off,
    );

ThemeData buildAppTheme() {
  // 시드 색으로 만든 표면색은 파랗게 물든다(메뉴·날짜 선택창). 표면은 중립 회색으로 못 박는다.
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    primary: AppColors.brand,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.textMuted,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: AppColors.surface,
    surfaceContainerLow: AppColors.surfaceAlt,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surface,
    surfaceContainerHighest: AppColors.fill,
    secondaryContainer: AppColors.brandSoft,
    onSecondaryContainer: AppColors.brand,
    outline: const Color(0xFFD1D6DB),
    outlineVariant: AppColors.border,
    error: AppColors.danger,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: appFont,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: appFont,
    colorScheme: scheme,
    textTheme: _tighten(
      base.textTheme.apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
    ),
    scaffoldBackgroundColor: AppColors.bg,
    visualDensity: VisualDensity.compact,
    splashFactory: InkRipple.splashFactory,
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 56,
      titleTextStyle: TextStyle(
        fontFamily: appFont,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: AppColors.text,
      ),
    ),
    // 카드는 테두리·그림자 없이 흰 면으로만 뜬다.
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: _inputBorder(AppColors.border),
      enabledBorder: _inputBorder(AppColors.border),
      focusedBorder: _inputBorder(AppColors.brand, 1.5),
      labelStyle: const TextStyle(
        fontFamily: appFont,
        color: AppColors.textMuted,
        fontSize: 13,
      ),
      // 파랑은 지금 입력 중인 칸에만. 한 가지 색으로 주면 모든 칸 이름이 파랗게 뜬다.
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (s) => TextStyle(
          fontFamily: appFont,
          color: s.contains(WidgetState.error)
              ? AppColors.danger
              : s.contains(WidgetState.focused)
              ? AppColors.brand
              : AppColors.textMuted,
        ),
      ),
      hintStyle: const TextStyle(
        fontFamily: appFont,
        color: AppColors.textFaint,
        fontSize: 13,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.brand : null,
      ),
      side: const BorderSide(color: Color(0xFFD1D6DB), width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    radioTheme: RadioThemeData(
      fillColor: _whenSelected(AppColors.brand, AppColors.textFaint),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(AppColors.surface),
      trackColor: _whenSelected(AppColors.brand, const Color(0xFFD1D6DB)),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    // 알약 모양 칩. 선택되면 먹색 바탕 + 흰 글자.
    // 글자색은 반드시 상태별로 준다(WidgetStateColor) — 한 색만 주면 먹색 바탕에서 글자가 사라진다.
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.text,
      side: const BorderSide(color: AppColors.border),
      labelStyle: TextStyle(
        fontFamily: appFont,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.surface
              : AppColors.textMuted,
        ),
      ),
      checkmarkColor: AppColors.surface,
      shape: const StadiumBorder(),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
        backgroundColor: _whenSelected(AppColors.text, AppColors.surface),
        foregroundColor: _whenSelected(AppColors.surface, AppColors.textMuted),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: appFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: _buttonShape().merge(
        FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.surface,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.textFaint,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _buttonShape().merge(
        OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.border),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: _buttonShape()),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.text,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(
        fontFamily: appFont,
        fontSize: 12,
        height: 1.45,
        color: AppColors.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      textStyle: const TextStyle(
        fontFamily: appFont,
        fontSize: 13,
        color: AppColors.text,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        fontFamily: appFont,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: AppColors.text,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.text,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// 화면 안쪽 섹션 제목. 제목 + (선택) 설명 + 오른쪽 액션.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // Wrap/Row 안에 그냥 놓이는 경우가 많다. trailing 이 없으면 Expanded 를 쓰지 않는다 —
    // 폭이 무한대로 들어오는 자리에서 flex 자식을 쓰면 RenderFlex 가 죽는다.
    final label = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: AppColors.text,
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
      ],
    );
    if (trailing == null) return label;
    return Row(
      children: [
        Expanded(child: label),
        trailing!,
      ],
    );
  }
}

/// 숫자 하나를 보여주는 요약 카드. [color] 는 경고처럼 의미가 있을 때만 준다.
class StatCard extends StatelessWidget {
  const StatCard(this.label, this.value, {super.key, this.color, this.unit});
  final String label;
  final String value;
  final String? unit;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 16, 24, 18),
    constraints: const BoxConstraints(minWidth: 132),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1,
                letterSpacing: -0.8,
                fontFeatures: tabular,
                color: color ?? AppColors.text,
              ),
            ),
            if (unit != null)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Text(
                  unit!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

/// 빈 상태·안내 화면. 아이콘 + 문장 + (선택) 다음 행동 버튼.
class EmptyNotice extends StatelessWidget {
  const EmptyNotice({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: AppColors.textFaint),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, height: 1.5),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

/// 되돌릴 수 없는 동작 확인. 누르면 true.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  bool danger = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 360, child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ==
    true;

/// 성별 표시 뱃지. 목록에서 같은 모양을 쓴다.
class GenderBadge extends StatelessWidget {
  const GenderBadge(this.gender, {super.key, this.dense = false});
  final String gender;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = genderColor(gender);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 4 : 5, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        genderLabel(gender),
        style: TextStyle(
          fontSize: dense ? 10 : 11,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: c,
        ),
      ),
    );
  }
}
