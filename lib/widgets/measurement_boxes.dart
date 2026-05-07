import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

/// Standard Styles & Widgets for Measurement Boxes

/// 1. Simple Measurement Label (On-Image Box)
class MeasurementLabelBox extends StatelessWidget {
  final String text;
  final Color color;
  final double scale;
  final bool isBold;
  final double fontSize;

  const MeasurementLabelBox({
    super.key,
    required this.text,
    required this.color,
    this.scale = 1.0,
    this.isBold = false,
    this.fontSize = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 / scale, vertical: 4 / scale),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4 / scale),
        border: Border.all(color: color, width: 1.5 / scale),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontSize: fontSize / scale,
        ),
      ),
    );
  }
}

/// 2. Template Result Box (Draggable Overlay)
class TemplateResultBox extends StatelessWidget {
  final String title;
  final List<Map<String, String>> items; // [{'label': 'Label', 'value': 'Value'}]
  final VoidCallback? onDrag; // Handle drag (place holder if needed for UI hint)
  final VoidCallback? onClose; // NEW: Callback to close the box

  const TemplateResultBox({
    super.key,
    required this.title,
    required this.items,
    this.onDrag,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
       width: 220, // Constrain width
       padding: const EdgeInsets.all(12),
       decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0,2))]
       ),
       child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 Expanded(child: Text(
                    title, 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)
                 )),
                 if (onClose != null)
                   GestureDetector(
                     onTap: onClose,
                     child: const Icon(Icons.close, color: Colors.white70, size: 20),
                   )
                 else if (onDrag != null) // Visual hint only, drag handled by parent
                    const Icon(Icons.drag_indicator, color: Colors.white54, size: 16)
                 else 
                    const Icon(Icons.drag_indicator, color: Colors.white54, size: 16)
               ],
             ),
             const Divider(color: Colors.white24, height: 16),
             ...items.map((item) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                       children: [
                          Expanded(child: Text(item['label'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 13))),
                          Text(
                            item['value'] ?? '', 
                            style: const TextStyle(color: Colors.yellowAccent, fontSize: 13, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right,
                          ),
                       ],
                    ),
                  );
             }),
          ],
       ),
    );
  }
}

/// 3. Info Box Helper (Dialog)
class MeasurementInfoDialog {
  static void show(BuildContext context, String title, String description) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: RichText(
            text: _buildRichText(description),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Kapat', style: TextStyle(color: Colors.blueAccent)),
          )
        ],
      )
    );
  }

  static TextSpan _buildRichText(String text) {
      final List<TextSpan> spans = [];
      final RegExp exp = RegExp(r"(\*\*.*?\*\*|\[.*?\]\(.*?\))");
      
      text.splitMapJoin(exp,
        onMatch: (m) {
          final match = m.group(0)!;
          if (match.startsWith('**')) {
             // Bold
             final content = match.substring(2, match.length - 2);
             spans.add(TextSpan(text: content, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15)));
             return match;
          } else if (match.startsWith('[')) {
             // Link
             final linkExp = RegExp(r"\[(.*?)\]\((.*?)\)");
             final linkMatch = linkExp.firstMatch(match);
             if (linkMatch != null) {
                 final label = linkMatch.group(1);
                 final url = linkMatch.group(2);
                 spans.add(TextSpan(
                   text: label, 
                   style: const TextStyle(color: Colors.blueAccent, decoration: TextDecoration.underline),
                   recognizer: TapGestureRecognizer()..onTap = () async {
                      if (url != null) {
                         final uri = Uri.parse(url);
                         if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                         }
                      }
                   }
                 ));
             }
             return match;
          }
          return match;
        },
        onNonMatch: (n) {
          spans.add(TextSpan(text: n, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)));
          return n;
        }
      );
      
      return TextSpan(children: spans);
  }
}
