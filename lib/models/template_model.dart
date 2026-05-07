import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as mat;
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/data/template_descriptions.dart';
import 'package:ortho_quant_md/data/template_descriptions.dart' as desc;

// JOINT CATEGORIES
enum JointCategory {
  shoulder,
  elbow,
  hand,
  spine,
  hip,
  knee,
  foot,
  other
}

extension JointCategoryExtension on JointCategory {
  String get label {
    switch (this) {
      case JointCategory.shoulder: return 'Omuz';
      case JointCategory.elbow: return 'Dirsek';
      case JointCategory.hand: return 'El/El Bileği';
      case JointCategory.spine: return 'Omurga';
      case JointCategory.hip: return 'Kalça';
      case JointCategory.knee: return 'Diz';
      case JointCategory.foot: return 'Ayak/Ayak Bileği';
      case JointCategory.other: return 'Diğer';
    }
  }

  // Fallback Icon
  IconData get icon {
    switch (this) {
      case JointCategory.shoulder: return mat.Icons.accessibility_new;
      case JointCategory.elbow: return mat.Icons.pan_tool_outlined;
      case JointCategory.hand: return mat.Icons.back_hand;
      case JointCategory.spine: return mat.Icons.format_align_center;
      case JointCategory.hip: return mat.Icons.accessibility;
      case JointCategory.knee: return mat.Icons.directions_walk;
      case JointCategory.foot: return mat.Icons.do_not_step;
      case JointCategory.other: return mat.Icons.category;
    }
  }

  String get assetPath {
    switch (this) {
      case JointCategory.shoulder: return 'assets/icons/shoulder.png';
      case JointCategory.elbow: return 'assets/icons/elbow.png';
      case JointCategory.hand: return 'assets/icons/hand.png';
      case JointCategory.spine: return 'assets/icons/spine.png';
      case JointCategory.hip: return 'assets/icons/hip.png';
      case JointCategory.knee: return 'assets/icons/knee.png';
      case JointCategory.foot: return 'assets/icons/foot.png';
      case JointCategory.other: return 'assets/icons/other.png';
    }
  }
}

// NEW TEMPLATE STRUCTURE

class TemplateLandmark {
  final String id;
  final String label;
  final String instruction;
  // If true, this landmark is invisible/helper (optional, but requested black/white coding)
  // We can just rely on 'type: MeasurementType.point' in the future, 
  // but here we just need to know it's a point.
  
  const TemplateLandmark({
    required this.id, 
    required this.label, 
    required this.instruction
  });
}

class TemplateCalculation {
  final String id;
  final String label;
  final MeasurementType type;
  // Which landmarks map to which indices of the measurement type
  final List<String> landmarkIds; 
  final bool forceAcute;
  final bool isAuxiliary; // If true, only shown in InfoBox, not rendered as a line/angle? Or rendered but locked.

  const TemplateCalculation({
    required this.id,
    required this.label,
    required this.type,
    required this.landmarkIds,
    this.forceAcute = false,
    this.isAuxiliary = false,
  });
}

class MeasurementTemplate {
  final String id;
  final String title;
  final String viewInfo;

  final String? description;
  final String? infoDescription;
  final IconData? icon;
  final JointCategory category;
  
  final List<TemplateLandmark> landmarks;
  final List<TemplateCalculation> calculations;
  final bool isPremium;

  MeasurementTemplate({
    required this.id,
    required this.title,
    this.viewInfo = '',
    this.description,
    this.infoDescription,
    this.icon,
    this.category = JointCategory.other,
    required this.landmarks,
    required this.calculations,
    this.isPremium = false,
  });
}



// ... (Models unchanged) ...

// DEFINED TEMPLATES
final List<MeasurementTemplate> appTemplates = [
  MeasurementTemplate(
    id: 'critical_shoulder_angle',
    title: 'Acromion Indices',
    viewInfo: 'True AP (Grashey)',
    category: JointCategory.shoulder,
    icon: mat.Icons.accessibility_new,
    infoDescription: desc.TemplateDescriptions.infoDescriptions['critical_shoulder_angle'],
    landmarks: [
       TemplateLandmark(id: 'glenoid_sup', label: 'Glenoid Superior', instruction: 'Mark Superior Glenoid Margin'),
       TemplateLandmark(id: 'glenoid_inf', label: 'Glenoid Inferior', instruction: 'Mark Inferior Glenoid Margin'),
       TemplateLandmark(id: 'acromion_lat', label: 'Lateral Acromion', instruction: 'Mark Lateral Acromion Edge'),
       TemplateLandmark(id: 'acromion_med', label: 'Medial Acromion', instruction: 'Mark Medial Acromion (Undersurface)'),
       TemplateLandmark(id: 'humerus_lat', label: 'Lateral Humerus', instruction: 'Mark Lateral Humeral Head'),
    ],
    calculations: [
       TemplateCalculation(
         id: 'csa_angle',
         label: 'Critical Shoulder Angle',
         type: MeasurementType.angle3Point,
         landmarkIds: ['glenoid_sup', 'glenoid_inf', 'acromion_lat'], 
         forceAcute: true
       ),
       TemplateCalculation(
         id: 'laa_angle',
         label: 'Lateral Acromion Angle',
         type: MeasurementType.cobbAngle,
         landmarkIds: ['glenoid_sup', 'glenoid_inf', 'acromion_med', 'acromion_lat'], 
         forceAcute: true
       ),
       TemplateCalculation(
         id: 'acromial_index',
         label: 'Acromial Index',
         type: MeasurementType.acromialIndex,
         landmarkIds: ['glenoid_sup', 'glenoid_inf', 'acromion_lat', 'humerus_lat'], 
       ),
    ]
  ),
  MeasurementTemplate(
    id: 'glenoid_version',
    title: 'Glenoid Analysis',
    viewInfo: 'Axial CT',
    description: desc.TemplateDescriptions.shortDescriptions['glenoid_version'],
    infoDescription: desc.TemplateDescriptions.infoDescriptions['glenoid_version'],
    icon: mat.Icons.api, 
    category: JointCategory.shoulder,
    landmarks: [
      TemplateLandmark(
        id: 'scapula_medial',
        label: 'Scapula Medial Border (A)',
        instruction: 'Place point on the medial border of the scapula.',
      ),
      TemplateLandmark(
        id: 'glenoid_anterior',
        label: 'Glenoid Anterior (B)',
        instruction: 'Place point on the anterior margin of the glenoid.',
      ),
      TemplateLandmark(
        id: 'glenoid_posterior',
        label: 'Glenoid Posterior (C)',
        instruction: 'Place point on the posterior margin of the glenoid.',
      ),
      TemplateLandmark(
        id: 'humeral_anterior',
        label: 'Humeral Head Anterior (D)',
        instruction: 'Place point on the anterior margin of the humeral head.',
      ),
      TemplateLandmark(
        id: 'humeral_posterior',
        label: 'Humeral Head Posterior (E)',
        instruction: 'Place point on the posterior margin of the humeral head.',
      ),
    ],
    calculations: [
      TemplateCalculation(
        id: 'glenoid_retroversion',
        label: 'Retroversion',
        type: MeasurementType.glenoidVersion,
        landmarkIds: ['scapula_medial', 'glenoid_anterior', 'glenoid_posterior', 'humeral_anterior', 'humeral_posterior'],
      ),
    ],
    isPremium: true,
  ),
  MeasurementTemplate(
    id: 'glenoid_bone_loss',
    title: 'Glenoid Bone Loss',
    viewInfo: 'En Face 3D CT',
    category: JointCategory.shoulder,
    icon: mat.Icons.accessibility_new, 
    infoDescription: desc.TemplateDescriptions.infoDescriptions['glenoid_bone_loss'],
    landmarks: [
       TemplateLandmark(id: 'glenoid_post', label: 'Posterior Rim', instruction: 'Mark posterior rim'),
       TemplateLandmark(id: 'glenoid_inf', label: 'Inferior Rim', instruction: 'Mark inferior rim'),
       TemplateLandmark(id: 'glenoid_third', label: '3rd Healthy Rim', instruction: 'Mark a third healthy glenoid rim'),
       TemplateLandmark(id: 'glenoid_ant_defect', label: 'Ant Defect', instruction: 'Mark anterior glenoid defect edge'),
    ],
    calculations: [
       TemplateCalculation(
         id: 'gbl_percent',
         label: 'Bone Loss',
         type: MeasurementType.glenoidDefect,
         landmarkIds: ['glenoid_post', 'glenoid_inf', 'glenoid_third', 'glenoid_ant_defect'],
       ),
       TemplateCalculation(
         id: 'gbl_size',
         label: 'Defect Size',
         type: MeasurementType.glenoidDefect, 
         landmarkIds: ['glenoid_post', 'glenoid_inf', 'glenoid_third', 'glenoid_ant_defect'],
       ),
    ],
    isPremium: true,
  ),
  MeasurementTemplate(
    id: 'hallux_valgus',
    title: 'Hallux Valgus',
    viewInfo: 'Standing AP',
    category: JointCategory.foot,
    icon: mat.Icons.do_not_step,
    infoDescription: desc.TemplateDescriptions.infoDescriptions['hallux_valgus'],
    landmarks: [
       TemplateLandmark(id: 'm1_head', label: 'M1 Head', instruction: 'Mark Center of Metatarsal 1 Head'),
       TemplateLandmark(id: 'm1_base', label: 'M1 Base', instruction: 'Mark Center of Metatarsal 1 Base'),
       TemplateLandmark(id: 'm1_art_med', label: 'M1 Articular Med', instruction: 'Mark Medial Edge of M1 Articular Surface'),
       TemplateLandmark(id: 'm1_art_lat', label: 'M1 Articular Lat', instruction: 'Mark Lateral Edge of M1 Articular Surface'),
       TemplateLandmark(id: 'm2_head', label: 'M2 Head', instruction: 'Mark Center of Metatarsal 2 Head'),
       TemplateLandmark(id: 'm2_base', label: 'M2 Base', instruction: 'Mark Center of Metatarsal 2 Base'),
       TemplateLandmark(id: 'p1_head', label: 'P1 Head', instruction: 'Mark Center of Proximal Phalanx Head'),
       TemplateLandmark(id: 'p1_base', label: 'P1 Base', instruction: 'Mark Center of Proximal Phalanx Base'),
    ],
    calculations: [
       TemplateCalculation(
         id: 'hva_angle',
         label: 'Hallux Valgus Angle',
         type: MeasurementType.cobbAngle,
         landmarkIds: ['m1_head', 'm1_base', 'p1_head', 'p1_base'],
         forceAcute: true
       ),
       TemplateCalculation(
         id: 'ima_angle',
         label: 'Intermetatarsal Angle',
         type: MeasurementType.cobbAngle,
         landmarkIds: ['m1_head', 'm1_base', 'm2_head', 'm2_base'],
         forceAcute: true
       ),
       TemplateCalculation(
         id: 'dmaa_angle',
         label: 'Distal Metatarsal Articular Angle',
         type: MeasurementType.cobbAngle,
         landmarkIds: ['m1_head', 'm1_base', 'm1_art_med', 'm1_art_lat'],
         forceAcute: true
       ),
    ],
    isPremium: true,
  ),
  MeasurementTemplate(
    id: 'carrying_angle',
    title: 'Carrying Angle',
    viewInfo: 'AP Elbow',
    category: JointCategory.elbow,
    icon: mat.Icons.pan_tool_outlined,
    infoDescription: desc.TemplateDescriptions.infoDescriptions['carrying_angle'],
    landmarks: [
       TemplateLandmark(id: 'humerus_prox', label: 'Humerus Mid-Shaft', instruction: 'Mark Center of Humerus Shaft (Proximal)'),
       TemplateLandmark(id: 'humerus_dist', label: 'Humerus Distal', instruction: 'Mark Center of Humerus Distal End (Elbow Center)'),
       TemplateLandmark(id: 'ulna_prox', label: 'Ulna Proximal', instruction: 'Mark Center of Ulna Proximal End (Elbow)'),
       TemplateLandmark(id: 'ulna_dist', label: 'Ulna Distal', instruction: 'Mark Center of Ulna Distal Styloid'),
    ],
    calculations: [
       TemplateCalculation(
         id: 'carrying_angle',
         label: 'Carrying Angle',
         type: MeasurementType.cobbAngle,
         landmarkIds: ['humerus_prox', 'humerus_dist', 'ulna_prox', 'ulna_dist'],
         forceAcute: true
       ),
    ],
    isPremium: true,
  ),
  MeasurementTemplate(
    id: 'spinopelvic_parameters',
    title: 'Spinopelvic Parameters',
    viewInfo: 'Lateral Standing',
    category: JointCategory.spine,
    icon: mat.Icons.format_align_center,
    infoDescription: desc.TemplateDescriptions.infoDescriptions['spinopelvic_parameters'],
    landmarks: [
       TemplateLandmark(id: 's1_post', label: 'S1 Post-Sup', instruction: 'Mark S1 Superior Endplate (Posterior Corner)'),
       TemplateLandmark(id: 's1_ant', label: 'S1 Ant-Sup', instruction: 'Mark S1 Superior Endplate (Anterior Corner)'),
       TemplateLandmark(id: 'r_hip_center', label: 'Right Hip Center', instruction: 'Mark Center of Right Femoral Head'),
       TemplateLandmark(id: 'r_hip_rim', label: 'Right Hip Rim', instruction: 'Mark Point on Right Femoral Head Circumference'),
       TemplateLandmark(id: 'l_hip_center', label: 'Left Hip Center', instruction: 'Mark Center of Left Femoral Head'),
       TemplateLandmark(id: 'l_hip_rim', label: 'Left Hip Rim', instruction: 'Mark Point on Left Femoral Head Circumference'),
    ],
    calculations: [
       TemplateCalculation(
         id: 'spinopelvic_composite',
         label: '',
         type: MeasurementType.spinopelvic,
         landmarkIds: ['s1_post', 's1_ant', 'r_hip_center', 'r_hip_rim', 'l_hip_center', 'l_hip_rim'],
       ),
    ],
    isPremium: true,
  ),

  MeasurementTemplate(
    id: 'patella_indices',
    title: 'Patella Indices',
    viewInfo: 'True Lateral',
    category: JointCategory.knee,
    icon: mat.Icons.directions_walk,
    infoDescription: desc.TemplateDescriptions.infoDescriptions['patella_indices'],
    landmarks: [
       TemplateLandmark(id: 'patella_sup', label: 'Patella Superior', instruction: 'Mark Superior Pole of Patella (Articular)'),
       TemplateLandmark(id: 'patella_inf', label: 'Patella Inferior', instruction: 'Mark Inferior Pole of Patella (Articular)'),
       TemplateLandmark(id: 'tibial_tuberosity', label: 'Tibial Tuberosity', instruction: 'Mark Tibial Tuberosity'),
       TemplateLandmark(id: 'tibial_plat_post', label: 'Tibial Plat Post', instruction: 'Mark Posterior Edge of Tibial Plateau'),
       TemplateLandmark(id: 'tibial_plat_ant', label: 'Tibial Plat Ant', instruction: 'Mark Anterior Edge of Tibial Plateau'),
    ],
    calculations: [
       TemplateCalculation(
         id: 'mis_ratio',
         label: 'Modified Insall-Salvati',
         type: MeasurementType.modifiedInsallSalvati,
         landmarkIds: ['patella_sup', 'patella_inf', 'tibial_tuberosity'],
       ),
       TemplateCalculation(
         id: 'bp_ratio',
         label: 'Blackburne-Peel',
         type: MeasurementType.blackburnePeel,
         landmarkIds: ['patella_sup', 'patella_inf', 'tibial_plat_post', 'tibial_plat_ant'],
       ),
    ],
    isPremium: true,
  ),
  MeasurementTemplate(
    id: 'flatfoot_lat',
    title: 'Flatfoot',
    viewInfo: 'Standing Lateral',
    category: JointCategory.foot,
    icon: mat.Icons.do_not_step,
    infoDescription: desc.TemplateDescriptions.infoDescriptions['flatfoot_lat'],
    landmarks: [
       TemplateLandmark(id: 'talus_prox', label: 'Talus Proximal', instruction: 'Mark Center of Talus Body'),
       TemplateLandmark(id: 'talus_dist', label: 'Talus Distal', instruction: 'Mark Center of Talus Head'),
       TemplateLandmark(id: 'm1_prox', label: 'M1 Base', instruction: 'Mark Center of M1 Base'),
       TemplateLandmark(id: 'm1_dist', label: 'M1 Head', instruction: 'Mark Center of M1 Head'),
       TemplateLandmark(id: 'calc_inf_post', label: 'Calcaneus Post Inf', instruction: 'Mark Posterior Point of Calcaneal Inferior Surface'),
       TemplateLandmark(id: 'calc_inf_ant', label: 'Calcaneus Ant Inf', instruction: 'Mark Anterior Point of Calcaneal Inferior Surface'),
    ],
    calculations: [
       TemplateCalculation(
         id: 'meary_angle',
         label: "Meary's Angle",
         type: MeasurementType.cobbAngle,
         landmarkIds: ['talus_prox', 'talus_dist', 'm1_prox', 'm1_dist'],
         forceAcute: true
       ),
       TemplateCalculation(
         id: 'calcaneal_pitch',
         label: 'Calcaneal Pitch',
         type: MeasurementType.calcanealPitch,
         landmarkIds: ['calc_inf_post', 'calc_inf_ant'], 
       ),
       TemplateCalculation(
         id: 'talocalcaneal_angle_lat',
         label: 'Talocalcaneal Angle',
         type: MeasurementType.talocalcanealAngle,
         landmarkIds: ['talus_prox', 'talus_dist', 'calc_inf_post', 'calc_inf_ant'],
       ),
    ]
  ),

  MeasurementTemplate(
    id: 'flatfoot_ap',
    title: 'Flatfoot',
    viewInfo: 'Standing AP',
    category: JointCategory.foot,
    icon: mat.Icons.personal_injury,
    infoDescription: desc.TemplateDescriptions.infoDescriptions['flatfoot_ap'],
    landmarks: [
       // TMA Axis
       TemplateLandmark(id: 'talus_axis_prox', label: 'Talus Axis Prox', instruction: 'Mark Proximal Center of Talus'),
       TemplateLandmark(id: 'talus_axis_dist', label: 'Talus Axis Dist', instruction: 'Mark Distal Center of Talus'),
       TemplateLandmark(id: 'm1_axis_base', label: 'M1 Base', instruction: 'Mark Center of M1 Base'),
       TemplateLandmark(id: 'm1_axis_head', label: 'M1 Head', instruction: 'Mark Center of M1 Head'),
       
       // TN Coverage / Uncoverage
       TemplateLandmark(id: 'talus_art_med', label: 'Talus Articular Med', instruction: 'Mark Medial Edge of Talar Head Articular Surface'),
       TemplateLandmark(id: 'talus_art_lat', label: 'Talus Articular Lat', instruction: 'Mark Lateral Edge of Talar Head Articular Surface'),
       TemplateLandmark(id: 'nav_art_med', label: 'Navicular Articular Med', instruction: 'Mark Medial Edge of Navicular Articular Surface'),
       TemplateLandmark(id: 'nav_art_lat', label: 'Navicular Articular Lat', instruction: 'Mark Lateral Edge of Navicular Articular Surface'),
       

    ],
    calculations: [
       TemplateCalculation(
         id: 'tma_angle',
         label: 'Taler-First Metatarsal Angle',
         type: MeasurementType.cobbAngle,
         landmarkIds: ['talus_axis_prox', 'talus_axis_dist', 'm1_axis_base', 'm1_axis_head'],
         forceAcute: true
       ),
       TemplateCalculation(
         id: 'tn_coverage_angle',
         label: 'Talonavicular Coverage Angle',
         type: MeasurementType.talonavicularCoverage,
         landmarkIds: ['talus_art_med', 'talus_art_lat', 'nav_art_med', 'nav_art_lat'],
       ),
        TemplateCalculation(
          id: 'tn_uncoverage_percent',
          label: 'Talonavicular Uncoverage %',
          type: MeasurementType.talonavicularUncoverage,
          landmarkIds: ['talus_art_lat', 'talus_art_med', 'nav_art_med'], 
        ),

     ]
  ),

  // AREA MEASUREMENTS (Other Category)
  

  MeasurementTemplate(
    id: 'glenoid_planning_ap',
    title: 'Glenoid Planning',
    viewInfo: 'True AP (Grashey)',
    category: JointCategory.shoulder,
    icon: mat.Icons.architecture,
    description: desc.TemplateDescriptions.shortDescriptions['glenoid_planning_ap'],
    infoDescription: desc.TemplateDescriptions.infoDescriptions['glenoid_planning_ap'],
    landmarks: [
       TemplateLandmark(id: 'ss_med', label: 'SS Fossa Med (A)', instruction: 'Place Medial point of SS Fossa'),
       TemplateLandmark(id: 'ss_lat', label: 'SS Fossa Lat (B)', instruction: 'Place Lateral point of SS Fossa'),
       TemplateLandmark(id: 'gl_inf', label: 'Glenoid Inf (C)', instruction: 'Place Inferior margin of Glenoid'),
       TemplateLandmark(id: 'gl_int', label: 'Glenoid Int (D)', instruction: 'Place Glenoid intersection point'),
       TemplateLandmark(id: 'gl_sup', label: 'Glenoid Sup (E)', instruction: 'Place Superior margin of Glenoid'),
       TemplateLandmark(id: 'ac_lat', label: 'Acromion Lat (F)', instruction: 'Place Lateral point of Acromion'),
       TemplateLandmark(id: 'maj_tub', label: 'Major Tub (G)', instruction: 'Place point on Major Tubercule'),
    ],
    calculations: [
       TemplateCalculation(
         id: 'ss_fossa_line',
         label: 'SS Fossa Line',
         type: MeasurementType.distance,
         landmarkIds: ['ss_med', 'ss_lat'],
         isAuxiliary: true,
       ),
       TemplateCalculation(
         id: 'perp_c_line',
         label: 'Perp C Line',
         type: MeasurementType.distance, 
         landmarkIds: ['gl_inf'], 
         isAuxiliary: true,
       ),
       TemplateCalculation(
         id: 'rsa',
         label: 'Reverse Shoulder Angle',
         type: MeasurementType.angle3Point,
         landmarkIds: ['ss_med', 'gl_inf', 'gl_int'], 
       ),
       TemplateCalculation(
         id: 'asa',
         label: 'Anatomic Shoulder Angle',
         type: MeasurementType.angle3Point,
         landmarkIds: ['ss_med', 'gl_inf', 'gl_sup'], 
       ),
       TemplateCalculation(
         id: 'lat_angle',
         label: 'Lateralization Angle',
         type: MeasurementType.angle3Point,
         landmarkIds: ['maj_tub', 'ac_lat', 'gl_sup'], 
       ),
       TemplateCalculation(
         id: 'dist_angle',
         label: 'Distalization Angle',
         type: MeasurementType.angle3Point,
         landmarkIds: ['ac_lat', 'gl_sup', 'maj_tub'], 
       ),
    ],
    isPremium: true,
  ),

  MeasurementTemplate(
    id: 'fai_pelvis',
    title: 'FAI – AP Pelvis',
    viewInfo: 'AP Pelvis',
    category: JointCategory.hip,
    icon: mat.Icons.accessibility,
    infoDescription: desc.TemplateDescriptions.infoDescriptions['fai_pelvis'],
    landmarks: [
       // Pelvic Orientation
       TemplateLandmark(id: 'teardrop_r', label: 'Right Teardrop', instruction: 'Mark Inferior point of Right Teardrop (Pelvic Ref)'),
       TemplateLandmark(id: 'teardrop_l', label: 'Left Teardrop', instruction: 'Mark Inferior point of Left Teardrop (Pelvic Ref)'),
       
       // Femoral Head (Circle Method ideally, but let's use 3 points for circle)
       TemplateLandmark(id: 'fh_1', label: 'Head Cortex 1', instruction: 'Mark a point on Femoral Head cortex'),
       TemplateLandmark(id: 'fh_2', label: 'Head Cortex 2', instruction: 'Mark a point on Femoral Head cortex'),
       TemplateLandmark(id: 'fh_3', label: 'Head Cortex 3', instruction: 'Mark a point on Femoral Head cortex'),

       // Sourcil
       TemplateLandmark(id: 'sourcil_med', label: 'Medial Sourcil', instruction: 'Mark Medial Edge of Weight-Bearing Dome'),
       TemplateLandmark(id: 'sourcil_lat', label: 'Lateral Sourcil', instruction: 'Mark Lateral Edge of Weight-Bearing Dome'),

       // Walls (2 points each for lines) - REMOVED per user request
    ],
    calculations: [
       TemplateCalculation(
         id: 'pelvic_ref_line',
         label: 'Pelvic Axis',
         type: MeasurementType.distance, // Using distance type to draw a line, but logic will treat as Ref
         landmarkIds: ['teardrop_r', 'teardrop_l'],
         isAuxiliary: true, // Show line but maybe don't clutter results
       ),
       TemplateCalculation(
         id: 'fh_circle',
         label: 'Femoral Head',
         type: MeasurementType.circle3Point,
         landmarkIds: ['fh_1', 'fh_2', 'fh_3'],
         isAuxiliary: true, // We need Center C
       ),
       TemplateCalculation(
         id: 'lcea_angle',
         label: 'LCEA',
         type: MeasurementType.lcea,
         landmarkIds: ['teardrop_r', 'teardrop_l', 'fh_1', 'fh_2', 'fh_3', 'sourcil_lat'], // Need Ref + C + Lat
         // Notes: Passing 3 circle points allows re-calculation of center. 
         // Or we can assume the screen logic will find the 'fh_circle' measurement?
         // For stateless calculation, passing all 6 points is safer.
       ),
       TemplateCalculation(
         id: 'tonnis_angle',
         label: 'Tönnis Angle',
         type: MeasurementType.tonnisAngle,
         landmarkIds: ['teardrop_r', 'teardrop_l', 'sourcil_med', 'sourcil_lat'],
       ),
    ],
    isPremium: true,
  ),
  MeasurementTemplate(
    id: 'carpal_alignment',
    title: 'Carpal Alignment',
    viewInfo: 'Wrist AP X-Ray',
    category: JointCategory.hand,
    icon: mat.Icons.back_hand,
    infoDescription: desc.TemplateDescriptions.infoDescriptions['carpal_alignment'],
    landmarks: [
       TemplateLandmark(id: 'radius_axis_prox', label: 'Radius Shaft Prox', instruction: 'Mark Proximal Center of Radius Shaft'),
       TemplateLandmark(id: 'radius_axis_dist', label: 'Radius Shaft Dist', instruction: 'Mark Distal Center of Radius Shaft'),
       TemplateLandmark(id: 'ulna_distal', label: 'Ulna Distal', instruction: 'Mark Most Distal Point of Ulna Articular Surface'),
       TemplateLandmark(id: 'radius_lunate_fossa', label: 'Radius Lunate Fossa', instruction: 'Mark Most Distal Point of Radius Lunate Fossa'),
       TemplateLandmark(id: 'radial_styloid', label: 'Radial Styloid', instruction: 'Mark Tip of Radial Styloid'),
       TemplateLandmark(id: 'radius_ulnar_corner', label: 'Radius Ulnar Corner', instruction: 'Mark Ulnar Corner of Distal Radius'),
    ],
    calculations: [
       TemplateCalculation(
         id: 'ulnar_variance',
         label: 'Ulnar Variance',
         type: MeasurementType.ulnarVariance,
         landmarkIds: const ['radius_axis_prox', 'radius_axis_dist', 'ulna_distal', 'radius_lunate_fossa'],
       ),
       TemplateCalculation(
         id: 'radial_inclination',
         label: 'Radial Inclination',
         type: MeasurementType.radialInclination,
         landmarkIds: const ['radial_styloid', 'radius_ulnar_corner', 'radius_axis_prox', 'radius_axis_dist'], 
       ),
       TemplateCalculation(
         id: 'radial_height',
         label: 'Radial Height',
         type: MeasurementType.radialHeight,
         landmarkIds: const ['radial_styloid', 'radius_lunate_fossa', 'radius_axis_prox', 'radius_axis_dist'],
       ),
    ],
    isPremium: true,
  ),
  MeasurementTemplate(
    id: 'carpal_sagittal_alignment',
    title: 'Carpal Sagittal Alignment',
    viewInfo: 'Lateral Wrist X-Ray',
    category: JointCategory.hand,
    icon: mat.Icons.back_hand,
    infoDescription: desc.TemplateDescriptions.infoDescriptions['carpal_sagittal_alignment'],
    landmarks: [
       TemplateLandmark(id: 'scaphoid_prox', label: 'Scaphoid Proximal', instruction: 'Mark Proximal Center of Scaphoid Axis'),
       TemplateLandmark(id: 'scaphoid_dist', label: 'Scaphoid Distal', instruction: 'Mark Distal Center of Scaphoid Axis'),
       TemplateLandmark(id: 'lunate_prox', label: 'Lunate Proximal', instruction: 'Mark Proximal Center of Lunate Axis'),
       TemplateLandmark(id: 'lunate_dist', label: 'Lunate Distal', instruction: 'Mark Distal Center of Lunate Axis'),
       TemplateLandmark(id: 'capitate_prox', label: 'Capitate Proximal', instruction: 'Mark Proximal Center of Capitate Axis'),
       TemplateLandmark(id: 'capitate_dist', label: 'Capitate Distal', instruction: 'Mark Distal Center of Capitate Axis'),
       TemplateLandmark(id: 'radius_axis_prox', label: 'Radius Shaft Prox', instruction: 'Mark Proximal Center of Radius Shaft'),
       TemplateLandmark(id: 'radius_axis_dist', label: 'Radius Shaft Dist', instruction: 'Mark Distal Center of Radius Shaft'),
       TemplateLandmark(id: 'radius_dorsal_lip', label: 'Radius Dorsal Lip', instruction: 'Mark Dorsal Lip of Distal Radius'),
       TemplateLandmark(id: 'radius_volar_lip', label: 'Radius Volar Lip', instruction: 'Mark Volar Lip of Distal Radius'),
    ],
    calculations: [
       TemplateCalculation(
         id: 'scapholunate_angle',
         label: 'Scapholunate Angle',
         type: MeasurementType.scapholunateAngle,
         landmarkIds: const ['scaphoid_prox', 'scaphoid_dist', 'lunate_prox', 'lunate_dist'],
       ),
       TemplateCalculation(
         id: 'capitolunate_angle',
         label: 'Capitolunate Angle',
         type: MeasurementType.capitolunateAngle,
         landmarkIds: const ['capitate_prox', 'capitate_dist', 'lunate_prox', 'lunate_dist'],
       ),
       TemplateCalculation(
         id: 'volar_tilt',
         label: 'Volar Tilt',
         type: MeasurementType.volarTilt,
         landmarkIds: const ['radius_axis_prox', 'radius_axis_dist', 'radius_dorsal_lip', 'radius_volar_lip'],
       ),
    ],
    isPremium: true,
  ),
  MeasurementTemplate(
    id: 'lower_limb_deformity',
    title: 'Lower Limb Deformity',
    viewInfo: 'Standing AP Long-Leg',
    category: JointCategory.other,
    icon: mat.Icons.category,
    description: desc.TemplateDescriptions.shortDescriptions['lower_limb_deformity'],
    infoDescription: desc.TemplateDescriptions.infoDescriptions['lower_limb_deformity'],
    landmarks: [
      TemplateLandmark(id: 'femur_head_center', label: 'Femur Head Center', instruction: 'Mark center of femoral head'),
      TemplateLandmark(id: 'femur_shaft_prox', label: 'Femur Shaft Proximal', instruction: 'Mark center of proximal femur shaft'),
      TemplateLandmark(id: 'femur_shaft_dist', label: 'Femur Shaft Distal', instruction: 'Mark center of distal femur shaft'),
      TemplateLandmark(id: 'femur_condyle_med', label: 'Medial Femoral Condyle', instruction: 'Mark most distal point of medial femoral condyle'),
      TemplateLandmark(id: 'femur_condyle_lat', label: 'Lateral Femoral Condyle', instruction: 'Mark most distal point of lateral femoral condyle'),
      TemplateLandmark(id: 'knee_center', label: 'Knee Center', instruction: 'Mark center of knee joint'),
      TemplateLandmark(id: 'tibia_plateau_med', label: 'Medial Tibial Plateau', instruction: 'Mark medial corner of tibial plateau'),
      TemplateLandmark(id: 'tibia_plateau_lat', label: 'Lateral Tibial Plateau', instruction: 'Mark lateral corner of tibial plateau'),
      TemplateLandmark(id: 'tibia_shaft_prox', label: 'Tibia Shaft Proximal', instruction: 'Mark center of proximal tibia shaft'),
      TemplateLandmark(id: 'tibia_shaft_dist', label: 'Tibia Shaft Distal', instruction: 'Mark center of distal tibia shaft'),
      TemplateLandmark(id: 'ankle_center', label: 'Ankle Center', instruction: 'Mark center of talus/ankle'),
    ],
    calculations: [], // Modular template handles calculations logic
    isPremium: true,
  ),
  MeasurementTemplate(
    id: 'knee_sagittal_balance',
    title: 'Knee Arthroplasty – Sagittal Balance',
    viewInfo: 'Lateral Knee Radiograph',
    category: JointCategory.knee,
    icon: mat.Icons.straighten,
    description: desc.TemplateDescriptions.shortDescriptions['knee_sagittal_balance'],
    infoDescription: desc.TemplateDescriptions.infoDescriptions['knee_sagittal_balance'],
    landmarks: [
      TemplateLandmark(id: 'femur_shaft_prox', label: 'Femur Shaft Proximal', instruction: 'Mark center of proximal femur shaft'),
      TemplateLandmark(id: 'femur_shaft_dist', label: 'Femur Shaft Distal', instruction: 'Mark center of distal femur shaft'),
      TemplateLandmark(id: 'femur_comp_ant', label: 'Femoral Distal Surface Anterior', instruction: 'Mark anterior point of the femoral component\'s distal flat surface'),
      TemplateLandmark(id: 'femur_comp_post', label: 'Femoral Distal Surface Posterior', instruction: 'Mark posterior point of the femoral component\'s distal flat surface'),
      TemplateLandmark(id: 'post_condyle', label: 'Posterior Condyle Edge', instruction: 'Mark most posterior point of femoral component contour'),
      TemplateLandmark(id: 'tibia_comp_ant', label: 'Tibial Component Anterior', instruction: 'Mark anterior edge of tibial component surface'),
      TemplateLandmark(id: 'tibia_comp_post', label: 'Tibial Component Posterior', instruction: 'Mark posterior edge of tibial component surface'),
      TemplateLandmark(id: 'tibia_shaft_prox', label: 'Tibia Shaft Proximal', instruction: 'Mark center of proximal tibia shaft'),
      TemplateLandmark(id: 'tibia_shaft_dist', label: 'Tibia Shaft Distal', instruction: 'Mark center of distal tibia shaft'),
    ],
    calculations: [], // Modular template handles calculations logic
    isPremium: true,
  ),
];

