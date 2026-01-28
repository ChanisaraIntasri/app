import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'disease_questions_page.dart';

// โทนสีเดียวกับหน้า DiseaseQuestionsPage
const kPrimaryGreen = Color(0xFF005E33);
const kPageBg = Color.fromARGB(255, 255, 255, 255);

class _ChemicalOption {
  final String id;
  final String name;

  const _ChemicalOption({required this.id, required this.name});
}

class ChemicalQuestionsPage extends StatefulWidget {
  final String treeId;
  final String? treeName;
  final String diseaseId;
  final String diseaseName;

  const ChemicalQuestionsPage({
    super.key,
    required this.treeId,
    this.treeName,
    required this.diseaseId,
    required this.diseaseName,
  });

  @override
  State<ChemicalQuestionsPage> createState() => _ChemicalQuestionsPageState();
}

class _ChemicalQuestionsPageState extends State<ChemicalQuestionsPage> {
  final _scroll = ScrollController();

  bool _loadingChemicals = true;
  bool _submitting = false;

  int _currentIndex = 0; // 0 = sprayed?, 1 = chemical
  String? _sprayed; // 'yes' | 'no'
  String? _selectedChemicalId; // chemical_id | '__other__'
  final TextEditingController _customChemicalCtrl = TextEditingController();

  List<_ChemicalOption> _chemicals = const [];

  @override
  void initState() {
    super.initState();
    _loadChemicals();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _customChemicalCtrl.dispose();
    super.dispose();
  }

  String _bubbleText() {
    final t = (widget.treeName ?? '').trim();
    if (t.isNotEmpty) return '${widget.diseaseName} • $t';
    return widget.diseaseName;
  }

  String? _readUserIdFromPrefs(SharedPreferences prefs) {
    final dynamic v = prefs.get('user_id') ??
        prefs.get('userId') ??
        prefs.get('uid') ??
        prefs.get('id');
    final s = v?.toString().trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  String? _readApiBaseUrl(SharedPreferences prefs) {
    // รองรับ key หลายแบบ เผื่อโปรเจกต์คุณใช้ชื่อไม่เหมือนกัน
    final v = prefs.getString('api_base_url') ??
        prefs.getString('apiBaseUrl') ??
        prefs.getString('baseUrl') ??
        prefs.getString('backend_url') ??
        prefs.getString('server_url');
    final s = v?.trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  Uri _buildUri(String base, String path) {
    // base เช่น: http://localhost หรือ http://10.0.2.2 หรือ https://xxxx.ngrok-free.app
    // path เช่น: /crud/api/chemicals/read_chemicals.php
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';

    // กันซ้ำกรณี base ลงท้ายด้วย /crud แล้ว path ก็ขึ้นต้น /crud
    final normalized = (b.endsWith('/crud') && p.startsWith('/crud'))
        ? b.substring(0, b.length - 5) + p
        : b + p;

    return Uri.parse(normalized);
  }

  Future<void> _loadChemicals() async {
    setState(() => _loadingChemicals = true);

    final prefs = await SharedPreferences.getInstance();
    final base = _readApiBaseUrl(prefs);

    // ถ้าไม่มี baseUrl ก็ fallback ให้กรอกเองได้
    if (base == null) {
      if (!mounted) return;
      setState(() {
        _chemicals = const [];
        _loadingChemicals = false;
      });
      return;
    }

    final uri = _buildUri(base, '/crud/api/chemicals/read_chemicals.php');

    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();

      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _chemicals = const [];
          _loadingChemicals = false;
        });
        return;
      }

      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);

      List records = [];
      if (decoded is Map && decoded['records'] is List) {
        records = decoded['records'] as List;
      } else if (decoded is List) {
        records = decoded;
      }

      final items = <_ChemicalOption>[];
      for (final r in records) {
        if (r is! Map) continue;

        final id = (r['chemical_id'] ?? r['id'])?.toString().trim();
        final name = (r['chemical_name'] ??
                r['name'] ??
                r['chemical'] ??
                r['trade_name'] ??
                r['product_name'])
            ?.toString()
            .trim();

        if (id == null || id.isEmpty) continue;
        if (name == null || name.isEmpty) continue;

        items.add(_ChemicalOption(id: id, name: name));
      }

      if (!mounted) return;
      setState(() {
        _chemicals = items;
        _loadingChemicals = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chemicals = const [];
        _loadingChemicals = false;
      });
    } finally {
      client.close(force: true);
    }
  }

  int get _totalSteps => (_sprayed == 'yes') ? 2 : 1;

  bool _canConfirm() {
    if (_sprayed == null) return false;
    if (_sprayed == 'no') return true;

    // sprayed == yes
    if (_chemicals.isNotEmpty) {
      if (_selectedChemicalId == null) return false;
      if (_selectedChemicalId == '__other__') {
        return _customChemicalCtrl.text.trim().isNotEmpty;
      }
      return true;
    }

    // ไม่มีรายการให้เลือก → ต้องกรอกเอง
    return _customChemicalCtrl.text.trim().isNotEmpty;
  }

  void _goBack() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex -= 1);
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _pickSprayed(String v) {
    setState(() {
      _sprayed = v;

      // reset step2
      _selectedChemicalId = null;
      _customChemicalCtrl.text = '';

      // ถ้าตอบ "พ่น" ให้ไปข้อถัดไปทันที
      if (v == 'yes') {
        _currentIndex = 1;
      } else {
        _currentIndex = 0;
      }
    });

    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = _readUserIdFromPrefs(prefs);

    final sprayedBool = _sprayed == 'yes';

    String? chemicalId;
    String? chemicalName;
    String? customName;

    if (sprayedBool) {
      if (_chemicals.isNotEmpty) {
        if (_selectedChemicalId == '__other__') {
          customName = _customChemicalCtrl.text.trim();
        } else {
          chemicalId = _selectedChemicalId;
          final hit = _chemicals.where((e) => e.id == chemicalId).toList();
          chemicalName = hit.isNotEmpty ? hit.first.name : null;
        }
      } else {
        customName = _customChemicalCtrl.text.trim();
      }
    }

    final payload = <String, dynamic>{
      'tree_id': widget.treeId,
      'disease_id': widget.diseaseId,
      'sprayed': sprayedBool,
      'chemical_id': chemicalId,
      'chemical_name': chemicalName,
      'custom_chemical_name': customName,
      'saved_at': DateTime.now().toIso8601String(),
    };

    final keySuffix = '${uid ?? 'guest'}_${widget.treeId}';
    final lastKey = 'chemical_answers_last_v1_$keySuffix';
    final historyKey = 'chemical_answers_history_v1_$keySuffix';

    await prefs.setString(lastKey, jsonEncode(payload));

    // append history (เก็บล่าสุดไม่เกิน 50 รายการ)
    final raw = prefs.getString(historyKey);
    final List<dynamic> list = [];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) list.addAll(decoded);
      } catch (_) {}
    }
    list.add(payload);
    while (list.length > 50) {
      list.removeAt(0);
    }
    await prefs.setString(historyKey, jsonEncode(list));
  }

  void _goDiseaseQuestions() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DiseaseQuestionsPage(
          treeId: widget.treeId,
          treeName: widget.treeName,
          diseaseId: widget.diseaseId,
          diseaseName: widget.diseaseName,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;

    if (!_canConfirm()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาตอบคำถามให้ครบก่อนยืนยัน')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _saveToPrefs();
      if (!mounted) return;
      _goDiseaseQuestions();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _header() {
    final total = _totalSteps;
    final current = total == 0 ? 0 : (_currentIndex + 1);
    final value = total == 0 ? 0.0 : current / total;
    final percent = (value * 100).clamp(0, 100).toStringAsFixed(0);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kPrimaryGreen,
            kPrimaryGreen.withOpacity(0.92),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 40),
                const Expanded(
                  child: Center(
                    child: Text(
                      'คำถามสารเคมี',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                  color: Colors.white,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'ถามทุกครั้ง (เพื่อใช้ประกอบคำแนะนำและการสลับสาร)',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$percent % completed',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: Colors.white.withOpacity(0.25),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topControlsRow() {
    return Row(
      children: [
        InkWell(
          onTap: _goBack,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.arrow_back, color: Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _selectedBubble() {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _bubbleText(),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16.0,
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _sprayQuestion() {
    return _card(
      title: 'ครั้งนี้มีการพ่นสารเคมีหรือไม่?',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _pillChoice(
            label: 'พ่น',
            selected: _sprayed == 'yes',
            onTap: () => _pickSprayed('yes'),
          ),
          _pillChoice(
            label: 'ไม่พ่น',
            selected: _sprayed == 'no',
            onTap: () => _pickSprayed('no'),
          ),
        ],
      ),
    );
  }

  Widget _pillChoice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: kPrimaryGreen,
          backgroundColor: selected ? kPrimaryGreen.withOpacity(0.08) : Colors.transparent,
          side: const BorderSide(color: kPrimaryGreen, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _chemicalQuestion() {
    // ถ้ายังโหลดรายการสารอยู่
    if (_loadingChemicals) {
      return _card(
        title: 'สารเคมีที่ใช้ในการพ่นครั้งนี้คืออะไร?',
        child: Row(
          children: const [
            SizedBox(width: 8),
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Expanded(child: Text('กำลังโหลดรายการสารเคมี...')),
          ],
        ),
      );
    }

    // ถ้ามีรายการสาร → dropdown + อื่นๆ
    if (_chemicals.isNotEmpty) {
      final items = <DropdownMenuItem<String>>[
        ..._chemicals.map(
          (c) => DropdownMenuItem<String>(
            value: c.id,
            child: Text(c.name),
          ),
        ),
        const DropdownMenuItem<String>(
          value: '__other__',
          child: Text('อื่นๆ (พิมพ์เอง)'),
        ),
      ];

      return _card(
        title: 'สารเคมีที่ใช้ในการพ่นครั้งนี้คืออะไร?',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedChemicalId,
              items: items,
              decoration: InputDecoration(
                hintText: 'เลือกสารเคมี',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.black.withOpacity(0.15)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kPrimaryGreen, width: 2),
                ),
              ),
              onChanged: (v) {
                setState(() {
                  _selectedChemicalId = v;
                  if (v != '__other__') {
                    _customChemicalCtrl.text = '';
                  }
                });
              },
            ),
            if (_selectedChemicalId == '__other__') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customChemicalCtrl,
                decoration: InputDecoration(
                  hintText: 'พิมพ์ชื่อสารเคมีที่ใช้',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.black.withOpacity(0.15)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: kPrimaryGreen, width: 2),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // ไม่มีรายการสารให้เลือก → กรอกเอง
    return _card(
      title: 'สารเคมีที่ใช้ในการพ่นครั้งนี้คืออะไร?',
      child: TextField(
        controller: _customChemicalCtrl,
        decoration: InputDecoration(
          hintText: 'พิมพ์ชื่อสารเคมีที่ใช้',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.black.withOpacity(0.15)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kPrimaryGreen, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _bottomButton() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: (_submitting || !_canConfirm()) ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE5E5E5),
              disabledForegroundColor: const Color(0xFF9E9E9E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: const Text(
              'ยืนยัน',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalSteps;
    final hasStep2 = total == 2;

    return Scaffold(
      backgroundColor: kPageBg,
      body: Column(
        children: [
          _header(),
          Expanded(
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _topControlsRow(),
                          const SizedBox(height: 10),
                          _selectedBubble(),
                          const SizedBox(height: 14),
                          if (_currentIndex == 0) _sprayQuestion(),
                          if (_currentIndex == 1 && hasStep2) _chemicalQuestion(),
                          if (_currentIndex == 1 && !hasStep2)
                            _sprayQuestion(), // กัน state แปลก ๆ
                        ],
                      ),
                    ),
                  ),
                  _bottomButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
