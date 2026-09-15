/// 회비 내역표·신청 상태 뱃지. 신청 웹과 관리자 앱이 같은 모양을 쓴다 (dart:io 금지).
library;

import 'package:flutter/material.dart';

import '../gathering.dart';
import '../theme.dart';

const _tabular = [FontFeature.tabularFigures()];

/// 사람별 금액 → 소계 → 할인 → 그룹당 → 합계.
class QuoteTable extends StatelessWidget {
  const QuoteTable(this.q, {super.key});
  final Quote q;

  @override
  Widget build(BuildContext context) {
    final extra =
        q.earlyPct > 0 || q.perRegistration > 0 || q.specialDiscount > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in q.lines)
          _Row(
            l.person.name.trim().isEmpty ? '(이름 없음)' : l.person.name,
            won(l.amount),
            sub: '${l.group.label} · ${l.stay}',
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Divider(),
        ),
        if (extra) _Row('소계', won(q.subtotal)),
        if (q.earlyPct > 0)
          _Row('사전등록 할인 ${q.earlyPct}%', '-${won(q.earlyDiscount)}'),
        if (q.perRegistration > 0)
          _Row('가족(신청 1건)당', '+${won(q.perRegistration)}'),
        if (q.specialDiscount > 0)
          _Row(
            q.discount.pct > 0 ? '지정 할인 ${q.discount.pct}%' : '지정 할인',
            '-${won(q.specialDiscount)}',
            sub: q.discount.note,
          ),
        _Row('합계', won(q.total), strong: true),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.sub, this.strong = false});
  final String label, value;
  final String? sub;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              text: label,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                fontSize: strong ? 15 : 14,
              ),
              children: [
                if (sub != null)
                  TextSpan(
                    text: '  $sub',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
            fontSize: strong ? 17 : 14,
            color: strong ? AppColors.brand : AppColors.text,
            fontFeatures: _tabular,
          ),
        ),
      ],
    ),
  );
}

class RegStatusBadge extends StatelessWidget {
  const RegStatusBadge(this.status, {super.key, this.free = false});
  final RegStatus status;

  /// 무료 집회 — '대기' / '확정'으로 보인다.
  final bool free;

  @override
  Widget build(BuildContext context) {
    final (bg, ink) = switch (status) {
      RegStatus.pending => (AppColors.warn, AppColors.warnInk),
      RegStatus.confirmed => (AppColors.ok, AppColors.ok),
      RegStatus.cancelled => (AppColors.textMuted, AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.labelFor(free: free),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink),
      ),
    );
  }
}
