import 'base/measurement_template_base.dart';
import 'hip/fai_pelvis_template.dart';
import 'hip/tha_cup_position_template.dart';
import 'shoulder/acromion_indices_template.dart';
import 'shoulder/glenoid_axial_template.dart';
import 'shoulder/glenoid_bone_loss_template.dart';
import 'shoulder/glenoid_planning_ap_template.dart';
import 'elbow/carrying_angle_template.dart';
import 'foot/hallux_valgus_template.dart';
import 'foot/flatfoot_lat_template.dart';
import 'foot/flatfoot_ap_template.dart';
import 'foot/calcaneus_angles_template.dart';
import 'spine/spinopelvic_template.dart';
import 'spine/cervical_spine_lateral_template.dart';
import 'spine/spondylolisthesis_template.dart';
import 'knee/patella_indices_template.dart';
import 'knee/knee_sagittal_balance_template.dart';
import 'knee/tka_coronal_alignment_template.dart';
import 'hand/carpal_alignment_template.dart';
import 'hand/carpal_sagittal_alignment_template.dart';
import 'general/lower_limb_deformity_template.dart';

class TemplateRegistry {
  static final List<MeasurementTemplateBase> _templates = [
    // Hip
    FaiPelvisTemplate(),
    ThaCupPositionTemplate(),
    // Shoulder
    AcromionIndicesTemplate(),
    GlenoidAxialTemplate(),
    GlenoidBoneLossTemplate(),
    GlenoidPlanningApTemplate(),
    // Elbow
    CarryingAngleTemplate(),
    // Hand
    CarpalAlignmentTemplate(),
    CarpalSagittalAlignmentTemplate(),
    // Foot
    HalluxValgusTemplate(),
    FlatfootLatTemplate(),
    FlatfootApTemplate(),
    CalcaneusAnglesTemplate(),
    // Spine
    SpinopelvicTemplate(),
    CervicalSpineLateralTemplate(),
    SpondylolisthesisTemplate(),
    // Knee
    PatellaIndicesTemplate(),
    KneeSagittalBalanceTemplate(),
    TkaCoronalAlignmentTemplate(),
    // Other
    LowerLimbDeformityTemplate(),
  ];

  static List<MeasurementTemplateBase> get all => List.unmodifiable(_templates);

  static MeasurementTemplateBase? getById(String id) {
    try {
      return _templates.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }
}
