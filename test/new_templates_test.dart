import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/models/template_model.dart';
import 'package:ortho_quant_md/templates/foot/calcaneus_angles_template.dart';
import 'package:ortho_quant_md/templates/spine/spondylolisthesis_template.dart';
import 'package:ortho_quant_md/templates/template_registry.dart';

void main() {
  group('CalcaneusAnglesTemplate', () {
    test('Böhler angle is positive when facet is above baseline', () {
      final a = CalcaneusAnglesTemplate.bohlerAngle(
        const Offset(0, 100),
        const Offset(50, 80),
        const Offset(100, 100),
      );
      expect(a, closeTo(43.6, 0.1));
    });

    test('Böhler angle is negative when facet is depressed', () {
      final a = CalcaneusAnglesTemplate.bohlerAngle(
        const Offset(0, 100),
        const Offset(50, 110),
        const Offset(100, 100),
      );
      expect(a, lessThan(0));
    });

    test('Böhler sign is independent of foot facing direction', () {
      final a = CalcaneusAnglesTemplate.bohlerAngle(
        const Offset(100, 100),
        const Offset(50, 80),
        const Offset(0, 100),
      );
      expect(a, closeTo(43.6, 0.1));
    });
  });

  group('SpondylolisthesisTemplate', () {
    const p0 = Offset(0, 100); // S1 post-sup
    const p1 = Offset(100, 100); // S1 ant-sup
    const p2 = Offset(30, 90); // L5 post-inf
    const p3 = Offset(130, 80); // L5 ant-inf
    const p4 = Offset(0, 150); // S1 posterior wall

    test('slip percent and Meyerding grade', () {
      final template = SpondylolisthesisTemplate();
      final rect = const Rect.fromLTWH(0, 0, 200, 200);
      final points = [p0, p1, p2, p3, p4]
          .map(
            (p) =>
                ReferencePoint(Offset(p.dx / rect.width, p.dy / rect.height)),
          )
          .toList();
      final results = template.calculate(points, rect);
      expect(results, contains('Slip: 30.0%'));
      expect(results, contains('Meyerding: Grade II'));
    });

    test('segmental angle positive for lordosis', () {
      final a = SpondylolisthesisTemplate.segmentalAngle(p0, p1, p2, p3);
      expect(a, closeTo(5.7, 0.1));
    });

    test('slip angle negative (lordotic) for normal alignment', () {
      final a = SpondylolisthesisTemplate.slipAngle(p0, p1, p2, p3, p4);
      expect(a, closeTo(-5.7, 0.1));
    });

    test('slip angle positive when slipped vertebra is kyphotic', () {
      final a = SpondylolisthesisTemplate.slipAngle(
        p0,
        p1,
        p2,
        const Offset(130, 110),
        p4,
      );
      expect(a, greaterThan(0));
    });

    test('grades', () {
      expect(SpondylolisthesisTemplate.meyerdingGrade(-5), 'Retrolisthesis');
      expect(SpondylolisthesisTemplate.meyerdingGrade(80), 'Grade IV');
      expect(
        SpondylolisthesisTemplate.meyerdingGrade(120),
        'Grade V (Spondyloptosis)',
      );
    });
  });

  test('new templates are registered', () {
    expect(TemplateRegistry.getById('calcaneus_angles'), isNotNull);
    expect(TemplateRegistry.getById('spondylolisthesis'), isNotNull);
  });

  test('only the new templates carry the NEW badge', () {
    final newIds = appTemplates.where((t) => t.isNew).map((t) => t.id);
    expect(newIds, unorderedEquals(['calcaneus_angles', 'spondylolisthesis']));
  });
}
