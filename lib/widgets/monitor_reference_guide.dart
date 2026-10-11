import 'package:flutter/material.dart';

const _accent = Color(0xFF00BFA5);
const _cornerColor = Color(0xFFFFD766);

/// Where the first photo of a multi-image measurement comes from.
enum MonitorPhotoSource { camera, gallery }

/// Explains how to photograph the monitor for a multi-image measurement and
/// returns where the first photo should come from (null when dismissed).
///
/// The monitor's corners are the shared reference that aligns the photos.
/// [steps] lists the template's images (which slice, what is marked);
/// [canTakePhoto] is false where there is no camera (desktop).
Future<MonitorPhotoSource?> showMonitorReferenceGuide(
  BuildContext context, {
  bool canTakePhoto = true,
  List<({String title, String detail})> steps = const [],
}) {
  return _showPhotoGuide(
    context,
    canTakePhoto: canTakePhoto,
    steps: steps,
    icon: Icons.monitor_outlined,
    title: 'Before you take the photos',
    intro:
        'This method measures across consecutive slices, so how the images '
        'are captured matters. Two photos of a screen are never taken '
        'from exactly the same spot. If one photo is shifted, tilted or '
        'closer than the other, the slices no longer line up and every '
        'measurement between them is wrong. OrthoQuant straightens each '
        'photo using the corners of the monitor, so both line up exactly.',
    rules: const [
      _GuideRule(
        number: 1,
        title: 'Keep the whole monitor in every photo',
        detail: 'All four corners of the screen must be visible.',
      ),
      _GuideRule(
        number: 2,
        title: 'Change slices only by scrolling',
        detail:
            'Do not pan or zoom the viewer between the photos, so both slices '
            'stay in the same place on the screen.',
      ),
      _GuideRule(
        number: 3,
        title: 'Drag the corners onto the monitor',
        detail:
            'After each photo, place the four corner handles exactly on the '
            'corners of the screen. The photo is straightened from them, '
            'whatever the distance or angle of the camera.',
      ),
      _GuideRule(
        number: 4,
        title: 'Start with new photos',
        detail:
            'To follow these rules, we will start by choosing the images '
            'again.',
      ),
    ],
    example: const MonitorReferenceExample(),
  );
}

Future<MonitorPhotoSource?> _showPhotoGuide(
  BuildContext context, {
  required bool canTakePhoto,
  required IconData icon,
  required String title,
  required String intro,
  required List<Widget> rules,
  List<({String title, String detail})> steps = const [],
  Widget? example,
}) {
  return showModalBottomSheet<MonitorPhotoSource>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF17191D),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(icon, color: _accent, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                intro,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              if (steps.isNotEmpty) ...[
                const Text(
                  'What you will do',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                for (final step in steps)
                  _GuideStep(title: step.title, detail: step.detail),
                const SizedBox(height: 8),
                const Text(
                  'Taking the photos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              ...rules,
              if (example != null) ...[
                const SizedBox(height: 6),
                const Text(
                  'Example',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                example,
              ],
              const SizedBox(height: 20),
              if (canTakePhoto) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        Navigator.pop(sheetContext, MonitorPhotoSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text(
                      'Take Photo',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(sheetContext, MonitorPhotoSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded),
                  label: Text(
                    canTakePhoto ? 'Choose from Gallery' : 'Choose Image',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: const BorderSide(color: _accent),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// One image of the template in the guide: which slice, what is marked.
class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 12, top: 1),
            child: Icon(Icons.image_outlined, color: _cornerColor, size: 22),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideRule extends StatelessWidget {
  const _GuideRule({
    required this.number,
    required this.title,
    required this.detail,
  });

  final int number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(right: 12, top: 1),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A monitor showing an axial CT slice, with the four screen corners
/// marked as the reference points.
class MonitorReferenceExample extends StatelessWidget {
  const MonitorReferenceExample({super.key});

  static const _marker = 22.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Bezel
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF2B2E33),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF41454C)),
          ),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: LayoutBuilder(
              builder: (context, box) {
                final corners = [
                  Offset.zero,
                  Offset(box.maxWidth, 0),
                  Offset(box.maxWidth, box.maxHeight),
                  Offset(0, box.maxHeight),
                ];
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Screen with the viewer showing one slice.
                    Positioned.fill(
                      child: Container(
                        color: Colors.black,
                        padding: const EdgeInsets.all(6),
                        child: Image.asset(
                          'assets/images/multi_image_example_axial_ct.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    for (var i = 0; i < corners.length; i++)
                      Positioned(
                        left: corners[i].dx - _marker / 2,
                        top: corners[i].dy - _marker / 2,
                        child: _CornerMarker(number: i + 1),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        // Stand
        Container(width: 16, height: 18, color: const Color(0xFF2B2E33)),
        Container(
          width: 90,
          height: 6,
          decoration: BoxDecoration(
            color: const Color(0xFF2B2E33),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Reference points: the four corners of the screen',
          style: TextStyle(color: _cornerColor, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _CornerMarker extends StatelessWidget {
  const _CornerMarker({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MonitorReferenceExample._marker,
      height: MonitorReferenceExample._marker,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _cornerColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Text(
        '$number',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
