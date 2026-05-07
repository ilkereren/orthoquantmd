import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:ortho_quant_md/utils/geometry.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ortho_quant_md/services/subscription_service.dart';
import 'package:ortho_quant_md/screens/paywall_screen.dart';
import 'package:ortho_quant_md/services/history_service.dart';
import 'package:ortho_quant_md/models/history_group.dart';
import 'package:file_picker/file_picker.dart';

class ExportScreen extends StatefulWidget {
  final String imagePath;
  final List<MeasurementModel> measurements;
  final double? pixelsPerMm;
  final Uint8List? capturedImageBytes;
  final Size? displaySize;
  final String? initialPatientName;
  final String? initialPatientId;
  final String? initialClinicalNotes;
  final String? initialGroupId;

  const ExportScreen({
    super.key,
    required this.imagePath,
    required this.measurements,
    this.pixelsPerMm,
    this.capturedImageBytes,
    this.displaySize,
    this.initialPatientName,
    this.initialPatientId,
    this.initialClinicalNotes,
    this.initialGroupId,
    this.customTableData,
  });

  final List<List<String>>? customTableData;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late TextEditingController _patientNameController;
  late TextEditingController _patientIdController;
  late TextEditingController _clinicalNotesController;
  String? _selectedGroupId;
  List<HistoryGroup> _groups = [];
  bool _loadingGroups = true;

  @override
  void initState() {
    super.initState();
    _patientNameController = TextEditingController(text: widget.initialPatientName);
    _patientIdController = TextEditingController(text: widget.initialPatientId);
    _clinicalNotesController = TextEditingController(text: widget.initialClinicalNotes);
    _selectedGroupId = widget.initialGroupId;
    _loadGroups();
  }
  
  Future<void> _loadGroups() async {
    final groups = await HistoryService().getGroups();
    setState(() {
      _groups = groups;
      _loadingGroups = false;
    });
  }

  @override
  void dispose() {
    _patientNameController.dispose();
    _patientIdController.dispose();
    _clinicalNotesController.dispose();
    super.dispose();
  }

  // Denormalize Point to Image Coordinates
  Offset _denormalize(Offset p, double w, double h) {
    return Offset(p.dx * w, p.dy * h);
  }

  // Generate the PDF document
  Future<void> _generatePdf(BuildContext context) async {
    final pdf = pw.Document();

    // Load Image
    final imageFile = File(widget.imagePath);
    final imageBytes = await imageFile.readAsBytes();
    final pdfImage = pw.MemoryImage(imageBytes);

    // Get Image Dimensions for scaling
    final decodedImage = await decodeImageFromList(imageBytes);
    final imageWidth = decodedImage.width.toDouble();
    final imageHeight = decodedImage.height.toDouble();

    // Calculate Real pxPerMm based on Image Resolution if Calibration exists
    double? pdfPxPerMm;
    try {
      final calib = widget.measurements.firstWhere((m) => m.type == MeasurementType.calibration);
      if (calib.points.length >= 2 && calib.calibrationValue != null) {
          final p1 = _denormalize(calib.points[0].position, imageWidth, imageHeight);
          final p2 = _denormalize(calib.points[1].position, imageWidth, imageHeight);
          final distPx = (p1 - p2).distance;
          pdfPxPerMm = distPx / calib.calibrationValue!;
      }
    } catch (_) {}

    // Load Fonts once
    final font = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();
    final themeData = pw.ThemeData.withFont(base: font, bold: fontBold);

    // PAGE 1: Header, Metadata, Table
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Theme(
            data: themeData,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // 1. HEADER
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                     pw.Text('OrthoQuant MD Report', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
                     pw.Text(DateTime.now().toString().substring(0, 16), style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  ]
                ),
                pw.Divider(color: PdfColors.grey300),
                pw.SizedBox(height: 10),

                // 2. METADATA
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildInfoRow('Patient Name', _patientNameController.text.isNotEmpty ? _patientNameController.text : 'N/A'),
                        _buildInfoRow('Patient ID', _patientIdController.text.isNotEmpty ? _patientIdController.text : 'N/A'),
                      ]
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                         _buildInfoRow('Calibration', pdfPxPerMm != null ? '${pdfPxPerMm!.toStringAsFixed(2)} px/mm' : 'None'),
                      ]
                    )
                  ]
                ),

                if (_clinicalNotesController.text.isNotEmpty) ...[
                   pw.SizedBox(height: 10),
                   pw.Text('Clinical Notes:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                   pw.Text(_clinicalNotesController.text, style: const pw.TextStyle(fontSize: 10)),
                ],

                pw.SizedBox(height: 20),

                // 3. MEASUREMENT TABLE
                pw.Text('Measurement Results', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
                 pw.SizedBox(height: 10),
                 pw.TableHelper.fromTextArray(
                  headers: ['#', 'Type', 'Value', 'Unit'],
                  data: widget.customTableData ?? widget.measurements.where((m) => m.type != MeasurementType.calibration && !m.isAuxiliary).toList().asMap().entries.map((entry) {
                     final i = entry.key + 1;
                     final m = entry.value;
                     String val = '';
                     String unit = '';
                     
                     // Denormalize points for Calculation
                     final pImgs = m.points.map((p) => _denormalize(p.position, imageWidth, imageHeight)).toList();

                     if (m.type == MeasurementType.angle3Point && m.points.length >= 3) {
                        val = GeometryUtils.calculateAngle(pImgs[0], pImgs[1], pImgs[2]).toStringAsFixed(1);
                        unit = '°';
                     } else if (m.type == MeasurementType.cobbAngle && m.points.length >= 4) {
                        final labelPos = m.labelPosition;
                        if (labelPos == null) {
                          val = GeometryUtils.calculateCobbAngle(pImgs[0], pImgs[1], pImgs[2], pImgs[3]).toStringAsFixed(1);
                        } else {
                           // Fix: Denormalize labelPos to match pImgs space
                           final labelPosImg = _denormalize(labelPos, imageWidth, imageHeight);
                           val = GeometryUtils.calculateDynamicCobbAngle(pImgs[0], pImgs[1], pImgs[2], pImgs[3], labelPosImg).toStringAsFixed(1);
                        }
                        unit = '°';
                     } else if (m.type == MeasurementType.distance && m.points.length >= 2) {
                        final dist = (pImgs[0] - pImgs[1]).distance;
                        if (pdfPxPerMm != null) {
                           val = (dist / pdfPxPerMm!).toStringAsFixed(1);
                           unit = 'mm';
                        } else {
                           val = dist.toStringAsFixed(0);
                           unit = 'px';
                        }
                     } else if (m.type == MeasurementType.glenoidDefect && m.points.length >= 4) {
                         final res = GeometryUtils.calculateGlenoidDefect(pImgs);
                         if (res != null) {
                             final percent = res['lossPercent'] as double;
                             val = percent.toStringAsFixed(1);
                             unit = '%';
                         }
                     }
                     
                     String typeStr = 'Angle';
                     if (m.type == MeasurementType.cobbAngle) typeStr = 'Cobb Angle';
                     if (m.type == MeasurementType.distance) typeStr = 'Distance';
                     if (m.type == MeasurementType.glenoidDefect) typeStr = 'Glenoid Bone Loss';
                     
                     return [i.toString(), typeStr, val, unit];
                  }).toList(),
                  border: pw.TableBorder.all(color: PdfColors.grey),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  cellAlignment: pw.Alignment.centerRight,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerLeft,
                    2: pw.Alignment.centerRight,
                    3: pw.Alignment.centerRight,
                  }
                ),

                pw.Spacer(), 
                // Footer Page 1
                 pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                     pw.Text('Page 1/2', style: const pw.TextStyle(color: PdfColors.grey500, fontSize: 10)),
                  ]
                )
              ]
            )
          );
        }
      )
    );

    // PAGE 2: Large Image
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20), // Smaller margin for image
        build: (pw.Context context) {
           return pw.Expanded(
             child: pw.LayoutBuilder(
               builder: (context, constraints) {
                  // Uses captured image (screenshot) if available for maximum fidelity
                  if (widget.capturedImageBytes != null) {
                     final capturedImage = pw.MemoryImage(widget.capturedImageBytes!);
                     return pw.Center(child: pw.Image(capturedImage, fit: pw.BoxFit.contain));
                  }

                  // FALLBACK: Reconstruct using raw image + vector overlay
                  // Calculate Scale to fit 'contain'
                  final wRatio = constraints?.maxWidth != null ? constraints!.maxWidth / imageWidth : 1.0;
                  final hRatio = constraints?.maxHeight != null ? constraints!.maxHeight / imageHeight : 1.0;
                  final fitScale = wRatio < hRatio ? wRatio : hRatio;
                  
                  final activeW = imageWidth * fitScale;
                  final activeH = imageHeight * fitScale;
                  
                  final dx = (constraints!.maxWidth - activeW) / 2;
                  final dy = (constraints.maxHeight - activeH) / 2;
                  
                  double pointScaleX = activeW; 
                  double pointScaleY = activeH;

                  return pw.Stack(
                    children: [
                      pw.Center(child: pw.Image(pdfImage, fit: pw.BoxFit.contain)),
                      
                      // Vector Overlay
                      pw.Positioned(
                        left: dx,
                        top: dy,
                        child: pw.Container(
                          width: activeW,
                          height: activeH,
                          child: pw.CustomPaint(
                            painter: (canvas, size) {
                               for (final m in widget.measurements) {
                                  if (m.type == MeasurementType.calibration) continue; // Skip calibration for cleanup
                                  
                                  final c = PdfColor.fromInt(m.color.toARGB32());
                                  canvas.setColor(c);
                                  canvas.setStrokeColor(c);
                                  canvas.setLineWidth(2.0);

                                  if (m.type == MeasurementType.cobbAngle && m.points.length >= 4) {
                                     // Line 1: 0-1
                                     canvas.drawLine(
                                        m.points[0].position.dx * pointScaleX, 
                                        m.points[0].position.dy * pointScaleY, 
                                        m.points[1].position.dx * pointScaleX, 
                                        m.points[1].position.dy * pointScaleY
                                     );
                                     // Line 2: 2-3
                                     canvas.drawLine(
                                        m.points[2].position.dx * pointScaleX, 
                                        m.points[2].position.dy * pointScaleY, 
                                        m.points[3].position.dx * pointScaleX, 
                                        m.points[3].position.dy * pointScaleY
                                     );
                                     canvas.strokePath();
                                  }
                                  else if (m.points.length >= 2) {
                                     for (int i = 0; i < m.points.length - 1; i++) {
                                        final p1 = m.points[i].position;
                                        final p2 = m.points[i+1].position;
                                        
                                        canvas.drawLine(
                                          p1.dx * pointScaleX, 
                                          p1.dy * pointScaleY, 
                                          p2.dx * pointScaleX, 
                                          p2.dy * pointScaleY
                                        );
                                        canvas.strokePath();
                                     }
                                  }
                                  
                                  // Draw Points
                                  for (final p in m.points) {
                                     canvas.drawEllipse(p.position.dx * pointScaleX - 2, p.position.dy * pointScaleY - 2, 4, 4);
                                     canvas.fillPath();
                                  }
                               }
                            }
                          )
                        )
                      ),
                      
                      // LABELS OVERLAY (Using Scaled Points)
                      ...widget.measurements.where((m) => m.type != MeasurementType.calibration).map((m) {
                          String val = '';
                          String unit = '';
                          // Normalised P positions
                          final pNorms = m.points.map((p) => p.position).toList();
                          
                          // Denormalize for Calculation (using Image Size)
                          final pImgs = pNorms.map((p) => _denormalize(p, imageWidth, imageHeight)).toList();

                          // Default Position (normalized)
                          double lx = 0;
                          double ly = 0;
                          
                          if (m.type == MeasurementType.angle3Point && m.points.length >= 3) {
                             val = GeometryUtils.calculateAngle(pImgs[0], pImgs[1], pImgs[2]).toStringAsFixed(1);
                             unit = '°';
                             lx = m.points[1].position.dx;
                             ly = m.points[1].position.dy; 
                          } else if (m.type == MeasurementType.cobbAngle && m.points.length >= 4) {
                             final labelPos = m.labelPosition;
                             if (labelPos == null) {
                               val = GeometryUtils.calculateCobbAngle(pImgs[0], pImgs[1], pImgs[2], pImgs[3]).toStringAsFixed(1);
                               lx = m.points[3].position.dx;
                               ly = m.points[3].position.dy;
                             } else {
                                // Dynamic calc needs denormalized label pos too
                                final labelPosImg = _denormalize(labelPos, imageWidth, imageHeight);
                                val = GeometryUtils.calculateDynamicCobbAngle(pImgs[0], pImgs[1], pImgs[2], pImgs[3], labelPosImg).toStringAsFixed(1);
                                lx = labelPos.dx;
                                ly = labelPos.dy;
                             }
                             unit = '°';
                          } else if (m.type == MeasurementType.distance && m.points.length >= 2) {
                             final dist = (pImgs[0] - pImgs[1]).distance;
                             if (pdfPxPerMm != null) {
                                val = (dist / pdfPxPerMm!).toStringAsFixed(1);
                                unit = 'mm';
                             } else {
                                val = dist.toStringAsFixed(0);
                                unit = 'px';
                             }
                             // Midpoint
                             lx = (m.points[0].position.dx + m.points[1].position.dx) / 2;
                             ly = (m.points[0].position.dy + m.points[1].position.dy) / 2;
                          }
                          
                          if (val.isEmpty) return pw.SizedBox();

                          if (m.type != MeasurementType.cobbAngle && m.labelPosition != null) {
                              lx = m.labelPosition!.dx;
                              ly = m.labelPosition!.dy;
                          }

                          // Apply Scaling to PDF Coordinates
                          final pdfLeft = dx + (lx * pointScaleX);
                          final pdfTop = dy + (ly * pointScaleY);

                          return pw.Positioned(
                            left: pdfLeft,
                            top: pdfTop,
                            child: pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.black,
                                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))
                              ),
                              child: pw.Text('$val$unit', style: const pw.TextStyle(color: PdfColors.white, fontSize: 8))
                            )
                          );
                      })
                    ],
                  );
               }
             ),
           );
        }
      )
    );

    // Footer for Page 2
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Theme(
            data: themeData,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Spacer(),
                pw.Divider(color: PdfColors.grey300),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                     pw.Text('Page 2/2 - Generated by OrthoQuant MD', style: const pw.TextStyle(color: PdfColors.grey500, fontSize: 10)),
                  ]
                )
              ]
            )
          );
        }
      )
    );

    final bytes = await pdf.save();

    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save PDF Report',
        fileName: 'ortho_quant_report.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(bytes);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Report saved to: $outputFile')),
          );
        }
      }
    } else {
      await Printing.sharePdf(bytes: bytes, filename: 'ortho_quant_report.pdf');
    }
  }

  pw.Widget _buildInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(text: '$label: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 10)),
          ]
        )
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    // Custom PopScope to return data on back button (Android/AppBar back)
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
         if (didPop) return;
         Navigator.pop(context, {
           'patientName': _patientNameController.text,
           'patientId': _patientIdController.text,
           'notes': _clinicalNotesController.text,
           'groupId': _selectedGroupId,
         });
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Export Options', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                 const Text('Patient Information', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                 const SizedBox(height: 16),
                 
                 // Patient Name
                 TextField(
                   controller: _patientNameController,
                   style: const TextStyle(color: Colors.white),
                   decoration: InputDecoration(
                     labelText: 'Patient Name',
                     labelStyle: const TextStyle(color: Colors.white70),
                     filled: true,
                     fillColor: Colors.grey[900],
                     border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                   ),
                 ),
                 const SizedBox(height: 12),
                                  // Patient ID
                  TextField(
                    controller: _patientIdController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Patient ID',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.grey[900],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Group Selection
                  _loadingGroups 
                    ? const SizedBox(height: 56, child: Center(child: CircularProgressIndicator()))
                    : GestureDetector(
                        onTap: SubscriptionService().isPro ? null : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const PaywallScreen()),
                          ).then((_) => _loadGroups());
                        },
                        child: AbsorbPointer(
                          absorbing: !SubscriptionService().isPro,
                          child: DropdownButtonFormField<String?>(
                            value: _selectedGroupId,
                            dropdownColor: Colors.grey[900],
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Save to Group ${SubscriptionService().isPro ? '' : '(PRO)'}',
                              labelStyle: TextStyle(color: SubscriptionService().isPro ? Colors.white70 : Colors.amber),
                              filled: true,
                              fillColor: Colors.grey[900],
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              prefixIcon: Icon(Icons.folder_outlined, color: SubscriptionService().isPro ? Colors.white70 : Colors.amber),
                            ),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Uncategorized')),
                              ..._groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))),
                            ],
                            onChanged: (val) => setState(() => _selectedGroupId = val),
                          ),
                        ),
                      ),
                  const SizedBox(height: 12),

                  // Clinical Notes
                  TextField(
                    controller: _clinicalNotesController,
                   maxLines: 3,
                   style: const TextStyle(color: Colors.white),
                   decoration: InputDecoration(
                     labelText: 'Clinical Notes',
                     labelStyle: const TextStyle(color: Colors.white70),
                     filled: true,
                     fillColor: Colors.grey[900],
                     border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                   ),
                 ),
                 
                 const SizedBox(height: 32),
                 const Divider(color: Colors.white24),
                 const SizedBox(height: 24),

                 _buildExportOption(
                   context, 
                   icon: Icons.picture_as_pdf, 
                   title: 'Export PDF Report', 
                   subtitle: 'Detailed report with image and results', 
                   isPremium: true,
                   onTap: () {
                     if (!SubscriptionService().isPro) {
                       Navigator.push(
                         context,
                         MaterialPageRoute(builder: (context) => const PaywallScreen()),
                       );
                     } else {
                       _generatePdf(context);
                     }
                   }
                 ),
                 const SizedBox(height: 24),
                  _buildExportOption(
                   context, 
                   icon: Icons.image, 
                   title: 'Export Image', 
                   subtitle: 'Saves the image with measurement overlays', 
                   onTap: () => _generateImage(context)
                 ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExportOption(BuildContext context, {
    required IconData icon, 
    required String title, 
    required String subtitle, 
    required VoidCallback onTap,
    bool isPremium = false,
  }) {
     return InkWell(
       onTap: onTap,
       borderRadius: BorderRadius.circular(16),
       child: Container(
         padding: const EdgeInsets.all(20),
         decoration: BoxDecoration(
           color: Colors.grey[900],
           borderRadius: BorderRadius.circular(16),
           border: Border.all(color: Colors.white24)
         ),
         child: Row(
           children: [
             Container(
               padding: const EdgeInsets.all(12),
               decoration: BoxDecoration(
                 color: const Color(0xFF00BFA5).withValues(alpha: 0.2),
                 shape: BoxShape.circle
               ),
               child: Icon(icon, color: const Color(0xFF00BFA5), size: 32),
             ),
             const SizedBox(width: 16),
             Expanded(
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                    Row(
                      children: [
                        Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        if (isPremium && !SubscriptionService().isPro) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('PRO', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                 ],
               ),
             ),
             const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16)
           ],
         ),
       ),
     );
  }

  Future<void> _generateImage(BuildContext context) async {
    if (widget.capturedImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: No image captured.')));
      return;
    }

    try {
      // Get temporary directory
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/ortho_quant_image.png');
      
      // Write bytes
      await file.writeAsBytes(widget.capturedImageBytes!);
      
      if (!context.mounted) return;

      // Share file
      // Check if file exists
      if (await file.exists()) {
        final xFile = XFile(file.path);
        
        if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
          final String? outputFile = await FilePicker.platform.saveFile(
            dialogTitle: 'Save Measurement Image',
            fileName: 'ortho_quant_image.png',
            type: FileType.image,
          );

          if (outputFile != null) {
            final destinationFile = File(outputFile);
            await destinationFile.writeAsBytes(widget.capturedImageBytes!);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Image saved to: $outputFile')),
              );
            }
          }
        } else {
          // ignore: deprecated_member_use 
          final box = context.findRenderObject() as RenderBox?;
          await Share.shareXFiles(
            [xFile], 
            text: 'OrthoQuant MD Measurement Image',
            sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
          );
        }
      } else {
         if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error saving image file.')));
         }
      }
    } catch (e) {
       debugPrint('Image Export Error: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
        }
    }
  }
}
