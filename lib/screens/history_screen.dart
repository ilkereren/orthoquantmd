import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ortho_quant_md/models/measurement_record.dart';
import 'package:ortho_quant_md/models/history_group.dart';
import 'package:ortho_quant_md/services/history_service.dart';
import 'package:ortho_quant_md/screens/measurement_screen.dart';
import 'package:ortho_quant_md/services/subscription_service.dart';
import 'package:ortho_quant_md/screens/paywall_screen.dart';
import 'package:uuid/uuid.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final HistoryService _historyService = HistoryService();
  List<MeasurementRecord> _records = [];
  List<HistoryGroup> _groups = [];
  bool _isLoading = true;
  bool _hasMoreHidden = false;
  String? _expandedGroupId; // Tracking which accordion is open

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final allRecords = await _historyService.getRecords();
    final allGroups = await _historyService.getGroups();
    
    if (mounted) {
      setState(() {
        _groups = allGroups;
        if (!SubscriptionService().isPro && allRecords.length > 10) {
           _records = allRecords.take(10).toList();
           _hasMoreHidden = true;
        } else {
           _records = allRecords;
           _hasMoreHidden = false;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteRecord(String id) async {
    await _historyService.deleteRecord(id);
    _loadData();
  }

  Future<void> _createNewGroup() async {
    if (!SubscriptionService().isPro) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const PaywallScreen()),
      ).then((_) => _loadData());
      return;
    }
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('New Group', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Group Name',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create', style: TextStyle(color: Color(0xFF00BFA5))),
          ),
        ],
      ),
    );

    if (name != null && name.trim().isNotEmpty) {
      final newGroup = HistoryGroup(
        id: const Uuid().v4(),
        name: name.trim(),
        createdAt: DateTime.now(),
      );
      await _historyService.saveGroup(newGroup);
      _loadData();
    }
  }

  Future<void> _deleteGroup(String id) async {
     final success = await _historyService.deleteGroup(id);
     if (!success) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cannot delete group. Empty it first.'))
           );
        }
     } else {
        _loadData();
     }
  }

  Future<void> _handleMoveToGroup(String recordId, String? targetGroupId) async {
     if (!SubscriptionService().isPro) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const PaywallScreen()),
        ).then((_) => _loadData());
        return;
     }
     await _historyService.updateRecordGroup(recordId, targetGroupId);
     _loadData();
  }

  @override
  Widget build(BuildContext context) {
    // Group records by groupId
    final Map<String?, List<MeasurementRecord>> groupedData = {};
    
    // Ensure all groups exist in map even if empty
    groupedData[null] = _records.where((r) => r.groupId == null).toList();
    for (var g in _groups) {
      groupedData[g.id] = _records.where((r) => r.groupId == g.id).toList();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Measurement History', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
           IconButton(
             icon: const Icon(Icons.create_new_folder_outlined, color: Color(0xFF00BFA5)),
             onPressed: _createNewGroup,
             tooltip: 'New Group',
           )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : _records.isEmpty && _groups.isEmpty
          ? const Center(child: Text("No history found.", style: TextStyle(color: Colors.white54)))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      // List groups first
                      ..._groups.map((g) => _buildGroupAccordion(g.id, g.name, groupedData[g.id] ?? [])),
                      // List Uncategorized at bottom
                      _buildGroupAccordion(null, 'Uncategorized', groupedData[null] ?? []),
                    ],
                  ),
                ),
                if (_hasMoreHidden) _buildUpsellBanner(),
              ],
            ),
    );
  }

  Widget _buildGroupAccordion(String? groupId, String title, List<MeasurementRecord> records) {
     final isExpanded = _expandedGroupId == groupId;
     
     return DragTarget<String>(
       onWillAcceptWithDetails: (details) => details.data != (records.any((r) => r.id == details.data) ? details.data : ''), // Don't drop icon on itself (oversimplified)
       onAcceptWithDetails: (details) => _handleMoveToGroup(details.data, groupId),
       builder: (context, candidateData, rejectedData) {
         return Container(
           margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
           decoration: BoxDecoration(
             color: candidateData.isNotEmpty ? Colors.white10 : Colors.transparent,
             borderRadius: BorderRadius.circular(12),
             border: Border.all(color: candidateData.isNotEmpty ? const Color(0xFF00BFA5) : Colors.transparent),
           ),
           child: Theme(
             data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
             child: ExpansionTile(
               key: PageStorageKey(groupId ?? 'uncategorized'),
               initiallyExpanded: isExpanded,
               onExpansionChanged: (expanded) {
                  setState(() {
                    _expandedGroupId = expanded ? groupId : null;
                  });
               },
               leading: Icon(
                 groupId == null ? Icons.folder_open : Icons.folder, 
                 color: candidateData.isNotEmpty ? const Color(0xFF00BFA5) : Colors.white38
               ),
               title: Text(
                 title, 
                 style: TextStyle(
                   color: candidateData.isNotEmpty ? const Color(0xFF00BFA5) : Colors.white, 
                   fontWeight: FontWeight.bold
                 )
               ),
               trailing: Row(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   Text('${records.length}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                   if (groupId != null && records.isEmpty) 
                     IconButton(
                       icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                       onPressed: () => _deleteGroup(groupId),
                     )
                   else
                     const Icon(Icons.expand_more, color: Colors.white38),
                 ],
               ),
               children: records.isEmpty 
                 ? [const Padding(padding: EdgeInsets.all(16), child: Text("No records in this group", style: TextStyle(color: Colors.white24, fontSize: 12)))]
                 : records.map((r) => _buildListItem(r)).toList(),
             ),
           ),
         );
       },
     );
  }

  Widget _buildListItem(MeasurementRecord record) {
     return LongPressDraggable<String>(
       data: record.id,
       feedback: Material(
         color: Colors.transparent,
         child: Container(
           width: 250,
           padding: const EdgeInsets.all(12),
           decoration: BoxDecoration(
             color: Colors.grey[900],
             borderRadius: BorderRadius.circular(12),
             boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 8)],
           ),
           child: Row(
             children: [
               Icon(Icons.insert_drive_file, color: const Color(0xFF00BFA5)),
               const SizedBox(width: 8),
               Expanded(child: Text(record.patientName ?? 'Record', style: const TextStyle(color: Colors.white))),
             ],
           ),
         ),
       ),
       childWhenDragging: Opacity(opacity: 0.3, child: _buildRawListItem(record)),
       child: _buildRawListItem(record),
     );
  }

  Widget _buildRawListItem(MeasurementRecord record) {
     return Dismissible(
       key: Key(record.id),
       background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
       direction: DismissDirection.endToStart,
       onDismissed: (direction) => _deleteRecord(record.id),
       child: ListTile(
         contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
         leading: Container(
           width: 50, height: 50,
           decoration: BoxDecoration(
             color: Colors.grey[900],
             borderRadius: BorderRadius.circular(8),
             image: DecorationImage(
               image: FileImage(File(record.imagePath)),
               fit: BoxFit.cover,
               opacity: 0.8
             )
           ),
         ),
         title: Text(
           record.patientName ?? 'Autosaved Session',
           style: const TextStyle(color: Colors.white, fontWeight: FontWeight.normal, fontSize: 14),
         ),
         subtitle: Row(
           children: [
              Text(DateFormat('MMM dd • HH:mm').format(record.timestamp), style: const TextStyle(color: Colors.white38, fontSize: 11)),
              const Spacer(),
              if (record.measurements.isNotEmpty)
                Text('${record.measurements.length} Measurements', style: const TextStyle(color: Color(0xFF00BFA5), fontSize: 11, fontWeight: FontWeight.bold)),
           ],
         ),
         onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => MeasurementScreen(
                imagePath: record.imagePath,
                initialRecord: record,
              ))
            ).then((_) => _loadData());
         },
       ),
     );
  }

  Widget _buildUpsellBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          const Text(
            'Limit Reach - Pro Required',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Free tier is limited to 10 records. Upgrade to PRO to see your full history.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PaywallScreen()),
              ).then((_) => _loadData());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
            ),
            child: const Text('UPGRADE TO PRO'),
          ),
        ],
      ),
    );
  }
}
