import 'package:flutter/material.dart';
import 'package:ortho_quant_md/models/measurement_record.dart';
import 'package:ortho_quant_md/services/history_service.dart';
import 'package:ortho_quant_md/models/history_group.dart';
import 'package:ortho_quant_md/services/subscription_service.dart';
import 'package:ortho_quant_md/screens/paywall_screen.dart';

class SaveRecordScreen extends StatefulWidget {
  final MeasurementRecord record;

  const SaveRecordScreen({super.key, required this.record});

  @override
  State<SaveRecordScreen> createState() => _SaveRecordScreenState();
}

class _SaveRecordScreenState extends State<SaveRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _idController;
  late TextEditingController _notesController;
  final HistoryService _historyService = HistoryService();
  bool _isSaving = false;
  String? _selectedGroupId;
  List<HistoryGroup> _groups = [];
  bool _loadingGroups = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.record.patientName);
    _idController = TextEditingController(text: widget.record.patientId);
    _notesController = TextEditingController(text: widget.record.notes);
    _selectedGroupId = widget.record.groupId;
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final groups = await _historyService.getGroups();
    setState(() {
      _groups = groups;
      _loadingGroups = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);

    // Update Record
    widget.record.patientName = _nameController.text;
    widget.record.patientId = _idController.text;
    widget.record.notes = _notesController.text;
    widget.record.groupId = _selectedGroupId;
    widget.record.isAutoSaved = false; // Marked as manual

    await _historyService.saveRecord(widget.record);

    if (mounted) {
       Navigator.pop(context, true); // Return true to indicate saved
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Save Record', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: _buildInputDecoration('Patient Name'),
                style: const TextStyle(color: Colors.white),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _idController,
                decoration: _buildInputDecoration('Patient ID / MRN'),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
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
                        decoration: _buildInputDecoration('Save to Group ${SubscriptionService().isPro ? '' : '(PRO)'}').copyWith(
                          prefixIcon: Icon(Icons.folder_outlined, color: SubscriptionService().isPro ? Colors.white70 : Colors.amber),
                          labelStyle: TextStyle(color: SubscriptionService().isPro ? Colors.white70 : Colors.amber),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Uncategorized')),
                          ..._groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))),
                        ],
                        onChanged: (val) => setState(() => _selectedGroupId = val),
                      ),
                    ),
                  ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: _buildInputDecoration('Clinical Notes'),
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00BFA5),
                    foregroundColor: Colors.white,
                  ),
                  child: _isSaving 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text('SAVE RECORD', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
      focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF00BFA5)), borderRadius: BorderRadius.circular(8)),
      errorBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.redAccent), borderRadius: BorderRadius.circular(8)),
      focusedErrorBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.redAccent), borderRadius: BorderRadius.circular(8)),
      filled: true,
      fillColor: Colors.grey[900],
    );
  }
}
