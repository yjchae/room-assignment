import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// 시트 여러 장짜리 엑셀(xlsx) 파일을 만든다. 시트마다 (이름, 행들).
/// 웹 빌드에서도 돌도록 `dart:io` 없이 archive + xml 로 직접 짠다 (엑셀 패키지 없음).
///
/// 셀은 모두 인라인 문자열(`t="inlineStr"`)이다 — 공유 문자열·스타일 파일이 필요 없고,
/// `=1+1` 같은 값도 수식으로 실행되지 않고 글자 그대로 보인다.
/// ponytail: 서식 없는 최소 xlsx 다. 나이·숫자도 문자열이라 엑셀에서 숫자 정렬이 안 된다.
/// 굵은 머리글·칸 너비·숫자 셀이 필요하면 `xl/styles.xml` 과 `t="n"` 셀을 더한다.
/// 시트 이름은 엑셀 규칙(31자, `[]:*?/\` 금지)을 부르는 쪽이 지킨다 — 지금은 '전체'·'10-09(금)' 뿐이다.
Uint8List xlsxBytes(List<(String, List<List<Object?>>)> sheets) {
  final archive = Archive();
  void add(String name, String xml) =>
      archive.add(ArchiveFile.bytes(name, utf8.encode(xml)));

  const decl = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
  const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const rel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  final n = sheets.length;

  add(
    '[Content_Types].xml',
    '$decl<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '${[for (var i = 1; i <= n; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>',
  );
  add(
    '_rels/.rels',
    '$decl<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$rel/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
  );

  final book = XmlBuilder();
  book.element(
    'workbook',
    namespaceUris: {null: ns, 'r': rel},
    nest: () => book.element(
      'sheets',
      nest: () {
        for (var i = 1; i <= n; i++) {
          book.element(
            'sheet',
            attributes: {
              'name': _clean(sheets[i - 1].$1),
              'sheetId': '$i',
              'r:id': 'rId$i',
            },
          );
        }
      },
    ),
  );
  add('xl/workbook.xml', '$decl${book.buildDocument().toXmlString()}');
  add(
    'xl/_rels/workbook.xml.rels',
    '$decl<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 1; i <= n; i++) '<Relationship Id="rId$i" Type="$rel/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
        '</Relationships>',
  );

  for (var i = 1; i <= n; i++) {
    final b = XmlBuilder();
    b.element(
      'worksheet',
      namespaceUris: {null: ns},
      nest: () => b.element(
        'sheetData',
        nest: () {
          for (final row in sheets[i - 1].$2) {
            b.element(
              'row',
              nest: () {
                for (final v in row) {
                  b.element(
                    'c',
                    attributes: {'t': 'inlineStr'},
                    nest: () => b.element(
                      'is',
                      nest: () => b.element(
                        't',
                        attributes: {'xml:space': 'preserve'},
                        nest: _clean('${v ?? ''}'),
                      ),
                    ),
                  );
                }
              },
            );
          }
        },
      ),
    );
    add('xl/worksheets/sheet$i.xml', '$decl${b.buildDocument().toXmlString()}');
  }
  return ZipEncoder().encodeBytes(archive);
}

/// XML 에 넣을 수 없는 제어문자(탭·줄바꿈 말고)를 뺀다 — 들어가면 엑셀이 파일을 못 연다.
String _clean(String s) =>
    s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
