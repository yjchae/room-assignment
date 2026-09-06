import 'package:flutter/material.dart';

/// 앱 전체 디자인 토큰. 색·모서리·여백은 전부 여기서만 정의한다.
/// 화면 코드에서 `Colors.red` 같은 걸 직접 쓰지 않는다 — 이름 없는 색은 관리가 안 된다.
class AppColors {
  AppColors._();

  static const brand = Color(0xFF4F46E5);
  static const brandSoft = Color(0xFFEEF0FF);

  static const bg = Color(0xFFF4F6FA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF8F9FC);
  static const border = Color(0xFFE3E6EF);
  static const text = Color(0xFF1B1F2A);
  static const textMuted = Color(0xFF6B7280);

  /// 방 보드 배경. 타일 색이 튀어 보이도록 일부러 어두운 판 위에 올린다.
  static const board = Color(0xFF2B3040);
  static const boardLine = Color(0xFF3F4559);
  static const boardText = Color(0xFFC7CCDA);
  static const boardTextDim = Color(0xFF8B92A6);

  static const danger = Color(0xFFE5484D);
  static const warn = Color(0xFFF5A524);
  static const ok = Color(0xFF16A34A);
  static const info = Color(0xFF21A8CD);
}

/// 모서리 반경. 타일 < 버튼/입력 < 카드/보드 순으로 커진다.
class Radii {
  Radii._();
  static const tile = 10.0;
  static const control = 10.0;
  static const card = 14.0;
}

/// 방 한 칸의 상태. 색이 곧 상태이므로 판정은 [statusOf] 하나만 거친다.
enum RoomStatus {
  /// 아무도 없는 방.
  empty('공실', Color(0xFFFFFFFF), Color(0xFF20242F), Color(0xFFCED3E0)),

  /// 사람은 있고 자리도 남은 방.
  partial('여유', Color(0xFF21A8CD), Color(0xFF04303C), Color(0xFF21A8CD)),

  /// 정원을 정확히 채운 방.
  full('만실', Color(0xFFF5A524), Color(0xFF4A2C00), Color(0xFFF5A524)),

  /// 정원을 넘긴 방. 막지는 않지만 눈에 띄어야 한다.
  over('초과', Color(0xFFE5484D), Color(0xFFFFFFFF), Color(0xFFE5484D));

  const RoomStatus(this.label, this.fill, this.ink, this.swatch);

  /// 타일 배경색.
  final Color fill;

  /// 타일 위 글자색. [fill] 대비를 맞춰 둔 값이다.
  final Color ink;

  /// 범례·요약에 쓰는 점 색. 흰 타일은 배경과 안 구분되므로 따로 둔다.
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

String genderLabel(String g) => g == 'M' ? '남' : '여';

Color genderColor(String g) =>
    g == 'M' ? const Color(0xFF2563EB) : const Color(0xFFDB2777);

OutlineInputBorder _inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(Radii.control),
  borderSide: BorderSide(color: c, width: w),
);

ButtonStyle _buttonShape() => ButtonStyle(
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
  ),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  ),
  textStyle: const WidgetStatePropertyAll(
    TextStyle(fontWeight: FontWeight.w600),
  ),
);

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    primary: AppColors.brand,
    surface: AppColors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    visualDensity: VisualDensity.compact,
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
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
    ),
    // 그림자 대신 1px 테두리로 면을 나눈다. 밀도 높은 화면에서 그림자는 지저분해진다.
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: _inputBorder(AppColors.border),
      enabledBorder: _inputBorder(AppColors.border),
      focusedBorder: _inputBorder(AppColors.brand, 1.6),
      labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      floatingLabelStyle: const TextStyle(color: AppColors.brand),
      hintStyle: const TextStyle(color: Color(0xFFA6ADBD), fontSize: 13),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.brandSoft,
      side: const BorderSide(color: AppColors.border),
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.text),
      secondaryLabelStyle: const TextStyle(
        fontSize: 13,
        color: AppColors.brand,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.brandSoft,
      selectedIconTheme: IconThemeData(color: AppColors.brand, size: 22),
      unselectedIconTheme: IconThemeData(color: AppColors.textMuted, size: 22),
      selectedLabelTextStyle: TextStyle(
        color: AppColors.brand,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: AppColors.textMuted,
        fontSize: 12,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: _buttonShape()),
    outlinedButtonTheme: OutlinedButtonThemeData(style: _buttonShape()),
    textButtonTheme: TextButtonThemeData(style: _buttonShape()),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control),
      ),
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
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
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

/// 숫자 하나를 보여주는 요약 카드.
class StatCard extends StatelessWidget {
  const StatCard(this.label, this.value, {super.key, this.color, this.unit});
  final String label;
  final String value;
  final String? unit;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
    constraints: const BoxConstraints(minWidth: 116),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.card),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color ?? AppColors.textMuted,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1,
                color: color ?? AppColors.text,
              ),
            ),
            if (unit != null)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  unit!,
                  style: const TextStyle(
                    fontSize: 13,
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

/// 성별 표시 뱃지. 방 타일·목록에서 같은 모양을 쓴다.
class GenderBadge extends StatelessWidget {
  const GenderBadge(this.gender, {super.key, this.dense = false});
  final String gender;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = genderColor(gender);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 4 : 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        genderLabel(gender),
        style: TextStyle(
          fontSize: dense ? 10 : 11,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: c,
        ),
      ),
    );
  }
}
