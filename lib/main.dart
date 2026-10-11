import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ortho_quant_md/screens/camera_screen.dart';
import 'package:ortho_quant_md/screens/measurement_screen.dart';
import 'package:ortho_quant_md/screens/history_screen.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart'; // Added for temp directory

import 'package:image_cropper/image_cropper.dart';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';
import 'package:ortho_quant_md/data/tips_list.dart'; // Import the tips list
import 'package:receive_sharing_intent/receive_sharing_intent.dart'; // New import
import 'package:ortho_quant_md/screens/settings_screen.dart'; // Import SettingsScreen
import 'package:ortho_quant_md/screens/survey_screen.dart';
import 'package:gal/gal.dart'; // Import for saving to gallery
import 'package:shared_preferences/shared_preferences.dart'; // Import for prefs
import 'package:url_launcher/url_launcher.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart'; // Import tutorial package
import 'package:ortho_quant_md/services/settings_service.dart'; // Import SettingsService
import 'package:ortho_quant_md/services/subscription_service.dart';
import 'package:flutter/services.dart' show rootBundle, MethodChannel;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';

List<CameraDescription> cameras = [];

bool get _supportsCameraPlugin {
  if (kIsWeb) return true;
  return Platform.isAndroid || Platform.isIOS;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    final isMacOS = Platform.isMacOS;
    final windowOptions = WindowOptions(
      size: isMacOS
          ? const Size(1180, 820)
          : const Size(402, 874), // iPhone 16 Pro approx logical resolution
      minimumSize: isMacOS ? const Size(780, 560) : const Size(402, 874),
      center: true,
      title: 'OrthoQuant MD',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  if (_supportsCameraPlugin) {
    try {
      cameras = await availableCameras();
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  // Load Settings and Subscriptions globally
  await SettingsService().loadSettings();
  await SubscriptionService().init();

  runApp(const OrthoQuantApp());
}

// Global Route Observer
final RouteObserver<ModalRoute<void>> pathObserver =
    RouteObserver<ModalRoute<void>>();

class OrthoQuantApp extends StatelessWidget {
  const OrthoQuantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OrthoQuantMD',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [pathObserver],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00BFA5), // Medical Teal
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(
          0xFFF5F5F7,
        ), // Apple-like light gray
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
          iconTheme: IconThemeData(color: Colors.black),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late String _currentTip;
  String _versionString = '';
  bool _dragging = false;
  bool _isImportingImage = false;
  String _importStatusText = 'Preparing image...';

  // Tutorial Keys
  // Tutorial Keys
  final GlobalKey _startKey = GlobalKey();
  final GlobalKey _historyKey = GlobalKey();
  final GlobalKey _tipKey = GlobalKey();
  final GlobalKey _feedbackKey = GlobalKey();
  final GlobalKey _settingsKey = GlobalKey();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<List<SharedMediaFile>>?
  _intentDataStreamSubscription; // For shared files

  static const _fileChannel = MethodChannel('com.orthoquant.md/file_open');

  late TutorialCoachMark tutorialCoachMark;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentTip = orthopedicTips[Random().nextInt(orthopedicTips.length)];

    // Check and show tutorial
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkAndShowTutorial(),
    );
    _loadVersion();
    _initAppLinks();
    _initNativeFileChannel();
    _initShareIntent(); // Initialize share intent listener

    if (!kIsWeb && Platform.isIOS) {
      _fileChannel.invokeMethod('requestNotificationPermission').catchError((
        e,
      ) {
        debugPrint("Error requesting notification permission: $e");
      });
    }
  }

  Future<void> _initShareIntent() async {
    // receive_sharing_intent may not support macOS or requires specific implementation
    if (kIsWeb) return;
    if (Platform.isMacOS) return;

    try {
      // For sharing images coming from outside the app while the app is in the memory
      _intentDataStreamSubscription = ReceiveSharingIntent.instance
          .getMediaStream()
          .listen(
            (List<SharedMediaFile> value) {
              if (value.isNotEmpty) {
                debugPrint("Shared stream: ${value.first.path}");
                _handleIncomingFilePath(value.first.path);
              }
            },
            onError: (err) {
              debugPrint("getIntentDataStream error: $err");
            },
          );

      // For sharing images coming from outside the app while the app is closed
      ReceiveSharingIntent.instance
          .getInitialMedia()
          .then((List<SharedMediaFile> value) {
            if (value.isNotEmpty) {
              debugPrint("Shared Initial: ${value.first.path}");
              _handleIncomingFilePath(value.first.path);
            }
          })
          .catchError((err) {
            debugPrint("getInitialMedia error: $err");
          });
    } catch (e) {
      debugPrint("Error initializing share intent: $e");
    }
  }

  void _initNativeFileChannel() async {
    // Platform check: now supporting iOS too for the native "Open In" bypass
    if (kIsWeb) return;
    if (Platform.isMacOS || Platform.isIOS) {
      _fileChannel.setMethodCallHandler((call) async {
        if (call.method == "onFileOpened") {
          final String? path = call.arguments as String?;
          if (path != null) {
            _handleIncomingFilePath(path);
          }
        } else if (call.method == "onShareIntent") {
          debugPrint(
            "Switched to foreground via Share Intent, checking for saved file...",
          );
          try {
            final String? initialPath = await _fileChannel.invokeMethod(
              'getInitialFile',
            );
            if (initialPath != null) {
              _handleIncomingFilePath(initialPath);
            }
          } catch (e) {
            debugPrint('Error pulling share file: $e');
          }
        }
      });

      // Check for an initial file if the app was launched by dropping a file onto the icon
      try {
        final String? initialPath = await _fileChannel.invokeMethod(
          'getInitialFile',
        );
        if (initialPath != null) {
          _handleIncomingFilePath(initialPath);
        }
      } catch (e) {
        debugPrint('Error pulling initial file: $e');
      }
    }
  }

  Future<void> _initAppLinks() async {
    // Keep app_links for mobile deep links if needed, but skip for macOS files
    if (kIsWeb) return;
    if (Platform.isMacOS) return;

    // Handle incoming links while the app is running
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      debugPrint('Incoming link: $uri');
      _handleIncomingFile(uri);
    });

    // Handle the link that opened the app
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      debugPrint('Initial link: $initialUri');
      _handleIncomingFile(initialUri);
    }
  }

  Future<void> _handleIncomingFilePath(String path) async {
    // Determine extension
    final ext = path.toLowerCase().split('.').last;

    if (['png', 'jpg', 'jpeg', 'heic'].contains(ext)) {
      // Copy to temp file to ensure access rights (iOS Sandbox issue fix)
      try {
        final file = File(path);
        if (await file.exists()) {
          final tempDir = await getTemporaryDirectory();
          final newPath =
              '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.$ext';
          await file.copy(newPath);
          debugPrint("File copied to: $newPath");
          _handleImageSelected(newPath);
        } else {
          debugPrint("Incoming file does not exist at: $path");
        }
      } catch (e) {
        debugPrint("Error copying incoming file: $e");
        // Fallback to original path
        _handleImageSelected(path);
      }
    }
  }

  void _handleIncomingFile(Uri uri) {
    debugPrint("Incoming URI: $uri");

    // Handle standard file scheme
    String path = uri.path;
    if (uri.scheme == 'file') {
      if (!kIsWeb && Platform.isIOS) {
        // Trust the native channel 'onFileOpened' to come through with the COPIED safe path.
        // Ignoring this raw locked path.
        debugPrint(
          "Ignoring raw iOS file URI in favor of native channel: $uri",
        );
        return;
      }

      try {
        path = uri.toFilePath();
      } catch (e) {
        debugPrint("Error converting URI to file path: $e");
        // Fallback to decoding manually if toFilePath fails for some reason
        path = Uri.decodeFull(uri.path);
      }
    }

    _handleIncomingFilePath(path);
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _versionString = 'v${info.version}';
    });
  }

  Future<void> _checkAndShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('home_tutorial_shown_v1') ?? false;
    if (!shown) {
      _createTutorial();
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) tutorialCoachMark.show(context: context);
      });
      prefs.setBool('home_tutorial_shown_v1', true);
    }
    await _checkAndShowWhatsNew(prefs, isFirstLaunch: !shown);
  }

  static const _whatsNewSeenVersionKey = 'whats_new_seen_version';

  // Opens the What's New sheet once after the user updates to a new version.
  // Fresh installs only record the version so they see the tutorial instead.
  Future<void> _checkAndShowWhatsNew(
    SharedPreferences prefs, {
    required bool isFirstLaunch,
  }) async {
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;
    final seenVersion = prefs.getString(_whatsNewSeenVersionKey);
    await prefs.setString(_whatsNewSeenVersionKey, currentVersion);
    if (isFirstLaunch || seenVersion == currentVersion) return;

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        _showWhatsNewSheet();
      }
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _intentDataStreamSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("App resumed - Checking for pending shared files...");
      _fileChannel
          .invokeMethod('getInitialFile')
          .then((path) {
            if (path != null && path is String) {
              debugPrint("Found pending file on resume: $path");
              _handleIncomingFilePath(path);
            }
          })
          .catchError((e) {
            debugPrint("Error checking pending file on resume: $e");
          });
    }
  }

  void _createTutorial() {
    tutorialCoachMark = TutorialCoachMark(
      targets: _createTargets(),
      colorShadow: Colors.black,
      textSkip: "SKIP",
      paddingFocus: 5, // Tighter spotlight
      opacityShadow: 0.85,
      onFinish: () {
        debugPrint("Tutorial finished");
      },
      onClickTarget: (target) {
        debugPrint("onClickTarget: $target");
      },
      onSkip: () {
        debugPrint("onSkip");
        return true;
      },
      onClickOverlay: (target) {
        debugPrint("onClickOverlay: $target");
      },
    );
  }

  List<TargetFocus> _createTargets() {
    List<TargetFocus> targets = [];

    // 1. Start Button (Bottom) -> Text Top
    targets.add(
      TargetFocus(
        identify: "StartButton",
        keyTarget: _startKey,
        alignSkip: Alignment.topRight,
        shape: ShapeLightFocus.RRect,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    "Start Here",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 20,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Tap to take a new X-ray photo or select one from your gallery.",
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    // 2. History Button (Bottom) -> Text Top
    targets.add(
      TargetFocus(
        identify: "HistoryButton",
        keyTarget: _historyKey,
        alignSkip: Alignment.topRight,
        shape: ShapeLightFocus.RRect,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    "Your Records",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 20,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Access your past measurements here.",
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    // 3. Tip (Top/Middle) -> Text Bottom
    targets.add(
      TargetFocus(
        identify: "TipSection",
        keyTarget: _tipKey,
        alignSkip: Alignment.bottomRight,
        shape: ShapeLightFocus.RRect,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 20.0),
                    child: Text(
                      "Daily Tips",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Tap here to discover useful tips on the app. Click for another tip!",
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    // 4. Feedback (Top Right) -> Text Bottom Left
    targets.add(
      TargetFocus(
        identify: "FeedbackButton",
        keyTarget: _feedbackKey,
        alignSkip: Alignment.bottomLeft,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 20.0),
                    child: Text(
                      "Feedback",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Send us your suggestions or report issues directly.",
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.right,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    // 5. Settings (Top Right) -> Text Bottom Left
    targets.add(
      TargetFocus(
        identify: "SettingsButton",
        keyTarget: _settingsKey,
        alignSkip: Alignment.bottomLeft,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 20.0),
                    child: Text(
                      "Settings",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Configure preferences, units, and app behaviors.",
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.right,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    return targets;
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      _showImageImportProgress('Loading selected image...');
      final bytes = kIsWeb ? await image.readAsBytes() : null;
      await _handleImageSelected(image.path, imageBytes: bytes);
    }
  }

  Future<void> _pickFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'heic'],
      withData: kIsWeb,
    );

    final file = result?.files.single;
    if (file == null) return;

    _showImageImportProgress('Loading selected image...');
    final path = file.path;
    if (path == null) {
      if (file.bytes != null) {
        await _handleImageSelected(file.name, imageBytes: file.bytes);
      }
      return;
    }

    await _handleImageSelected(path, imageBytes: file.bytes);
  }

  Future<void> _handleImageSelected(
    String path, {
    Uint8List? imageBytes,
  }) async {
    if (!mounted) return;
    _showImageImportProgress('Preparing image for measurement...');

    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          IOSUiSettings(title: 'Crop Image'),
        ],
      );

      if (croppedFile != null && mounted) {
        _showImageImportProgress('Opening measurement screen...');
        final croppedBytes = kIsWeb ? await croppedFile.readAsBytes() : null;
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MeasurementScreen(
              imagePath: croppedFile.path,
              imageBytes: croppedBytes ?? imageBytes,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Crop error: $e');
      // Fallback to original image if crop fails (e.g. MissingPlugin on macOS)
      if (mounted) {
        _showImageImportProgress('Opening measurement screen...');
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                MeasurementScreen(imagePath: path, imageBytes: imageBytes),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImportingImage = false);
      }
    }
  }

  void _showImageImportProgress(String message) {
    if (!mounted) return;
    setState(() {
      _isImportingImage = true;
      _importStatusText = message;
    });
  }

  Future<void> _openCamera({CameraDescription? camera}) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => CameraScreen(camera: camera)),
    );

    if (result != null && result is String) {
      if (!mounted) return;

      // Check preferences and save to gallery if enabled
      final prefs = await SharedPreferences.getInstance();
      final shouldSave = prefs.getBool('save_to_camera_roll') ?? false;
      if (shouldSave) {
        try {
          // Request access explicitly first if needed (Gal handles it but good practice)
          // Gal.putImage saves the image to the gallery
          await Gal.putImage(result);
          // Show small feedback? Maybe too intrusive.
          // Let's just do it silently or with a quiet snackbar if needed.
        } catch (e) {
          debugPrint('Error saving to gallery: $e');
        }
      }

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => MeasurementScreen(imagePath: result),
        ),
      );
    }
  }

  Future<void> _launchFeedbackEmail() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'ilker.eren@gmail.com',
      query: 'subject=Feedback on OrthoQuant MD',
    );

    try {
      if (!await launchUrl(emailLaunchUri)) {
        debugPrint('Could not launch email client');
      }
    } catch (e) {
      debugPrint('Error launching email: $e');
    }
  }

  Future<void> _openSurvey() async {
    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const SurveyScreen()),
    );
    if (sent == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? 'Thank you! Your feedback was sent.'
              : 'Your mail app is open — tap Send to share your answers.',
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // title: const Text('OrthoQuant MD', style: TextStyle(color: Colors.white)), // REMOVED
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 92,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16, top: 2),
          child: _WhatsNewBadge(onTap: _showWhatsNewSheet),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.rate_review_outlined, color: Colors.amber),
            onPressed: _openSurvey,
            tooltip: 'Quick Survey',
          ),
          IconButton(
            key: _feedbackKey,
            icon: const Icon(Icons.mail_outline, color: Colors.white),
            onPressed: _launchFeedbackEmail,
          ),
          IconButton(
            key: _settingsKey,
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      // ...
      body: DropTarget(
        onDragDone: (detail) async {
          if (detail.files.isNotEmpty) {
            final file = detail.files.first;
            final path = file.path;
            final ext = path.toLowerCase().split('.').last;
            if (['png', 'jpg', 'jpeg'].contains(ext)) {
              _handleImageSelected(path);
            }
          }
        },
        onDragEntered: (detail) {
          setState(() {
            _dragging = true;
          });
        },
        onDragExited: (detail) {
          setState(() {
            _dragging = false;
          });
        },
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/home_bg.png'),
                  fit: BoxFit.cover,
                ),
              ),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: IntrinsicHeight(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // const Spacer(), // Reduced top space to move up
                                const SizedBox(height: 60), // Top Padding
                                // TIP OF THE DAY (Moved to Top)
                                // TIP OF THE DAY (Moved to Top)
                                GestureDetector(
                                  key: _tipKey,
                                  onTap: () {
                                    setState(() {
                                      _currentTip =
                                          orthopedicTips[Random().nextInt(
                                            orthopedicTips.length,
                                          )];
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: Column(
                                      children: [
                                        // Add an icon to indicate interactivity? Maybe subtle.
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Tip of the Day',
                                              style: TextStyle(
                                                color: Color(0xFF00BFA5),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                            SizedBox(width: 6),
                                            Icon(
                                              Icons.refresh,
                                              size: 12,
                                              color: Color(
                                                0xFF00BFA5,
                                              ).withValues(alpha: 0.7),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          _currentTip,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontStyle: FontStyle.italic,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    '*click for more tips',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontStyle: FontStyle.italic,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),

                                const Spacer(), // Push Logo down slightly or center it in remaining space
                                // Tagline and Version (Above Logo)
                                const SizedBox(height: 20),
                                const Spacer(),
                                // Logo or Hero Section
                                Container(
                                  height: 120,
                                  width: 120,
                                  decoration: BoxDecoration(
                                    image: const DecorationImage(
                                      image: AssetImage(
                                        'assets/images/app_logo.png',
                                      ),
                                      fit: BoxFit.contain,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Digital Orthopedic\nMeasurement',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Capture or select an X-ray to start measuring angles.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(color: Colors.white70),
                                ),

                                const Spacer(),

                                const Spacer(), // Spacer before buttons
                                // Action Buttons

                                // TAGLINE AND VERSION (Moved above buttons)

                                // ACTION BUTTONS
                                Container(
                                  key: _startKey,
                                  child: _buildActionButton(
                                    context,
                                    icon: Icons.add_a_photo_outlined,
                                    label: 'Start New Measurement',
                                    onPressed: () {
                                      _showSelectionSheet(context);
                                    },
                                    isPrimary: true,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  key: _historyKey,
                                  child: _buildActionButton(
                                    context,
                                    icon: Icons.history_rounded,
                                    label: 'Measurement History',
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const HistoryScreen(),
                                        ),
                                      );
                                    },
                                    isPrimary: false,
                                  ),
                                ),
                                const SizedBox(height: 32),

                                // Tagline, Version & Legal Notice (Bottom Group)
                                Center(
                                  child: Column(
                                    children: [
                                      const Text(
                                        'made by doctors for doctors',
                                        style: TextStyle(
                                          fontStyle: FontStyle.italic,
                                          color: Colors.white70,
                                          fontFamily: 'serif',
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const SizedBox(height: 4),
                                      Text(
                                        _versionString,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextButton(
                                        onPressed: () =>
                                            _showLegalDialog(context),
                                        style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          foregroundColor: Colors.white54,
                                        ),
                                        child: const Text(
                                          'Disclaimer & Privacy Policy',
                                          style: TextStyle(
                                            fontSize: 12,
                                            decoration:
                                                TextDecoration.underline,
                                            decorationColor: Colors.white54,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (_dragging)
              Container(
                color: const Color(0xFF00BFA5).withValues(alpha: 0.15),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF00BFA5),
                        width: 2,
                      ),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.file_download_rounded,
                          color: Color(0xFF00BFA5),
                          size: 48,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Drop image to import',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_isImportingImage)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.58),
                  child: Center(
                    child: Container(
                      width: 260,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111820),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF00BFA5)),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: Color(0xFF00BFA5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _importStatusText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Large images can take a moment.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showWhatsNewSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF17191D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.86,
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
                  const Row(
                    children: [
                      _SketchBulb(size: 34),
                      SizedBox(width: 12),
                      Text(
                        "What's new",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const _WhatsNewItem(
                    title: 'Multi-Image measurements',
                    detail:
                        'Measure across two CT or MRI slices with '
                        'step-by-step guidance. Available with PRO.',
                  ),
                  const _WhatsNewItem(
                    title: 'TT-TG distance',
                    detail:
                        'The first Multi-Image template: mark the trochlea '
                        'and tibial tuberosity slices and see both in one '
                        'overlay view.',
                  ),
                  const _WhatsNewItem(
                    title: 'Quick Survey',
                    detail:
                        'Tap the new survey button on the home screen to '
                        'share your feedback in under a minute.',
                  ),
                  const _WhatsNewItem(
                    title: 'AI interpretation on Mac',
                    detail:
                        'AI interpretation now works out of the box in the '
                        'Mac App Store version.',
                  ),
                  const _WhatsNewItem(
                    title: "What's new on update",
                    detail:
                        'This summary now opens automatically after each '
                        'app update.',
                  ),
                  const _WhatsNewItem(
                    title: 'Bug fix',
                    detail:
                        'Fixed a crash on launch on iOS 27 devices.',
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsScreen(
                              showVersionHistoryOnOpen: true,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: const Text('View full version history'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00BFA5),
                        side: const BorderSide(color: Color(0xFF00BFA5)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
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
        );
      },
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary
              ? Theme.of(context).colorScheme.primary
              : Colors.white,
          foregroundColor: isPrimary ? Colors.white : Colors.black87,
          elevation: isPrimary ? 4 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: isPrimary
                ? BorderSide.none
                : const BorderSide(color: Colors.grey, width: 0.5),
          ),
        ),
        icon: Icon(icon),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  void _showSelectionSheet(BuildContext context) {
    final isMacOS = !kIsWeb && Platform.isMacOS;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                isMacOS
                    ? Icons.insert_drive_file_rounded
                    : Icons.camera_alt_rounded,
                color: const Color(0xFF00BFA5),
              ),
              title: Text(isMacOS ? 'Import from File' : 'Take Photo'),
              onTap: () {
                Navigator.pop(context);
                if (isMacOS) {
                  _pickFromFile();
                } else {
                  _openCamera();
                }
              },
            ),
            ListTile(
              leading: Icon(
                isMacOS ? Icons.open_with_rounded : Icons.photo_library_rounded,
                color: const Color(0xFF2979FF),
              ),
              title: Text(isMacOS ? 'Drag and Drop' : 'Select from Gallery'),
              onTap: () {
                Navigator.pop(context);
                if (isMacOS) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Drag an X-ray image into the app window.'),
                    ),
                  );
                } else {
                  _pickFromGallery();
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showLegalDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            maxWidth: 600,
          ),
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
                    const Icon(
                      Icons.privacy_tip_rounded,
                      color: Color(0xFF00BFA5),
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Disclaimer & Privacy Policy',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Content
              Flexible(
                child: FutureBuilder<String>(
                  future: rootBundle.loadString('PRIVACY_POLICY.md'),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF00BFA5),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text(
                          'Error loading policy',
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: MarkdownBody(
                        data: snapshot.data ?? '',
                        styleSheet: MarkdownStyleSheet(
                          p: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.5,
                          ),
                          h1: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          h2: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            height: 2,
                          ),
                          h3: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            height: 1.8,
                          ),
                          strong: const TextStyle(
                            color: Color(0xFF00BFA5),
                            fontWeight: FontWeight.bold,
                          ),
                          listBullet: const TextStyle(color: Color(0xFF00BFA5)),
                          horizontalRuleDecoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Colors.white10),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Footer
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BFA5),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'I UNDERSTAND & AGREE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
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
}

class _WhatsNewBadge extends StatelessWidget {
  const _WhatsNewBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: "What's new",
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 68,
            height: 58,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Transform.rotate(
                  angle: -pi / 6,
                  child: const _SketchBulb(size: 31.2),
                ),
                Transform.rotate(
                  angle: -0.055,
                  child: const Text(
                    "What's new",
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      fontStyle: FontStyle.italic,
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
}

class _WhatsNewItem extends StatelessWidget {
  const _WhatsNewItem({required this.title, required this.detail});

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
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 8, right: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFFFD766),
              shape: BoxShape.circle,
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
                    fontSize: 13,
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

class _SketchBulb extends StatelessWidget {
  const _SketchBulb({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 1.12),
      painter: _SketchBulbPainter(),
    );
  }
}

class _SketchBulbPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final glowPaint = Paint()
      ..color = const Color(0xFFFFD766).withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    final bulbPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFD766).withValues(alpha: 0.9);
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.92);
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFD766);

    final center = Offset(size.width * 0.5, size.height * 0.39);
    final bulbRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.54,
      height: size.height * 0.48,
    );

    canvas.drawCircle(center, size.width * 0.37, glowPaint);
    canvas.drawOval(bulbRect, bulbPaint);
    canvas.drawOval(bulbRect.shift(const Offset(-0.8, -0.4)), strokePaint);

    final baseTop = Offset(size.width * 0.36, size.height * 0.64);
    final basePath = Path()
      ..moveTo(baseTop.dx, baseTop.dy)
      ..lineTo(size.width * 0.64, size.height * 0.64)
      ..lineTo(size.width * 0.59, size.height * 0.82)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.88,
        size.width * 0.41,
        size.height * 0.82,
      )
      ..close();
    canvas.drawPath(
      basePath,
      Paint()..color = const Color(0xFF2D3238).withValues(alpha: 0.95),
    );
    canvas.drawPath(basePath, strokePaint);

    for (final y in [0.69, 0.76]) {
      canvas.drawLine(
        Offset(size.width * 0.39, size.height * y),
        Offset(size.width * 0.61, size.height * (y - 0.01)),
        strokePaint,
      );
    }

    final rays = [
      (
        Offset(size.width * 0.5, size.height * 0.02),
        Offset(size.width * 0.5, size.height * 0.14),
      ),
      (
        Offset(size.width * 0.18, size.height * 0.17),
        Offset(size.width * 0.27, size.height * 0.25),
      ),
      (
        Offset(size.width * 0.82, size.height * 0.17),
        Offset(size.width * 0.73, size.height * 0.25),
      ),
      (
        Offset(size.width * 0.07, size.height * 0.43),
        Offset(size.width * 0.2, size.height * 0.43),
      ),
      (
        Offset(size.width * 0.93, size.height * 0.43),
        Offset(size.width * 0.8, size.height * 0.43),
      ),
    ];

    for (final ray in rays) {
      canvas.drawLine(ray.$1, ray.$2, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
