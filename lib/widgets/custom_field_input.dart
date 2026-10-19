/// 사용자 정의 항목 하나의 입력 칸. 형식(FieldSpec)에 맞는 모양으로 그린다.
/// 신청 웹과 운영자 참석자 편집 창이 같이 쓴다 — 웹 빌드에 들어가므로 dart:io 를 import 하지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../theme.dart';

/// 값은 형식과 상관없이 [controller] 의 글자 하나에 담는다. 켜고 끄는 형식은 켜면 [fieldOn], 끄면 ''.
/// 형식을 나중에 바꿔도 이미 받은 값은 그대로 보인다 — 보기에 없는 값은 목록 맨 아래에 따로 붙는다.
class CustomFieldInput extends StatelessWidget {
  const CustomFieldInput({
    super.key,
    required this.label,
    required this.spec,
    required this.controller,
  });

  final String label;
  final FieldSpec spec;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => switch (spec.type) {
    // 글자 칸은 controller 가 스스로 다시 그린다 — 글자마다 바깥까지 다시 그리지 않게 builder 밖에 둔다.
    FieldType.text => TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
    ),
    // 고칠 때 숫자만 남긴다 — 텍스트일 때 받은 값이 있어도 열기만 해서는 바뀌지 않는다.
    FieldType.number => TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label),
    ),
    _ => ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, v, _) => _onOffOrSelect(v.text),
    ),
  };

  Widget _onOffOrSelect(String value) => switch (spec.type) {
    FieldType.check => CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label),
      value: value.isNotEmpty,
      onChanged: (on) => _set(on == true ? fieldOn : ''),
    ),
    FieldType.toggle => Align(
      alignment: Alignment.centerLeft,
      child: FilterChip(
        label: Text(label),
        selected: value.isNotEmpty,
        onSelected: (on) => _set(on ? fieldOn : ''),
      ),
    ),
    _ => _select(value),
  };

  Widget _select(String value) {
    final stray = value.isNotEmpty && !spec.options.contains(value);
    return DropdownButtonFormField<String>(
      // 값이 바뀌면 새로 그린다 (initialValue 는 처음 한 번만 읽힌다).
      key: ValueKey(value),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(
          value: '',
          child: Text('선택 안 함', style: TextStyle(color: AppColors.textMuted)),
        ),
        for (final o in spec.options)
          DropdownMenuItem(value: o, child: Text(o)),
        if (stray)
          DropdownMenuItem(
            value: value,
            child: Text(
              '$value (목록에 없음)',
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ),
      ],
      onChanged: (o) => _set(o ?? ''),
    );
  }

  void _set(String v) => controller.text = v;
}
