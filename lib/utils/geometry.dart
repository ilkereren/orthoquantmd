import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vector;

class GeometryUtils {
  /// Calculates the angle (in degrees) formed by three points: p1 -> p2 -> p3.
  static double calculateAngle(Offset p1, Offset p2, Offset p3) {
    final v1 = vector.Vector2(p1.dx - p2.dx, p1.dy - p2.dy);
    final v2 = vector.Vector2(p3.dx - p2.dx, p3.dy - p2.dy);
    double angleRadians = v1.angleTo(v2);
    return (angleRadians * 180 / pi).abs();
  }

  /// Calculates Cobb Angle based on label position.
  /// If lines intersect:
  ///   - Label in Acute sector -> returns Acute angle.
  ///   - Label in Obtuse sector -> returns Obtuse angle (180 - Acute).
  /// If parallel (no intersection), returns 0.
  static double calculateDynamicCobbAngle(Offset p1, Offset p2, Offset p3, Offset p4, Offset labelPos) {
    // 1. Calculate Intersection
    final intersection = getLineIntersection(p1, p2, p3, p4);
    
    // Base acute angle
    double theta = calculateCobbAngle(p1, p2, p3, p4); // Always returns <= 90

    if (intersection == null) return theta; // Parallel-ish

    // 2. Determine Sector
    // Vectors from Intersection
    // We need to define the two lines as vectors crossing through I
    // We can check the angle of (Label - I) relative to the lines.
    
    // Easier approach: Bisectors.
    // The two lines form 4 regions.
    // Vector for Line 1 direction:

    
    // We need 2 unit vectors originating from I aligned with the lines.
    // Actually, simple angle check:
    // Let vL = Label - I.
    // Angle between vL and Line1 (0..90 distance)
    // If it's "closer" to the bisector of the acute angle... this is hard to generalize without orientation.
    
    // Robust Vector Approach:
    // 1. Get direction vectors for lines: u = L1dir, v = L2dir
    // 2. Acute Angle between u and v is theta.
    // 3. Obtuse Angle is 180-theta.
    // 4. Project (Label-I) onto the basis defined by u and v?
    
    // Simplest: Check 3-point angle formed by (Label, Intersection, arbitrary point on L1).
    // Let's say we map Label to an angle relative to L1 (0..360).
    // The line L2 intersects at angle 'theta' and '180+theta'.
    // Sectors are [0, theta], [theta, 180], [180, 180+theta], [180+theta, 360].
    // If L2 is at relative angle phi?
    
    // We skip the complex math and use current code's angleTo logic.
    // Calculate angle between Line1 and Vector(Int->Label). let it be alpha.
    // If alpha is close to Line2 angle or (180-Line2), determines sector.
    
    // Actually, user wants: "If lines intersect, show acute by default. If box moved to wide side, show wide."
    // "Wide side" means the Obtuse sector.
    
    // Let's use the property of angle bisectors again.
    // Acute Bisector A_bis. Obtuse Bisector O_bis.
    // If Label is closer to O_bis than A_bis, return Obtuse.
    
    // Calculate intersection I
    final I = intersection;
    
    // Line directions (normalized)
    var u = (p2 - p1) / (p2 - p1).distance;
    var v = (p4 - p3) / (p4 - p3).distance;
    
    // We need to ensure u and v make an ACUTE angle so (u+v) is the acute bisector.
    // If dot(u,v) < 0, they make an ideal obtuse angle. Flip one.
    // dot = cos(theta). If cos < 0, theta > 90.
    if ((u.dx * v.dx + u.dy * v.dy) < 0) {
      v = -v;
    }
    
    // Now u and v form acute angle at I.
    // Acute Bisector (unnormalized)
    final acuteBisector = u + v; 
    // Obtuse Bisector is perpendicular to Acute Bisector
    final obtuseBisector = Offset(-acuteBisector.dy, acuteBisector.dx);
    
    // Vector to Label
    final toLabel = labelPos - I;
    
    // Project toLabel onto Acute vs Obtuse bisectors (squared length of projection to compare alignment)
    // Or just compare angle.
    // abs(dot(toLabel, acute)) vs abs(dot(toLabel, obtuse))
    // The one with larger absolute dot product is the closer axis.
    
    // Normalize bisectors for fair comparison
    final ab = acuteBisector / acuteBisector.distance;
    final ob = obtuseBisector / obtuseBisector.distance;
    
    if (ab.distance == 0 || ob.distance == 0) return theta;
    
    double dotAcute = (toLabel.dx * ab.dx + toLabel.dy * ab.dy).abs();
    double dotObtuse = (toLabel.dx * ob.dx + toLabel.dy * ob.dy).abs();
    
    if (dotObtuse > dotAcute) {
      return 180 - theta;
    }
    return theta;
  }

  /// Returns intersection point of two infinite lines defined by p1-p2 and p3-p4.
  static Offset? getLineIntersection(Offset p1, Offset p2, Offset p3, Offset p4) {
    final x1 = p1.dx, y1 = p1.dy;
    final x2 = p2.dx, y2 = p2.dy;
    final x3 = p3.dx, y3 = p3.dy;
    final x4 = p4.dx, y4 = p4.dy;

    final denom = (y4 - y3) * (x2 - x1) - (x4 - x3) * (y2 - y1);
    if (denom == 0) return null; // Parallel

    final ua = ((x4 - x3) * (y1 - y3) - (y4 - y3) * (x1 - x3)) / denom;
    
    return Offset(x1 + ua * (x2 - x1), y1 + ua * (y2 - y1));
  }

  /// Calculates the Cobb angle between two lines (2 points each).
  /// Always returns the Acute angle (<= 90).
  static double calculateCobbAngle(Offset p1, Offset p2, Offset p3, Offset p4) {
    // Vector for Line 1
    final v1 = vector.Vector2(p2.dx - p1.dx, p2.dy - p1.dy);
    // Vector for Line 2
    final v2 = vector.Vector2(p4.dx - p3.dx, p4.dy - p3.dy);
    
    // Angle between lines
    double angleRadians = v1.angleTo(v2);
    double angleDegrees = angleRadians * (180 / pi);
    angleDegrees = angleDegrees.abs();
    
    if (angleDegrees > 90) {
      return 180 - angleDegrees;
    }
    return angleDegrees;
  }

  static double calculateSacralSlope(Offset p1, Offset p2) {
      final vs1 = p2 - p1;
      return (atan(vs1.dy / vs1.dx) * 180 / pi).abs();
  }

  static double calculatePelvicTilt(Offset p1, Offset p2, Offset h1, Offset h2) {
      final s1Center = (p1 + p2) / 2;
      final hipCenter = (h1 + h2) / 2;
      final vPelvicRadius = s1Center - hipCenter;
      return (atan(vPelvicRadius.dx / -vPelvicRadius.dy) * 180 / pi).abs();
  }

  static double calculatePelvicIncidence(Offset p1, Offset p2, Offset h1, Offset h2) {
      final ss = calculateSacralSlope(p1, p2);
      final pt = calculatePelvicTilt(p1, p2, h1, h2);
      return ss + pt;
  }

  /// Calculates Spinopelvic Parameters: SS, PT, PI
  /// Returns { 'SS': double, 'PT': double, 'PI': double }
  /// p1, p2: S1 Endplate (Posterior -> Anterior)
  /// c1, c2: Hip Centers
  static Map<String, double> calculateSpinopelvic(Offset p1, Offset p2, Offset c1, Offset c2) {
      // 1. Centers
      final s1Center = (p1 + p2) / 2;
      final hipCenter = (c1 + c2) / 2;
      
      // 2. Sacral Slope (SS)
      // Angle of S1 plate with Horizontal.
      // Line vector
      final vs1 = p2 - p1;
      // Horizontal vector (1, 0)
      // We essentially want abs(atan(dy/dx))
      double ss = (atan(vs1.dy / vs1.dx) * 180 / pi).abs();
      
      // 3. Pelvic Tilt (PT)
      // Angle between Vertical and Line(HipCenter -> S1Center)
      final vPelvicRadius = s1Center - hipCenter; // From Hip UP to S1
      // Vertical Up is (0, -1) in Flutter coords (0,0 is top-left)
      // Actually standard: Vertical is Y-axis. 
      // Angle with Vertical axis.
      // angle = atan(dx / dy). 
      // If x is 0, angle is 0.
      double pt = (atan(vPelvicRadius.dx / -vPelvicRadius.dy) * 180 / pi).abs();
      // Wait, is it -dy? dy is negative going up.
      // If vPR is (10, -100) (Up and right). atan(10/100) ~ 5 deg. Correct.
      // If vPR is (10, 100) (Down and right). atan(10/-100) ~ -5. Abs -> 5. 
      // Correct for simple magnitude.
      
      // 4. Pelvic Incidence (PI)
      // PI = SS + PT (Arithmetic approximation is standard)
      // Geometric definition: Angle between perpendicular to S1 and line joining S1-Hip.
      // Let's use the identity for consistency in display, 
      // or calculate geometrically to handle edge cases accurately?
      // Identity is safer: PI = SS + PT.
      double piVal = ss + pt;
      
      
      return {'SS': ss, 'PT': pt, 'PI': piVal};
  }

  static double calculateBlackburnePeel(Offset pSup, Offset pInf, Offset pPlatPost, Offset pPlatAnt) {
     // BP = Perpendicular Height from pInf to Plateau Line / Articular Length (pSup-pInf)
     
     double articularLen = (pSup - pInf).distance;
     if (articularLen == 0) return 0;

     // Plateau Line Vector
     final vPlat = pPlatAnt - pPlatPost;
     if (vPlat.distance == 0) return 0;
     
     // Project pInf onto line (pPlatPost, pPlatAnt) extended
     // Vector from Post to Inf
     
     // Projection scalar t = (vPostInf . vPlat) / |vPlat|^2
     // But we need perpendicular distance. 
     // Cross product method or projection
     // Let's use standard line distance formula:
     // |(x2-x1)(y1-y0) - (x1-x0)(y2-y1)| / sqrt((x2-x1)^2 + (y2-y1)^2)
     // Line: (x1, y1) = Post, (x2, y2) = Ant. Point: (x0, y0) = Inf.
     
     double num = ((pPlatAnt.dx - pPlatPost.dx) * (pPlatPost.dy - pInf.dy) - (pPlatPost.dx - pInf.dx) * (pPlatAnt.dy - pPlatPost.dy)).abs();
     double den = vPlat.distance;
     
     double perpHeight = num / den;
     
     return perpHeight / articularLen;
  }

  static double calculateModifiedInsallSalvati(Offset pSup, Offset pInf, Offset pTub) {
      // mIS = Dist(pInf, pTub) / Articular Length (pSup-pInf)
      
      double articularLen = (pSup - pInf).distance;
      if (articularLen == 0) return 0;
      
      double tendonLen = (pInf - pTub).distance;
      
      
      return tendonLen / articularLen;
  }

  // Returns {center: Offset, radius: double}
  static Map<String, dynamic>? calculateCircleFrom3Points(Offset p1, Offset p2, Offset p3) {
      double x1 = p1.dx, y1 = p1.dy;
      double x2 = p2.dx, y2 = p2.dy;
      double x3 = p3.dx, y3 = p3.dy;

      double D = 2 * (x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2));
      
      if (D.abs() < 1e-6) return null; // Collinear points

      double centerX = ((x1 * x1 + y1 * y1) * (y2 - y3) + (x2 * x2 + y2 * y2) * (y3 - y1) + (x3 * x3 + y3 * y3) * (y1 - y2)) / D;
      double centerY = ((x1 * x1 + y1 * y1) * (x3 - x2) + (x2 * x2 + y2 * y2) * (x1 - x3) + (x3 * x3 + y3 * y3) * (x2 - x1)) / D;

      Offset center = Offset(centerX, centerY);
      double radius = (center - p1).distance;
      
      
      return {'center': center, 'radius': radius};
  }

  static Offset getCircleCenter(Offset p1, Offset p2, Offset p3) {
      final circle = calculateCircleFrom3Points(p1, p2, p3);
      if (circle != null) {
          return circle['center'] as Offset;
      }
      return Offset.zero;
  }

  static Map<String, dynamic>? calculateGlenoidDefect(List<Offset> points) {
     if (points.length < 4) return null;
     
     final p1 = points[0];
     final p2 = points[1];
     final p3 = points[2];
     final pDefect = points[3];
     
     final circle = calculateCircleFrom3Points(p1, p2, p3);
     if (circle == null) return null;
     
     final center = circle['center'] as Offset;
     final radius = circle['radius'] as double;
     
     if (radius == 0) return null;

     final distToDefect = (center - pDefect).distance;
     
     // Linear Bone Loss Diameter %
     // If Defect is at rim (Dist=R) -> Loss=0.
     // If Defect is at center (Dist=0) -> Loss=R (50% of Diameter).
     
     double lossLength = radius - distToDefect;
     // Clamp simple logic? 
     // Defect point usually inside.
     
     double diameter = radius * 2;
     double percent = (lossLength / diameter) * 100;
     
     return {
        'center': center,
        'radius': radius,
        'defectPoint': pDefect,
        'lossPercent': percent,
        'lossMms': lossLength // Needs PxPerMm
     };
  }

  /// Calculates perpendicular distance from Point P to Line defined by A and B.
  static double distanceToLine(Offset p, Offset lineStart, Offset lineEnd) {
      if ((lineEnd - lineStart).distance == 0) return (p - lineStart).distance;
      
      double num = ((lineEnd.dx - lineStart.dx) * (lineStart.dy - p.dy) - (lineStart.dx - p.dx) * (lineEnd.dy - lineStart.dy)).abs();
      double den = (lineEnd - lineStart).distance;
      
      return num / den;
  }

  static double calculateAcromialIndex(Offset pSup, Offset pInf, Offset pLatA, Offset pLatH) {
      double ga = distanceToLine(pLatA, pSup, pInf);
      double gh = distanceToLine(pLatH, pSup, pInf);
      if (gh == 0) return 0.0;
      return ga / gh;
  }
  /// Calculates Talonavicular Coverage Angle (TNCA)
  /// Angle between Talus Head Articular Surface (t1-t2) and Navicular Proximal Articular Surface (n1-n2)
  static double calculateTNCA(Offset t1, Offset t2, Offset n1, Offset n2) {
      return calculateCobbAngle(t1, t2, n1, n2);
  }

  /// Calculates Talonavicular Uncoverage Percentage (TNUP)
  /// tLat: Lateral Talar Head Articular margin
  /// tMed: Medial Talar Head Articular margin
  /// nMed: Medial Navicular Articular margin
  static double calculateTNUP(Offset tLat, Offset tMed, Offset nMed) {
      // User Logic:
      // A = tLat, B = tMed.
      // C = Midpoint(A, B).
      // P = nMed.
      // Angle ACP (Angle between CA and CP).
      // Uncoverage based on Angle.
      // Normal (P near B): Angle(CA, CB) = 180. Angle(CA, CP) ~ 180. Uncoverage ~ 0%.
      // Flatfoot (P near A): Angle(CA, CA) = 0. Angle(CA, CP) ~ 0. Uncoverage ~ 100%.
      // Formula: (180 - AngleACP) / 180 * 100.
      
      final A = tLat;
      final B = tMed;
      final C = (A + B) / 2;
      final P = nMed;
      
      // Angle A-C-P
      // Vector CA
      final vCA = A - C;
      // Vector CP
      final vCP = P - C;
      
      if (vCA.distance == 0 || vCP.distance == 0) return 0;
      
      // Angle using standard atan2 diff
      final angleRad = (vCA.direction - vCP.direction).abs();
      // Normalize to 0-pi
      double angleDeg = angleRad * 180 / pi;
      if (angleDeg > 180) angleDeg = 360 - angleDeg;
      
      // Calculate %
      // 180 deg -> 0%
      // 0 deg -> 100%
      
      double percent = (180.0 - angleDeg) / 180.0 * 100.0;
      return percent.clamp(0.0, 100.0);
  }

  /// Calculates Talar Incongruency Angle
  /// pNeck: Lateral Narrowest Point of Talar Neck
  /// pLatTalus: Lateral Talar Articular Margin
  /// pLatNav: Lateral Navicular Articular Margin
  static double calculateTalarIncongruency(Offset pNeck, Offset pLatTalus, Offset pLatNav) {
      // Angle between Line(Neck -> LatTalus) and Line(LatTalus -> LatNav)
      // If collinear, angle is 0.
      // We use calculateAngle(pNeck, pLatTalus, pLatNav) which uses vectors (pNeck-pLatTalus) and (pLatNav-pLatTalus).
      // Angle between them. Ideally 180 degrees (straight line).
      // If we measure deviation from 180.
      
      double angle = calculateAngle(pNeck, pLatTalus, pLatNav);
      return (180 - angle).abs(); 
  }

  static double calculateCalcanealPitch(Offset p1, Offset p2) => calculateSacralSlope(p1, p2);

  static double calculateTalocalcanealAngle(Offset p1, Offset p2, Offset p3, Offset p4) => calculateCobbAngle(p1, p2, p3, p4);

  /// Calculates area of a circle from 3 points on its circumference
  /// Returns area in square pixels (needs to be converted to mm² using calibration)
  static double? calculateCircleArea(Offset p1, Offset p2, Offset p3) {
    final circle = calculateCircleFrom3Points(p1, p2, p3);
    if (circle == null) return null;
    
    final radius = circle['radius'] as double;
    return pi * radius * radius; // π × r²
  }

  /// Calculates area of a polygon using the Shoelace formula (Gauss's area formula)
  /// Points should be in order (clockwise or counter-clockwise)
  /// Returns area in square pixels (needs to be converted to mm² using calibration)
  static double calculatePolygonArea(List<Offset> points) {
    if (points.length < 3) return 0;
    
    double area = 0;
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length; // Next point (wraps around)
      area += points[i].dx * points[j].dy;
      area -= points[j].dx * points[i].dy;
    }
    
    return (area / 2).abs();
  }
  // / Calculates bounding box for a list of points
  static Rect? calculateBoundingBox(List<Offset> points) {
    if (points.isEmpty) return null;
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (var p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Calculates Glenoid Version parameters using Friedman method + Medialization + Subluxation.
  /// Points: 
  /// A: Scapula Medial Border
  /// B: Glenoid Anterior Margin
  /// C: Glenoid Posterior Margin
  /// D: Humeral Head Anterior (Optional, index 3)
  /// E: Humeral Head Posterior (Optional, index 4)
  /// 
  /// Returns a map with keys:
  /// 'retroversion': double (degrees) - Angle between Glenoid Line and Perpendicular to Scapular Axis
  /// 'medialization': double (pixels/units) - Distance between perpendiculars at M and C
  /// 'subluxation': double (percentage) - Percentage of humeral head posterior to Scapular Axis
  static Map<String, double> calculateGlenoidVersion(List<Offset> points) {
    if (points.length < 3) {
      return {'retroversion': 0.0, 'medialization': 0.0, 'subluxation': 0.0};
    }

    final A = points[0];
    final B = points[1];
    final C = points[2];

    if (A == Offset.zero || B == Offset.zero || C == Offset.zero) {
       return {'retroversion': 0.0, 'medialization': 0.0, 'subluxation': 0.0};
    }

    // 1. Calculate Midpoint M of Glenoid line BC
    Offset M = Offset((B.dx + C.dx) / 2, (B.dy + C.dy) / 2);

    // 2. Define Scapular Axis Vector vAM = M - A
    vector.Vector2 vAM = vector.Vector2(M.dx - A.dx, M.dy - A.dy);
    
    // 3. Define Neutral Line Direction (Perpendicular to vAM)
    vector.Vector2 vNeutral = vector.Vector2(-vAM.y, vAM.x);

    // 4. Define Glenoid Line Vector vBC = C - B
    vector.Vector2 vBC = vector.Vector2(C.dx - B.dx, C.dy - B.dy);

    // 5. Calculate Retroversion Angle
    double angleRad = vBC.angleTo(vNeutral);
    double retroversion = (angleRad * 180 / pi).abs();
    if (retroversion > 90) retroversion = 180 - retroversion;


    // 6. Calculate Medialization
    // Friedman medialization: Distance between 'line perp to axis at M (Midpoint)' and 'line perp to axis at C (Posterior)'.
    // Projection of vector MC onto Axis AM.
    // MC is just half of BC? No, not necessarily relative to axis logic. Vector M -> C.
    // Wait, M is the midpoint of B and C. So |MC| = |MB|.
    // So medialization measured at edges vs midpoint perpendiculars...
    // The user specifically asked: "AM doğrusuna çizdiğimiz dikmeler M ve C noktalarından geçecek. Bu aradaki mesafe Medializasyon miktarı olacak."
    // Yes, projection of vector MC onto AM. 
    // Since M is (B+C)/2, vector MC = C - M.
    vector.Vector2 vMC = vector.Vector2(C.dx - M.dx, C.dy - M.dy);
    
    double medialization = 0.0;
    if (vAM.length > 0) {
       vector.Vector2 vAM_norm = vAM.normalized();
       medialization = (vMC.dot(vAM_norm)).abs();
    }


    // 7. Calculate Posterior Subluxation (if 5 points)
    double subluxation = 0.0;
    if (points.length >= 5) {
        final D = points[3]; // Humeral Anterior
        final E = points[4]; // Humeral Posterior
        
        // Axis Line defined by A and M.
        // We project D and E onto the line perpendicular to Axis AM to measure "width" perpendicular to axis.
        // Actually, usually subluxation is percentage of the head width that is "behind" the axis line.
        // So we need:
        // 1. Total Width |DE_projected|? Usually just diameter of head. Or distance D-E projected onto neutral axis (perp to scapular axis).
        // 2. Posterior Portion: Distance from Axis Line (extended) to E (Posterior).
        
        // Let's assume standard method:
        // Project D and E onto Neutral Axis (perp to AM).
        // Coordinate system: X axis = AM. Y axis = Neutral (Perp to AM).
        // We want Y positions? No, we want position along the Neutral Axis relative to the Scapular Axis (which is at 0).
        // Axis AM is the "zero" line.
        // Distance of point P from Line(A, M) = CrossProduct(AP, AM_norm).
        // Let's use signed distance.
        // Anterior (D) should be on one side, Posterior (E) on the other?
        // Usually Axis AM passes through the head roughly.
        
        // Normalized Axis Direction
        if (vAM.length > 0) {
             vector.Vector2 u = vAM.normalized();
             // Normal vector (Perpendicular) - Neutral Axis Direction
             vector.Vector2 n = vector.Vector2(-u.y, u.x); 
             
             // Vector AE and AD
             vector.Vector2 vAE = vector.Vector2(E.dx - A.dx, E.dy - A.dy);
             vector.Vector2 vAD = vector.Vector2(D.dx - A.dx, D.dy - A.dy);
             
             // Projected lengths along the Neutral Axis (n)
             // This gives distance from the Scapular Axis line.
             // We need to define "Posterior" side.
             // C is posterior glenoid. Let's see which side C is on.
             vector.Vector2 vAC = vector.Vector2(C.dx - A.dx, C.dy - A.dy);
             double cProj = vAC.dot(n); // Signed distance of C
             
             double eProj = vAE.dot(n); // Signed distance of E (Humeral Post)
             double dProj = vAD.dot(n); // Signed distance of D (Humeral Ant)
             
             // We assume E is the Posterior point, but let's verify using C's sign.
             // If cProj and eProj have same sign, E is on posterior side.
             // We want the distance of E from the axis line. That is abs(eProj).
             // And we want the Total Width involved. Is it abs(eProj - dProj)? 
             // Yes, the full width of the head along that measurement axis.
             
             double totalWidth = (eProj - dProj).abs();
             double posteriorWidth = 0.0;
             
             // Subluxation is typically "Amount of head posterior to axis".
             // If the axis passes THROUGH the head, one point is +dist, one is -dist.
             // Posterior width is the distance from Axis to the Posterior Edge.
             // So if E is posterior, it's just abs(eProj).
             // BUT, what if the whole head is posterior (dislocated)? Then it's total width?
             // Or if axis is completely anterior to head?
             // Standard formula: (Distance from Axis to Posterior Edge) / (Total Diameter) * 100.
             // If E is on the posterior side relative to axis:
             
             // Determine if E is truly strictly posterior side of axis relative to D?
             // We assume user marked D (Ant) and E (Post).
             // Posterior side is defined by C (Glenoid Post).
             // Ideally eProj has same sign as cProj.
             
             // Let's just calculate: Percentage of diameter behind axis.
             // If axis splits head: E is dist E_d, D is dist D_d. Total = E_d + D_d. Post = E_d.
             // If axis is in front of head: All head is posterior. Post = Total. Result 100%? Or meas > 100?
             // Usually indices (like Walch) cap at... simple percent.
             
             // We calculate the segment of D-E that lies on the "Posterior Side" of the line AM.
             // Posterior Side is the half-plane containing C.
             
             // Check sides
             bool cSidePositive = cProj >= 0;
             bool eSidePositive = eProj >= 0;
             bool dSidePositive = dProj >= 0;
             
             double eDist = eProj.abs();
             double dDist = dProj.abs();
             totalWidth = (vector.Vector2(E.dx-D.dx, E.dy-D.dy).dot(n)).abs();
             // Wait, total width is projection of DE onto normal.
             
             if (totalWidth > 0) {
                 if (eSidePositive == dSidePositive) {
                     // Both on same side.
                     // If that side is the Posterior side (same as C), then 100% subluxated (or effectively so for this specific geometric definition, or 100% of head is posterior).
                     // But indices usually implied axis intersects head.
                     if (eSidePositive == cSidePositive) {
                         subluxation = 100.0;
                     } else {
                         subluxation = 0.0;
                     }
                 } else {
                     // They span the axis.
                     // The posterior part is the distance from Axis to E (if E is on C's side).
                     if (eSidePositive == cSidePositive) {
                         subluxation = (eDist / totalWidth) * 100.0;
                     } else {
                         // E is actually on anterior side? Maybe points swapped.
                         // Use D?
                         subluxation = (dDist / totalWidth) * 100.0;
                     }
                 }
             }
        }
    }

    return {
      'retroversion': retroversion,
      'medialization': medialization,
      'subluxation': subluxation
    };
  }

  /// Projects point P onto the line defined by A and B.
  static Offset projectPointToLine(Offset p, Offset a, Offset b) {
    if ((b - a).distanceSquared == 0) return a;
    final ap = p - a;
    final ab = b - a;
    double t = (ap.dx * ab.dx + ap.dy * ab.dy) / (ab.dx * ab.dx + ab.dy * ab.dy);
    return a + ab * t;
  }

  /// Returns the two intersection points of an infinite line (p1-p2) with a bounding box (Rect).
  static List<Offset>? getInfiniteLinePoints(Offset p1, Offset p2, Rect rect) {
    if ((p2 - p1).distance == 0) return null;
    
    final List<Offset> intersections = [];
    
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    
    // Check Vertical boundaries (Left/Right)
    if (dx.abs() > 1e-9) {
      double tL = (rect.left - p1.dx) / dx;
      double yL = p1.dy + tL * dy;
      if (yL >= rect.top - 1e-6 && yL <= rect.bottom + 1e-6) intersections.add(Offset(rect.left, yL));
      
      double tR = (rect.right - p1.dx) / dx;
      double yR = p1.dy + tR * dy;
      if (yR >= rect.top - 1e-6 && yR <= rect.bottom + 1e-6) intersections.add(Offset(rect.right, yR));
    }
    
    // Check Horizontal boundaries (Top/Bottom)
    if (dy.abs() > 1e-9) {
      double tT = (rect.top - p1.dy) / dy;
      double xT = p1.dx + tT * dx;
      if (xT >= rect.left - 1e-6 && xT <= rect.right + 1e-6) intersections.add(Offset(xT, rect.top));
      
      double tB = (rect.bottom - p1.dy) / dy;
      double xB = p1.dx + tB * dx;
      if (xB >= rect.left - 1e-6 && xB <= rect.right + 1e-6) intersections.add(Offset(xB, rect.bottom));
    }
    
    if (intersections.isEmpty) return null;
    
    // Unique points
    final unique = <Offset>[];
    for (final p in intersections) {
      if (!unique.any((u) => (u - p).distance < 1e-3)) {
        unique.add(p);
      }
    }
    
    if (unique.length < 2) return null;
    
    // If we have more than 2, sort them by distance and pick ends (should ideally be exactly 2 after unique)
    unique.sort((a, b) => (a - p1).distanceSquared.compareTo((b - p1).distanceSquared));
    
    return [unique.first, unique.last];
  }
  /// Calculates LCEA (Lateral Center-Edge Angle)
  /// Returns angle in degrees.
  /// Points: TeardropR, TeardropL, FH1, FH2, FH3, SourcilLat
  static double calculateLCEA(Offset tdR, Offset tdL, Offset fh1, Offset fh2, Offset fh3, Offset sourcilLat) {
      // 1. Pelvic Horizontal Axis (Vector)
      vector.Vector2 vPelvis = vector.Vector2(tdL.dx - tdR.dx, tdL.dy - tdR.dy);
      
      // 2. Vertical Ref (Perpendicular to Pelvic)
      // Rotate -90 degrees (Upwards relative to image coords usually, but let's just get perp)
      vector.Vector2 vVert = vector.Vector2(vPelvis.y, -vPelvis.x); 
      
      // Ensure vVert points "Up" (negative Y in screen coords)
      if (vVert.y > 0) vVert.scale(-1.0);

      // 3. Femoral Head Center
      final center = getCircleCenter(fh1, fh2, fh3);
      if (center == Offset.zero) return 0.0;
      
      // 4. Center-Edge Vector
      vector.Vector2 vCE = vector.Vector2(sourcilLat.dx - center.dx, sourcilLat.dy - center.dy);
      
      // 5. Angle
      double angleRad = vVert.angleTo(vCE);
      return (angleRad * 180 / pi).abs();
  }

  /// Calculates Tönnis Angle (Acetabular Index)
  /// Points: TeardropR, TeardropL, SourcilMed, SourcilLat
  static double calculateTonnisAngle(Offset tdR, Offset tdL, Offset sMed, Offset sLat) {
       // 1. Pelvic Horizontal Axis
      final vPelvis = vector.Vector2(tdL.dx - tdR.dx, tdL.dy - tdR.dy);
      
      // 2. Sourcil Axis
      final vSourcil = vector.Vector2(sLat.dx - sMed.dx, sLat.dy - sMed.dy);
      
      // 3. Angle between lines
      // We want the inclination relative to horizontal.
      // Usually Tönnis is 0-10 deg.
      // angleTo gives angle between vectors.
      
      double angleRad = vPelvis.angleTo(vSourcil);
      double angleDeg = (angleRad * 180 / pi).abs();
      
      // angleTo might return large angle if vectors oppose. Normalize.
      if (angleDeg > 180) angleDeg = 360 - angleDeg;
      if (angleDeg > 90) angleDeg = 180 - angleDeg;
      
      return angleDeg;
  }
}
