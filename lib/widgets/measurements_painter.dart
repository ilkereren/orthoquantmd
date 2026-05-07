import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/services/settings_service.dart';
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

class MeasurementsPainter extends CustomPainter {
  final List<MeasurementModel> measurements;
  final Rect imageRect;
  final double scale;
  final double strokeWidth;
  final double textSize;
  final bool isTextBold;
  final double? pixelsToMm;

  MeasurementsPainter(
    this.measurements, {
    required this.imageRect, 
    required this.scale, 
    this.strokeWidth = 2.0,
    required this.textSize,
    required this.isTextBold,
    this.pixelsToMm,
    this.modularTemplate, // Receive it
  });

  final MeasurementTemplateBase? modularTemplate;

  @override
  void paint(Canvas canvas, Size size) {
    if (imageRect.isEmpty) return;
    
    // NEW: Modular Template Painting
    if (modularTemplate != null) {
       // Aggregate all points (assuming they are landmarks)
       // This is a simplification; ideally we track which measurement belongs to the template.
       // But for the FAI template pilot, all single points are landmarks.
       List<ReferencePoint> allPoints = [];
       for (final m in measurements) {
           if (m.type == MeasurementType.point) {
               allPoints.addAll(m.points);
           }
       }
       
       // Delegate to Template
       if (allPoints.isNotEmpty) {
           modularTemplate!.paint(canvas, allPoints, scale, Paint()..color = const Color(0xFF00FF00)..strokeWidth=strokeWidth, imageRect);
       }
       // Ghosting Fix: We want to skip "Result Measurements" which are duplicate representations.
       // But we MUST draw "Calibration" or other manual measurements if they exist.
    }

    for (final m in measurements) {
      // 2. Skip "Ghost" Results
    // Heuristic: If Template Active, don't draw template-generated results UNLESS it is Calibration.
    if (modularTemplate != null && m.isTemplateResult && m.type != MeasurementType.calibration) continue;

      _paintMeasurement(canvas, m);

      // 3. Draw Points (REPLACES widget-based loop for performance)
      _paintMeasurementPoints(canvas, m);
    }
  }

  void _paintMeasurementPoints(Canvas canvas, MeasurementModel m) {
    if (m.points.isEmpty || m.isTemplateResult) return; // Hide results points per user request

    final isLandmark = (modularTemplate != null && m.type == MeasurementType.point);
    final baseSize = SettingsService().landmarkSize * 5.0;
    final radius = (baseSize / 2) / scale;

    // Paints
    final landmarkPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    
    final landmarkBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / scale;

    final standardPaint = Paint()
      ..color = m.type == MeasurementType.calibration ? Colors.white : m.color.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    final standardBorderPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / scale;

    for (final p in m.points) {
      final screenPos = Offset(
        imageRect.left + p.position.dx * imageRect.width,
        imageRect.top + p.position.dy * imageRect.height,
      );

      if (isLandmark) {
        canvas.drawCircle(screenPos, radius, landmarkPaint);
        canvas.drawCircle(screenPos, radius, landmarkBorderPaint);
      } else {
        canvas.drawCircle(screenPos, radius, standardPaint);
        canvas.drawCircle(screenPos, radius, standardBorderPaint);
      }
    }
  }
  
  void _drawCustomLine(Canvas canvas, Offset p1, Offset p2, Paint paint, {bool isDashed = false, bool isInfinite = false}) {
    // 1. Draw the core segment (between p1 and p2)
    if (isDashed) {
      _drawDashedLine(canvas, p1, p2, paint);
    } else {
      canvas.drawLine(p1, p2, paint);
    }

    // 2. Draw extensions if infinite
    if (isInfinite) {
      final infPoints = GeometryUtils.getInfiniteLinePoints(p1, p2, imageRect);
      if (infPoints != null && infPoints.length >= 2) {
        final v = p2 - p1;
        if (v.distance > 0) {
          for (final b in infPoints) {
            // Check if boundary point b is "behind" p1
            final vP1B = b - p1;
            final dotP1 = vP1B.dx * v.dx + vP1B.dy * v.dy;
            if (dotP1 < -0.01) {
              _drawDashedLine(canvas, p1, b, paint);
              continue;
            }

            // Check if boundary point b is "ahead" of p2
            final vP2B = b - p2;
            final dotP2 = vP2B.dx * v.dx + vP2B.dy * v.dy;
            if (dotP2 > 0.01) {
              _drawDashedLine(canvas, p2, b, paint);
            }
          }
        }
      }
    }
  }
  
  
  void _paintMeasurement(Canvas canvas, MeasurementModel m) {
    if (m.points.isEmpty) return;

    final paint = Paint()
      ..color = m.color
      ..strokeWidth = (m.type == MeasurementType.calibration ? 2.0 : strokeWidth) / scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    Offset denormalize(Offset p) {
       if (imageRect.isEmpty) return p;
       return Offset(
         imageRect.left + p.dx * imageRect.width, 
         imageRect.top + p.dy * imageRect.height
       );
    }
    
    final points = m.points.map((rp) => denormalize(rp.position)).toList();
    final labelPos = m.labelPosition != null ? denormalize(m.labelPosition!) : null;

    final pointRadius = SettingsService().landmarkSize / scale;
    final crossSize = (SettingsService().landmarkSize + 1.0) / scale;

    if (points.length >= 2) {
       if (m.type == MeasurementType.calibration) {
          _drawDashedLine(canvas, points[0], points[1], paint);
       } else if (m.type == MeasurementType.angle3Point && points.length >= 3) {
          _drawCustomLine(canvas, points[0], points[1], paint, isDashed: m.isDashed, isInfinite: m.isInfinite);
          _drawCustomLine(canvas, points[1], points[2], paint, isDashed: m.isDashed, isInfinite: m.isInfinite);
          _drawAngleArc(canvas, paint, points[0], points[1], points[2]);
          
       } else if (m.type == MeasurementType.cobbAngle && points.length >= 4) {
          final p1 = points[0];
          final p2 = points[1];
          final p3 = points[2];
          final p4 = points[3];
          
          // Dynamic Cobb Painter Logic
          // Top Line
          canvas.drawLine(p1, p2, paint);
          // Bot Line
          canvas.drawLine(p3, p4, paint);
          
          // Extension Lines (Dotted)
          // Calculate Intersect
          final i = GeometryUtils.getLineIntersection(p1, p2, p3, p4);
          if (i != null) {
             final dottedPaint = Paint()
               ..color = m.color.withValues(alpha: 0.7)
               ..style = PaintingStyle.stroke
               ..strokeWidth = (strokeWidth * 0.5) / scale // Thinner extension
               ..strokeCap = StrokeCap.round;
               
             _drawDashedLine(canvas, (p1+p2)/2, i, dottedPaint);
             _drawDashedLine(canvas, (p3+p4)/2, i, dottedPaint);
          }
          
          // Highlight Endplates?
          paint.strokeWidth = (strokeWidth + 2.0) / scale; // Slightly thicker caps
          canvas.drawPoints(ui.PointMode.points, [p1,p2,p3,p4], paint);
          paint.strokeWidth = strokeWidth / scale; // Reset

          _drawCobbArc(canvas, paint, points[0], points[1], points[2], points[3], labelPos, m.forceAcute);
       } else if (m.type == MeasurementType.cobbAngle && points.length >= 2) {
          _drawCustomLine(canvas, points[0], points[1], paint, isDashed: m.isDashed, isInfinite: m.isInfinite);
       } else if (m.type == MeasurementType.circle || m.type == MeasurementType.areaCircle) {
          // CIRCLE DRAWING
          final center = points[0];
          final edge = points[1];
          final radius = (center - edge).distance;
          
          // Circle
          canvas.drawCircle(center, radius, paint);
          
          // Fill for Area (Faint)
          if (m.type == MeasurementType.areaCircle) {
             canvas.drawCircle(center, radius, paint..style=PaintingStyle.fill..color=m.color.withValues(alpha: 0.15));
             // Restore stroke for other parts if needed (but we are done with paint object here mostly)
             paint..style = PaintingStyle.stroke ..color = m.color; 
          }
          
          // Radius Line
          canvas.drawLine(center, edge, paint..strokeWidth = 1.5 / scale);
          
          // Center Cross
          canvas.drawLine(center - Offset(crossSize, 0), center + Offset(crossSize, 0), paint);
          canvas.drawLine(center - Offset(0, crossSize), center + Offset(0, crossSize), paint);
       } else if (m.type == MeasurementType.areaPolygon && points.length >= 2) {
          // POLYGON DRAWING
          final path = Path()..moveTo(points[0].dx, points[0].dy);
          for (int k = 1; k < points.length; k++) {
              path.lineTo(points[k].dx, points[k].dy);
          }
          if (m.isLocked) {
              path.close();
              // Fill
              canvas.drawPath(path, paint..style=PaintingStyle.fill..color=m.color.withValues(alpha: 0.15));
              paint..style = PaintingStyle.stroke ..color = m.color;
          }
          canvas.drawPath(path, paint);
          
          // Draw vertices
          for (final p in points) {
              canvas.drawCircle(p, pointRadius, paint..style=PaintingStyle.fill);
          }

       } else if (m.type == MeasurementType.sacralSlope && points.length >= 2) {
          // SACRAL SLOPE (2 pts - S1)
          canvas.drawLine(points[0], points[1], paint);
          
          // Horizontal Ref
          final s1Center = (points[0] + points[1]) / 2;
          final hLen = 40.0 / scale;
          final auxPaint = Paint()..color = paint.color.withValues(alpha: 0.7)..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
          canvas.drawLine(s1Center - Offset(hLen, 0), s1Center + Offset(hLen, 0), auxPaint);
          
          // DRAW TEXT REMOVED (Handled by Widget)
          
       } else if (m.type == MeasurementType.pelvicTilt && points.length >= 4) {
          // PELVIC TILT (S1: P1-P2, Hips: P3, P4)
          // Note: Reuse copies points, so we draw them too?
          // Maybe just the Pelvic Radius and Vertical.
          
          final s1Center = (points[0] + points[1]) / 2;
          final hipCenter = (points[2] + points[3]) / 2;
          
          // Draw Pelvic Radius with Thinner line
          final radiusPaint = Paint()..color = paint.color..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
          canvas.drawLine(hipCenter, s1Center, radiusPaint);
          
          // Vertical Ref at Hip Center (Thinner, Dashed)
          final vLen = 60.0 / scale;
          final auxPaint = Paint()..color = paint.color.withValues(alpha: 0.7)..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
          _drawDashedLine(canvas, hipCenter - Offset(0, vLen), hipCenter + Offset(0, vLen/2), auxPaint);

          // DRAW TEXT REMOVED (Handled by Widget)

       } else if (m.type == MeasurementType.pelvicIncidence && points.length >= 4) {
          // PELVIC INCIDENCE (S1: P1-P2, Hips: P3, P4)
          final s1Center = (points[0] + points[1]) / 2;
          final hipCenter = (points[2] + points[3]) / 2;
          
          // Draw Pelvic Radius (Faint/Thin)
          final radiusPaint = Paint()..color = paint.color..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
          canvas.drawLine(hipCenter, s1Center, radiusPaint);
          
          // Perpendicular to S1 (Thin)
          final vs1 = points[1] - points[0];
          // Rotated 90
          final perp = Offset(-vs1.dy, vs1.dx);
          final normPerp = perp / perp.distance;
          final pLen = 50.0 / scale;
          
          final perpPaint = Paint()..color = paint.color..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
          canvas.drawLine(s1Center, s1Center + normPerp * pLen, perpPaint);

          // DRAW TEXT REMOVED (Handled by Widget)

       } else if (m.type == MeasurementType.spinopelvic && points.length >= 6) {
          // SPINOPELVIC DRAWING
          final p1 = points[0]; // S1 P1
          final p2 = points[1]; // S1 P2
          final c1 = points[2]; // Hip 1 Center
          final r1 = (points[3] - c1).distance;
          final c2 = points[4]; // Hip 2 Center
          final r2 = (points[5] - c2).distance;
          
          // Draw S1 Line
          canvas.drawLine(p1, p2, paint);
          
          // Draw Hip Circles
          canvas.drawCircle(c1, r1, paint);
          canvas.drawCircle(c2, r2, paint);
          // Crosses for centers
          canvas.drawLine(c1 - Offset(crossSize, 0), c1 + Offset(crossSize, 0), paint);
          canvas.drawLine(c2 - Offset(crossSize, 0), c2 + Offset(crossSize, 0), paint);
          canvas.drawLine(c2 - Offset(0, crossSize), c2 + Offset(0, crossSize), paint);
          
          // Calculate Geometry
           GeometryUtils.calculateSpinopelvic(p1, p2, c1, c2);
          final s1Center = (p1 + p2) / 2;
          final hipCenter = (c1 + c2) / 2;
          
          // Draw Hip Axis (Dashed)
          final auxPaint = Paint()
             ..color = paint.color.withValues(alpha: 0.7)
             ..strokeWidth = 1.5 / scale
             ..style = PaintingStyle.stroke;

          _drawDashedLine(canvas, c1, c2, auxPaint);
          
          // Draw Pelvic Radius (Hip Center -> S1 Center)
          canvas.drawLine(hipCenter, s1Center, paint..strokeWidth=2.0/scale);
          
          // Draw References
          // Horizontal through S1 Center (for SS)
          final hLen = 40.0 / scale;
          canvas.drawLine(s1Center - Offset(hLen, 0), s1Center + Offset(hLen, 0), auxPaint);
          
          // Vertical through Hip Center (for PT)
          final vLen = 60.0 / scale;
          canvas.drawLine(hipCenter - Offset(0, vLen), hipCenter + Offset(0, vLen/2), auxPaint); // Up mostly
          
       } else if (m.type == MeasurementType.lcea && points.length >= 6) {
          // points: 0,1=Teardrops, 2,3,4=FH, 5=Source
          // 1. Pelvic Axis Video
          final pAxisVec = points[1] - points[0];
          // 2. FH Center
          final fhCenter = GeometryUtils.getCircleCenter(points[2], points[3], points[4]);
          // 3. Vertical (Perp to Axis)
          final verticalVec = Offset(-pAxisVec.dy, pAxisVec.dx); // rotate 90
          // Draw Vertical from Center
          // Make sure vertical goes UP (compare Y). Screen Y is down.
          // If pAxisVec is roughly (1, 0), vertical is (0, 1) [Down]. We want (0, -1).
          Offset safeVert = verticalVec;
          if (safeVert.dy > 0) safeVert = -safeVert; // Force UP
          
          final vLineEnd = fhCenter + (safeVert / safeVert.distance) * (100.0/scale);
          _drawDashedLine(canvas, fhCenter, vLineEnd, paint..strokeWidth = 1.0/scale);

          // 4. Center-Edge Line
          canvas.drawLine(fhCenter, points[5], paint..strokeWidth = 2.0/scale);
          
          // Draw FH Circle (Auxiliary visual)
          if (fhCenter != Offset.zero) {
              final r = (points[2] - fhCenter).distance;
              canvas.drawCircle(fhCenter, r, paint..strokeWidth=1.0/scale..color=paint.color.withValues(alpha:0.5));
          }

       } else if (m.type == MeasurementType.tonnisAngle && points.length >= 4) {
          // 0,1=Teardrops, 2=Med, 3=Lat
          // Draw Pelvic Axis (Light)
          canvas.drawLine(points[0], points[1], paint..strokeWidth = 1.0/scale..color=paint.color.withValues(alpha:0.5));
          // Draw Sourcil Line
          canvas.drawLine(points[2], points[3], paint..strokeWidth = 2.0/scale);
          
          // Visualizing angle intersection
          final intersection = GeometryUtils.getLineIntersection(points[0], points[1], points[2], points[3]);
          if (intersection != null) {
              _drawDashedLine(canvas, points[3], intersection, paint..strokeWidth=1.0/scale);
          }
       
       } else if (m.type == MeasurementType.modifiedInsallSalvati) {
          // mIS: Sup(0)->Inf(1), Tub(2)
          if (points.length >= 2) {
             // Articular Line
             canvas.drawLine(points[0], points[1], paint);
          }
          if (points.length >= 3) {
             // Tendon Line (Thin/Distinct)
             final tendonPaint = Paint()..color = paint.color..strokeWidth = 1.5/scale..style=PaintingStyle.stroke;
             canvas.drawLine(points[1], points[2], tendonPaint);
          }

       } else if (m.type == MeasurementType.blackburnePeel) {
          // BP: Sup(0)->Inf(1), PlatPost(2)->PlatAnt(3)
          if (points.length >= 2) {
             // Articular Line
             canvas.drawLine(points[0], points[1], paint);
          }
          if (points.length >= 4) {
              // Plateau Line (2-3)
              canvas.drawLine(points[2], points[3], paint);
              
              // Perpendicular (Inf(1) -> Project onto 2-3)
              final pInf = points[1];
              final pPost = points[2];
              final pAnt = points[3];
              
              final vPlat = pAnt - pPost;
              if (vPlat.distance > 0) {
                  final vInf = pInf - pPost;
                  final t = (vInf.dx * vPlat.dx + vInf.dy * vPlat.dy) / (vPlat.dx*vPlat.dx + vPlat.dy*vPlat.dy);
                  final projected = pPost + vPlat * t;
                  
                  // Thin Dashed Line
                  final dashPaint = Paint()..color = paint.color..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
                  _drawDashedLine(canvas, pInf, projected, dashPaint);
              }
          }

       } else if (m.type == MeasurementType.circle3Point) {
          // Draw points
          for (final p in points) {
               canvas.drawCircle(p, pointRadius, paint..style=PaintingStyle.fill);
          }
          if (points.length >= 3) {
              final res = GeometryUtils.calculateCircleFrom3Points(points[0], points[1], points[2]);
              if (res != null) {
                  final c = res['center'] as Offset;
                  final r = res['radius'] as double;
                  canvas.drawCircle(c, r, paint..style=PaintingStyle.stroke);
                  
                  // Center cross
                  canvas.drawLine(c - Offset(crossSize, 0), c + Offset(crossSize, 0), paint);
                  canvas.drawLine(c - Offset(0, crossSize), c + Offset(0, crossSize), paint);
              }
          }
       } else if (m.type == MeasurementType.acromialIndex && points.length >= 4) {
          final p1 = points[0]; 
          final p2 = points[1]; 
          final pA = points[2]; 
          final pH = points[3]; 
          
          canvas.drawLine(p1, p2, paint);
          
          final vLine = p2 - p1;
          if (vLine.distance > 0) {
              final dashPaint = Paint()..color = paint.color.withValues(alpha: 0.8)..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;

              final vA = pA - p1;
              final tA = (vA.dx * vLine.dx + vA.dy * vLine.dy) / (vLine.dx * vLine.dx + vLine.dy * vLine.dy);
              final projA = p1 + vLine * tA;
              _drawDashedLine(canvas, pA, projA, dashPaint);
              
              final vH = pH - p1;
              final tH = (vH.dx * vLine.dx + vH.dy * vLine.dy) / (vLine.dx * vLine.dx + vLine.dy * vLine.dy);
              final projH = p1 + vLine * tH;
              _drawDashedLine(canvas, pH, projH, dashPaint);
          }
       } else if (m.type == MeasurementType.glenoidDefect) {
           if (points.length >= 4) {
               final res = GeometryUtils.calculateGlenoidDefect(points);
               if (res != null) {
                   final c = res['center'] as Offset;
                   final r = res['radius'] as double;
                   final defect = res['defectPoint'] as Offset;
                   
                   // Draw Best Fit Circle (Dashed or Thin)
                   final thinPaint = Paint()..color = m.color ..strokeWidth = 1.0/scale ..style = PaintingStyle.stroke;
                   canvas.drawCircle(c, r, thinPaint);
                   
                   // Draw Defect Point (Circle)
                   canvas.drawCircle(defect, pointRadius, Paint()..color=Colors.red..style=PaintingStyle.fill);
                   
                   // Draw Line from Center to Defect
                   final linePaint = Paint()..color = Colors.redAccent ..strokeWidth = 2.0/scale ..style = PaintingStyle.stroke;
                   canvas.drawLine(c, defect, linePaint);
                   
                   // Draw Center
                   canvas.drawCircle(c, pointRadius * 0.75, Paint()..color=Colors.white);
               }
           }
       } else if (m.type == MeasurementType.talonavicularCoverage && points.length >= 4) {
           final p1 = points[0];
           final p2 = points[1];
           final p3 = points[2];
           final p4 = points[3];
           
           canvas.drawLine(p1, p2, paint);
           canvas.drawLine(p3, p4, paint);
           
           // Extension lines
           final i = GeometryUtils.getLineIntersection(p1, p2, p3, p4);
           if (i != null) {
               final dottedPaint = Paint()..color = paint.color.withValues(alpha: 0.7)..style = PaintingStyle.stroke..strokeWidth = 1.0/scale;
               _drawDashedLine(canvas, (p1+p2)/2, i, dottedPaint);
               _drawDashedLine(canvas, (p3+p4)/2, i, dottedPaint);
           }
           // Arc
           _drawCobbArc(canvas, paint, p1, p2, p3, p4, labelPos, m.forceAcute);
           
       } else if (m.type == MeasurementType.talonavicularUncoverage && points.length >= 3) {
           final pLat = points[0];
           final pMed = points[1]; 
           final pNav = points[2];
           
           canvas.drawLine(pLat, pMed, paint);
           
           final c = (pLat + pMed) / 2;
           canvas.drawCircle(pNav, pointRadius, paint..style=PaintingStyle.fill);
           canvas.drawCircle(c, pointRadius * 0.75, Paint()..color=Colors.white);

           // Draw dashed line C-P
           final dashPaint = Paint()..color = paint.color.withValues(alpha: 0.8)..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
           _drawDashedLine(canvas, c, pNav, dashPaint);
       
       } else if (m.type == MeasurementType.calcanealPitch && points.length >= 2) {
           canvas.drawLine(points[0], points[1], paint);
           final p1 = points[0]; final p2 = points[1];
           final lowPt = (p1.dy > p2.dy) ? p1 : p2;
           final hLen = 60.0 / scale;
           final auxPaint = Paint()..color = paint.color.withValues(alpha: 0.7)..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
           canvas.drawLine(lowPt - Offset(hLen, 0), lowPt + Offset(hLen, 0), auxPaint);

       } else if (m.type == MeasurementType.talocalcanealAngle && points.length >= 4) {
           final p1 = points[0]; final p2 = points[1];
           final p3 = points[2]; final p4 = points[3];
           canvas.drawLine(p1, p2, paint);
           canvas.drawLine(p3, p4, paint);
           _drawCobbArc(canvas, paint, p1, p2, p3, p4, labelPos, m.forceAcute);

       } else if (m.type == MeasurementType.areaCircle) {
           if (points.length >= 2) {
               final center = points[0];
               final edge = points[1];
               final radius = (center - edge).distance;
               canvas.drawCircle(center, radius, paint..style=PaintingStyle.stroke);
               final fillPaint = Paint()..color = m.color.withValues(alpha: 0.2)..style = PaintingStyle.fill;
               canvas.drawCircle(center, radius, fillPaint);
               canvas.drawLine(center, edge, paint..strokeWidth = 1.5 / scale);
                canvas.drawLine(center - Offset(crossSize, 0), center + Offset(crossSize, 0), paint..style=PaintingStyle.stroke);
                canvas.drawLine(center - Offset(0, crossSize), center + Offset(0, crossSize), paint);
           }
       } else if (m.type == MeasurementType.areaPolygon) {
           for (final p in points) {
                canvas.drawCircle(p, pointRadius, paint..style=PaintingStyle.fill);
           }
           if (points.length >= 2) {
               for (int i = 0; i < points.length - 1; i++) {
                   canvas.drawLine(points[i], points[i + 1], paint..style=PaintingStyle.stroke);
               }
               if (m.isLocked && points.length >= 3) {
                   canvas.drawLine(points.last, points.first, paint);
                   final fillPaint = Paint()..color = m.color.withValues(alpha: 0.2)..style = PaintingStyle.fill;
                   final path = Path();
                   path.moveTo(points.first.dx, points.first.dy);
                   for (int i = 1; i < points.length; i++) {
                       path.lineTo(points[i].dx, points[i].dy);
                   }
                   path.close();
                   canvas.drawPath(path, fillPaint);
               }
           }
       } else if (m.type == MeasurementType.talarIncongruency && points.length >= 3) {
           canvas.drawLine(points[0], points[1], paint);
           canvas.drawLine(points[1], points[2], paint);
           _drawAngleArc(canvas, paint, points[0], points[1], points[2]);
           
       } else if (m.type == MeasurementType.glenoidVersion && points.length >= 3) {
           final A = points[0];
           final B = points[1];
           final C = points[2];
           for (int i=0; i<3; i++) {
                canvas.drawCircle(points[i], pointRadius, paint..style=PaintingStyle.fill);
           }
           if (points.length >= 5) {
               canvas.drawCircle(points[3], pointRadius, paint..style=PaintingStyle.fill);
               canvas.drawCircle(points[4], pointRadius, paint..style=PaintingStyle.fill);
           }
           canvas.drawLine(B, C, paint);
           final M = (B + C) / 2;
           final axisPaint = Paint()..color = paint.color..strokeWidth = 1.5/scale..style=PaintingStyle.stroke;
           _drawDashedLine(canvas, A, M, axisPaint);
           final vAM = M - A;
           if (vAM.distance > 0) {
               final vPerp = Offset(-vAM.dy, vAM.dx) / vAM.distance;
               final visLen = 60.0 / scale;
               final mStart = M - vPerp * visLen;
               final mEnd = M + vPerp * visLen;
               _drawDashedLine(canvas, mStart, mEnd, axisPaint); 
               final cStart = C - vPerp * visLen;
               final cEnd = C + vPerp * visLen;
               _drawDashedLine(canvas, cStart, cEnd, axisPaint);
               if (points.length >= 5) {
                   final D = points[3];
                   final E = points[4];
                   final subPaint = Paint()..color = paint.color.withValues(alpha: 0.8)..strokeWidth = 1.5/scale..style=PaintingStyle.stroke;
                   canvas.drawLine(D, E, subPaint);
                   final intersection = GeometryUtils.getLineIntersection(A, M, D, E);
                   if (intersection != null) {
                       _drawDashedLine(canvas, M, intersection, axisPaint);
                       canvas.drawCircle(intersection, 3.0/scale, Paint()..color=Colors.white);
                   }
               }
           }
       } else {
          // Distance / Polyline / Standard Line fallback
          for (int i=0; i < points.length - 1; i++) {
            _drawCustomLine(canvas, points[i], points[i+1], paint, isDashed: m.isDashed, isInfinite: m.isInfinite);
          }
       }
    }
  }



  void _drawCobbArc(Canvas canvas, Paint basePaint, Offset p1, Offset p2, Offset p3, Offset p4, Offset? labelPos, bool forceAcute) {
      final intersection = GeometryUtils.getLineIntersection(p1, p2, p3, p4);
      if (intersection == null) return;
      
      const double piVal = 3.14159265;

      double t1 = (p2 - p1).direction % piVal; 
      if (t1 < 0) t1 += piVal; 
      double t2 = (p4 - p3).direction % piVal;
      if (t2 < 0) t2 += piVal;
      
      final angles = [t1, t2, t1 + piVal, t2 + piVal]..sort();
      
      double targetAngle;
      
      if (labelPos != null && !forceAcute) {
         final vLabel = labelPos - intersection;
         if (vLabel.distance == 0) return;
         targetAngle = vLabel.direction;
      } else {
         // Default to Bisector of Acute Angle
         // Or just pick the acute sector
         // Vectors u and v
         var u = (p2 - p1);
         var v = (p4 - p3);
         
         // Ensure dot product is positive for acute angle between vectors
         if ((u.dx * v.dx + u.dy * v.dy) < 0) {
            v = -v;
         }
         final bisect = u + v;
         targetAngle = bisect.direction;
      }

      if (targetAngle < 0) targetAngle += 2 * piVal; 
      
      double start = 0;
      double sweep = 0;
      
      bool inInterval(double a, double s, double e) {
          if (s <= e) return a >= s && a <= e;
          return a >= s || a <= e; 
      }
      
      for (int i = 0; i < 4; i++) {
          final s = angles[i];
          final e = angles[(i + 1) % 4];
          
          if (inInterval(targetAngle, s, e)) {
             start = s;
             sweep = e - s;
             if (sweep < 0) sweep += 2 * piVal;
             break;
          }
      }
      
      final arcPaint = Paint()
        ..color = basePaint.color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale;
        
      final radius = (SettingsService().landmarkSize * 5.0) / scale;
      canvas.drawArc(
        Rect.fromCircle(center: intersection, radius: radius),
        start,
        sweep,
        false,
        arcPaint
      );
  }

  void _drawAngleArc(Canvas canvas, Paint basePaint, Offset p1, Offset p2, Offset p3) {
      const double piVal = 3.14159265;
      
      final v1 = p1 - p2;
      final v2 = p3 - p2;
      
      if (v1.distance == 0 || v2.distance == 0) return;
      
      double a1 = v1.direction;
      double a2 = v2.direction;
      
      double diff = a2 - a1;
      while (diff <= -piVal) {
        diff += 2*piVal;
      }
      while (diff > piVal) {
        diff -= 2*piVal;
      }
      
      final arcPaint = Paint()
        ..color = basePaint.color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale;
        
      final radius = (SettingsService().landmarkSize * 5.0) / scale;
      canvas.drawArc(
        Rect.fromCircle(center: p2, radius: radius),
        a1,
        diff,
        false,
        arcPaint
      );
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    var max = (p2 - p1).distance;
    var dashWidth = 10.0 / scale;
    var dashSpace = 5.0 / scale;
    var startY = 0.0;
    final normalized = (p2 - p1) / max;
    
    while (startY < max) {
      final lineStart = p1 + normalized * startY;
      final lineEnd = p1 + normalized * (startY + dashWidth > max ? max : startY + dashWidth);
      canvas.drawLine(lineStart, lineEnd, paint);
      startY += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant MeasurementsPainter oldDelegate) {
    return oldDelegate.scale != scale || 
           oldDelegate.imageRect != imageRect || 
           oldDelegate.strokeWidth != strokeWidth ||
           oldDelegate.measurements != measurements ||
           oldDelegate.textSize != textSize ||
           oldDelegate.isTextBold != isTextBold ||
           oldDelegate.pixelsToMm != pixelsToMm;
  }
}
