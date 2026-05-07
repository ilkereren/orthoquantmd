import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ortho_quant_md/services/history_service.dart';
import 'package:ortho_quant_md/services/settings_service.dart';
import 'package:ortho_quant_md/services/subscription_service.dart';
import 'package:ortho_quant_md/screens/paywall_screen.dart';
import 'package:flutter/services.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  // Public Keys
  static const String kSaveToCameraRollKey = 'save_to_camera_roll';
  static const String kStyleTextBoldKey = 'style_text_bold';
  static const String kStyleTextSizeKey = 'style_text_size';
  static const String kStyleLineThicknessKey = 'style_line_thickness';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _saveToCameraRoll = false;

  // Style State
  bool _textBold = false;
  double _textSize = 16.0;
  double _lineThickness = 2.0;
  double _landmarkSize = 4.0;
  bool _autoZoomEnabled = true;

  // Stats
  final HistoryService _historyService = HistoryService();
  Map<String, int> _stats = {'storage': 0, 'exams': 0, 'measurements': 0, 'lifetime_exams': 0};
  bool _loadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadStats();
  }
  
  String _appUserId = 'Loading...';

  Future<void> _loadStats() async {
    final stats = await _historyService.getAppUsageStatistics();
    final userId = await SubscriptionService().getAppUserId();
    if (mounted) {
      setState(() {
        _stats = stats;
        _loadingStats = false;
        _appUserId = userId;
      });
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    // Load local toggle
    setState(() {
      _saveToCameraRoll = prefs.getBool(SettingsScreen.kSaveToCameraRollKey) ?? false;
    });
    
    // Load Global Styles from Service
    await SettingsService().loadSettings();
    setState(() {
      _textBold = SettingsService().textBold;
      _textSize = SettingsService().textSize;
      _lineThickness = SettingsService().lineThickness;
      _landmarkSize = SettingsService().landmarkSize;
      _autoZoomEnabled = SettingsService().autoZoomEnabled;
    });
  }

  Future<void> _toggleSave(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsScreen.kSaveToCameraRollKey, value);
    setState(() {
      _saveToCameraRoll = value;
    });
  }
  


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/home_bg.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Subscription Section
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  SubscriptionService().isPro ? 'PRO STATUS ACTIVE' : 'UPGRADE TO PRO',
                  style: TextStyle(
                    color: SubscriptionService().isPro ? Colors.amber : const Color(0xFF00BFA5),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                subtitle: Text(
                  SubscriptionService().isPro 
                    ? 'You have unlimited access to all features.' 
                    : 'Unlock advanced templates and PDF reports.',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                trailing: Icon(
                  SubscriptionService().isPro ? Icons.verified : Icons.chevron_right,
                  color: SubscriptionService().isPro ? Colors.amber : const Color(0xFF00BFA5),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PaywallScreen()),
                  ).then((_) => setState(() {})); // Refresh status if changed
                },
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white24),
              const SizedBox(height: 16),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: SwitchListTile(
                  title: const Text(
                    'Save original to Camera Roll',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Captured photos are saved in their raw format for later access. Measurements are not included.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  value: _saveToCameraRoll,
                  activeThumbColor: const Color(0xFF00BFA5),
                  onChanged: _toggleSave,
                ),
              ),
              
              const SizedBox(height: 32),
              const Divider(color: Colors.white24),
              const SizedBox(height: 16),
              const Text(
                'Measurement Style',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              Container(

                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    // Bold Toggle
                    SwitchListTile(
                      title: const Text('Bold Labels', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      value: _textBold,
                      activeThumbColor: const Color(0xFF00BFA5),
                      onChanged: (val) {
                         setState(() => _textBold = val);
                         SettingsService().updateTextBold(val);
                      },
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    
                    // Text Size Slider
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                               const Text('Font Size', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                               Text('${_textSize.toInt()}', style: const TextStyle(color: Colors.white70)),
                            ],
                          ),
                          Slider(
                            value: _textSize,
                            min: 10.0,
                            max: 30.0,
                            divisions: 20,
                            activeColor: const Color(0xFF00BFA5),
                            inactiveColor: Colors.white24,
                            label: '${_textSize.toInt()}',
                            onChanged: (val) {
                               setState(() => _textSize = val);
                               SettingsService().updateTextSize(val);
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),

                    // Landmark Size Slider
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                               const Text('Landmark Pointer Size', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                               Text(_getLandmarkSizeLabel(_landmarkSize), style: const TextStyle(color: Colors.white70)),
                            ],
                          ),
                          Slider(
                            value: _getLandmarkSizeLevel(_landmarkSize),
                            min: 1.0,
                            max: 4.0,
                            divisions: 3,
                            activeColor: const Color(0xFF00BFA5),
                            inactiveColor: Colors.white24,
                            onChanged: (val) {
                               final realSize = _getRealLandmarkSize(val);
                               setState(() => _landmarkSize = realSize);
                               SettingsService().updateLandmarkSize(realSize);
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    
                    // Line Thickness Selector
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                           const Text('Line Thickness', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                           const SizedBox(height: 12),
                           Row(
                             mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                             children: [
                               _buildChoiceChip('Thin', 2.0),
                               _buildChoiceChip('Medium', 5.0),
                               _buildChoiceChip('Thick', 8.0),
                             ],
                           ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),  const SizedBox(height: 16),
              
              // Smart Zoom Toggle
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: SwitchListTile(
                  title: const Text(
                    'Smart Zoom (Auto)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Hold for 1.2 seconds to automatically zoom x2.2 for precise adjustment.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  value: _autoZoomEnabled,
                  activeThumbColor: const Color(0xFF00BFA5),
                  onChanged: (val) {
                    setState(() => _autoZoomEnabled = val);
                    SettingsService().setAutoZoomEnabled(val);
                  },
                ),
              ),

              const SizedBox(height: 32),
              const Divider(color: Colors.white24),
              const SizedBox(height: 16),
              const Text(
                'App Statistics',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              // Statistics Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: _loadingStats 
                   ? const Center(child: CircularProgressIndicator(color: Colors.white))
                   : Column(
                      children: [
                        _buildStatRow('Storage Used', _formatBytes(_stats['storage']!)),
                        const Divider(color: Colors.white10),
                        _buildStatRow('Active Exams (History)', '${_stats['exams']}'),
                        const Divider(color: Colors.white10),
                        _buildStatRow('Lifetime Total Exams', '${_stats['lifetime_exams']}'),
                        const Divider(color: Colors.white10),
                        _buildStatRow('Total Measurements', '${_stats['measurements']}'),
                      ],
                   ),
              ),
              
              const SizedBox(height: 32),
              const Divider(color: Colors.white24),
              const SizedBox(height: 16),
              const Text(
                'Support',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              // App User ID for Debugging
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('App User ID', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            _appUserId,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, color: Colors.white54, size: 20),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _appUserId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('User ID copied to clipboard'), duration: Duration(seconds: 1)),
                            );
                          },
                        ),
                      ],
                    ),
                    const Text(
                      'Use this ID in RevenueCat to grant manual PRO access.',
                      style: TextStyle(color: Colors.white38, fontSize: 10, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
              
              // Version History Tile
               Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: ListTile(
                  leading: const Icon(Icons.update, color: Colors.white),
                  title: const Text(
                    'Version History',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'See what\'s new in the latest update.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  onTap: () => _showVersionHistory(context),
                ),
              ),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: ListTile(
                  leading: const Icon(Icons.replay_rounded, color: Colors.white),
                  title: const Text(
                    'Reactivate Tutorial',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Show the guided tour again on the Home Screen.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('home_tutorial_shown_v1', false);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Tutorial reactivated. It will appear on next Home Screen visit."),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 48), // Bottom padding
            ],
          ),
        ),
      ),
    );
  }

  String _getLandmarkSizeLabel(double size) {
    if (size <= 2.5) return 'Small';
    if (size <= 3.5) return 'Medium';
    if (size <= 4.5) return 'Large';
    return 'Extra Large';
  }

  double _getLandmarkSizeLevel(double size) {
    if (size <= 2.5) return 1.0; // Small (was 2.0)
    if (size <= 3.5) return 2.0; // Medium (was 3.0)
    if (size <= 4.5) return 3.0; // Large (was 4.0)
    return 4.0; // Extra Large (was 6.0+)
  }

  double _getRealLandmarkSize(double level) {
    switch (level.toInt()) {
      case 1: return 2.0; // Small
      case 2: return 3.0; // Medium
      case 3: return 4.0; // Large
      case 4: return 6.0; // Extra Large
      default: return 2.0;
    }
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 16)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
  
  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    // Better logic:
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }
  Widget _buildChoiceChip(String label, double value) {
     final bool selected = _lineThickness == value;
     return InkWell(
         onTap: () {
            setState(() => _lineThickness = value);
            SettingsService().updateLineThickness(value);
         },
        child: Container(
           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
           decoration: BoxDecoration(
              color: selected ? const Color(0xFF00BFA5) : Colors.white10,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? const Color(0xFF00BFA5) : Colors.white30),
           ),
           child: Text(
             label,
             style: TextStyle(
               color: selected ? Colors.black : Colors.white,
               fontWeight: FontWeight.bold,
             ),
           ),
        ),
     );
  }

  void _showVersionHistory(BuildContext context) {
    final List<Map<String, dynamic>> history = [
      {
        'version': 'v0.6.7',
        'date': 'Jan 2026',
        'changes': [
          'Minor bug fixes and rendering refinements.',
        ]
      },
      {
        'version': 'v0.6.6',
        'date': 'Jan 2026',
        'changes': [
          'Fixed a rendering issue where Distance tool lines were not visible.',
          'Improved landmark visualization by removing redundant cross markers.',
          'Simplified template UX by starting results in an unlocked state.',
        ]
      },
      {
        'version': 'v0.6.5',
        'date': 'Jan 2026',
        'changes': [
          'Comprehensive Analysis: Introduced Lower Limb Deformity Analysis (LLDA) for full leg radiographs.',
          'Clinical Excellence: Updated all modular templates with precise clinical definitions, normal ranges, and severity grading.',
          'Scientific Foundation: Added international clinical references (Bellemans, Paley, StatPearls, etc.) across all joint categories.',
          'Contribute & Earn: Reward program added to win 1 Month of PRO access by suggesting new clinical templates.',
          'Professional Standardization: Unified methodology for millimeter conversions (pixelsPerMm) across all clinical templates.',
          'Knee Arthroplasty Clarity: Expanded PTS, FCFA, and PFCO abbreviations to full clinical names in Sagittal Balance results.',
          'Export Branding: Added subtle "OrthoQuant MD" watermark to all shared measurement images.',
          'Modular Integrity: Ensured results boxes for all categories (Hip, Knee, Shoulder, etc.) are correctly rendered in exports.',
        ]
      },
      {
        'version': 'v0.6.4',
        'date': 'Jan 2026',
        'changes': [
          'UI Fix: Added horizontal scrolling to the top measurement menu to prevent overflow on narrow screens.',
          'Professional Labels: Expanded all template abbreviations (IMA, TMA, SS, PT, BP etc.) to full clinical names for better clarity.',
          'Visual Standard: Implemented "Solid Core + Dashed Extension" rule for all infinite lines in modular templates.',
          'Enhanced Shoulder Visualization: Restored dashed medialization lines in Glenoid Axial analysis.',
        ]
      },
      {
        'version': 'v0.6.3',
        'date': 'Jan 2026',
        'changes': [
          'Modular Template Architecture: Complete system migration for all joint categories (Hip, Shoulder, Knee, Foot, Spine, Elbow).',
          'Integrated "FAI Pelvis" template with LCEA and Tönnis Angle calculations.',
          'Standardized Results Display: Unified draggable results box for all modular templates.',
          'Enhanced Shoulder Templates: Added Glenoid Bone Loss, Axial Analysis, and Planning tools.',
        ]
      },
      {
        'version': 'v0.6.2',
        'date': 'Jan 2026',
        'changes': [
          'Share Extension Fix: Reliable image sharing from iOS Photos app.',
          'Simplified UI: Removed Undo button for cleaner interface.',
          'UX Improvement: Draggable Calibration Button for easier positioning.',
          'Visual Enhancements: Increased Magnifier brightness (+25%) for better clarity.',
          'Stability: Fixed issue with old shared files reappearing (Ghosting).',
          'Notification Support: Fallback notifications ensuring app opens on share.',
        ]
      },
      {
        'version': 'v0.6.1',
        'date': 'Jan 2026',
        'changes': [
          'Drag & Drop Import: Drag radiographic images directly into the window or onto the app icon.',
          'Native File Associations: Open images with OrthoQuant MD from Finder or Dock.',
          'iOS Share Extension: Open images directly from Photos app via Share menu.',
          'HEIC Support: Added compatibility for High Efficiency Image Format (Apple Photos).',
          'Educational Tips: New helpful tips for faster clinical workflows.',
        ]
      },
      {
        'version': 'v0.6.0',
        'date': 'Dec 2025',
        'changes': [
          'History Grouping: Organize measurements into folders (PRO).',
          'MacOS Support: Full compatibility with Apple Silicon Macs.',
          'Responsive Smart Zoom: Quicker activation (1.2s delay).',
          'Privacy Compliance: New dedicated local data storage policies.',
        ]
      },
      {
        'version': 'v0.5.2',
        'date': 'Dec 2025',
        'changes': [
          'Full RevenueCat Integration (Apple Subscriptions).',
          'Resolved Entitlement ID mismatch for PRO access.',
          'Refactored Paywall for specific device compatibility (iPhone XR).',
          'Centralized template results for a cleaner measurement UI.',
        ]
      },
      {
        'version': 'v0.5.1',
        'date': 'Dec 2025',
        'changes': [
          'Smart Zoom v2.0: Higher precision (2.2x) with auto-trigger.',
          'Instant Point Placement: Removed tap delay.',
          'Fixed Settings persistence for styles.',
        ]
      },
      {
        'version': 'v0.5.0',
        'date': 'Dec 2025',
        'changes': [
          'Introduced PRO Subscription Model.',
          'Advanced Clinical Templates (Glenoid, Spinopelvic).',
          'Professional PDF Report generation.',
          'Flexible Image Boundaries (50% displacement).',
        ]
      },
      {
        'version': 'v0.4.0',
        'date': 'Nov 2025',
        'changes': [
          'Multi-device support (iPad Stability).',
          'Custom Measurement Styles (Line thickness, Font size).',
          'New Horizontal Category Menu.',
          'Automated tool deselection.',
        ]
      }
    ];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded, color: Color(0xFF00BFA5), size: 28),
                    const SizedBox(width: 12),
                    const Text(
                      'Release Notes',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: history.map((item) => _buildVersionTimelineItem(item)).toList(),
                  ),
                ),
              ),
              
              // Footer
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'CLOSE',
                      style: TextStyle(color: Color(0xFF00BFA5), fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVersionTimelineItem(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline Indicator
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: item['version'] == 'v0.6.7' ? const Color(0xFF00BFA5) : Colors.white24,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white12, width: 2),
                ),
              ),
              Container(
                width: 1,
                height: 80, // Approximate height for content
                color: Colors.white12,
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item['version'],
                      style: TextStyle(
                        color: item['version'] == 'v0.6.7' ? const Color(0xFF00BFA5) : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      item['date'],
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...(item['changes'] as List<String>).map((change) => Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6.0),
                        child: Icon(Icons.circle, size: 4, color: Colors.white54),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          change,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
