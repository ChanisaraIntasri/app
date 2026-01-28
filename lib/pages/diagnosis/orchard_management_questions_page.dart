import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chemical_questions_page.dart';
import 'disease_questions_page.dart';

// โทนสีเดียวกับหน้า DiseaseQuestionsPage
const kPrimaryGreen = Color(0xFF005E33);
const kPageBg = Color.fromARGB(255, 255, 255, 255);
const kCardBg = Colors.white;

class _Choice {
  final String id;
  final String label;

  const _Choice({required this.id, required this.label});
}

class _Question {
  final String id;
  final String text;
  final String type; // 'single' | 'multi' | 'numeric'
  final List<_Choice> choices;

  const _Question({
    required this.id,
    required this.text,
    required this.type,
    required this.choices,
  });
}

// ✅ ชุดคำถาม (Local)
List<_Question> _defaultQuestions() {
  return const [
    _Question(
      id: 'q_orch_1',
      text: 'สวนของคุณมีการพ่นสารป้องกันกำจัดโรค/แมลงเป็นประจำหรือไม่?',
      type: 'single',
      choices: [
        _Choice(id: 'c1', label: 'พ่นเป็นประจำ'),
        _Choice(id: 'c2', label: 'พ่นบางครั้ง'),
        _Choice(id: 'c3', label: 'ไม่ได้พ่น'),
      ],
    ),
    _Question(
      id: 'q_orch_2',
      text: 'คุณมีการตัดแต่งกิ่ง/ลดความชื้นในทรงพุ่มหรือไม่?',
      type: 'single',
      choices: [
        _Choice(id: 'c1', label: 'ทำเป็นประจำ'),
        _Choice(id: 'c2', label: 'ทำบ้างเป็นครั้งคราว'),
        _Choice(id: 'c3', label: 'ไม่ได้ทำ'),
      ],
    ),
    _Question(
      id: 'q_orch_3',
      text: 'ตอนนี้ในสวนมีอาการเหล่านี้ร่วมด้วยหรือไม่?\n(ตอบได้มากกว่า 1 ข้อ)',
      type: 'multi',
      choices: [
        _Choice(id: 'c1', label: 'ใบอ่อนมีจุด/รอยผิดปกติหลายใบ'),
        _Choice(id: 'c2', label: 'ผลมีรอย/จุดผิดปกติ'),
        _Choice(id: 'c3', label: 'พบแมลงพาหะจำนวนมาก'),
        _Choice(id: 'c4', label: 'พบอาการลุกลามเร็วในหลายต้น'),
      ],
    ),
  ];
}

class OrchardManagementQuestionsPage extends StatefulWidget {
  final String treeId;
  final String? treeName;
  final String diseaseId;
  final String diseaseName;

  /// ✅ โหมดแก้ไข: เปิดจาก Setting/Share เพื่อดูคำตอบเดิมและแก้ไข
  /// - จะไม่ข้ามหน้าแม้เคยทำแล้ว
  /// - กดยืนยันแล้วบันทึกและกลับหน้าก่อนหน้า
  final bool editMode;

  const OrchardManagementQuestionsPage({
    super.key,
    required this.treeId,
    this.treeName,
    required this.diseaseId,
    required this.diseaseName,
    this.editMode = false,
  });

  @override
  State<OrchardManagementQuestionsPage> createState() =>
      _OrchardManagementQuestionsPageState();
}

class _OrchardManagementQuestionsPageState
    extends State<OrchardManagementQuestionsPage> {
  static const String _onceKeyBase = 'orchard_management_answered_v1';
  static const String _answersKeyBase = 'orchard_management_answers_v1';

  String _onceKey = _onceKeyBase;
  String _answersKey = _answersKeyBase;

  final _scroll = ScrollController();

  bool _checkingOnce = true;
  bool _submitting = false;

  int _currentIndex = 0;
  late final List<_Question> _questions;

  /// answers:
  /// - single: String choiceId
  /// - multi : Set<String> choiceIds
  final Map<String, dynamic> _answers = {};

  @override
  void initState() {
    super.initState();
    _questions = _defaultQuestions();
    _initStorageAndFlow();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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

  Future<void> _initStorageAndFlow() async {
    final prefs = await SharedPreferences.getInstance();

    // 1) แยก key ต่อ user (ถ้ามี)
    final uid = _readUserIdFromPrefs(prefs);
    if (uid != null) {
      _onceKey = '${_onceKeyBase}_$uid';
      _answersKey = '${_answersKeyBase}_$uid';

      // migrate จาก key เก่า (ไม่ต่อท้าย uid)
      if (!prefs.containsKey(_onceKey) && prefs.containsKey(_onceKeyBase)) {
        final old = prefs.getBool(_onceKeyBase);
        if (old != null) await prefs.setBool(_onceKey, old);
      }
      if (!prefs.containsKey(_answersKey) && prefs.containsKey(_answersKeyBase)) {
        final old = prefs.getString(_answersKeyBase);
        if (old != null && old.trim().isNotEmpty) {
          await prefs.setString(_answersKey, old);
        }
      }
    }

    // 2) โหลดคำตอบเดิม (ถ้ามี)
    final hadAnswers = await _loadSavedAnswers(prefs);

    // 3) ถ้าไม่ใช่ editMode และเคยทำแล้ว (และมีคำตอบจริง) → ข้ามไป “คำถามสารเคมี” (เพราะถามทุกครั้ง)
    if (!widget.editMode) {
      final done = prefs.getBool(_onceKey) ?? false;

      // ป้องกันกรณี flag true แต่ไม่มี answers (ข้อมูลไม่ครบ) -> บังคับให้ตอบใหม่
      if (done && !hadAnswers) {
        await prefs.setBool(_onceKey, false);
      } else if (done && hadAnswers) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _goChemicalQuestions();
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() => _checkingOnce = false);
  }

  Future<bool> _loadSavedAnswers(SharedPreferences prefs) async {
    try {
      final raw = prefs.getString(_answersKey);
      if (raw == null || raw.trim().isEmpty) return false;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;

      _answers.clear();
      decoded.forEach((k, v) {
        final key = k.toString();
        if (v is List) {
          _answers[key] = v.map((e) => e.toString()).toSet();
        } else {
          _answers[key] = v;
        }
      });

      // ถือว่ามีข้อมูล ถ้าอย่างน้อย 1 ข้อมีค่า
      for (final q in _questions) {
        if (_isAnswered(q)) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  String _bubbleText() {
    final t = (widget.treeName ?? '').trim();
    if (t.isNotEmpty) return '${widget.diseaseName} • $t';
    return widget.diseaseName;
  }

  bool _isAnswered(_Question q) {
    final v = _answers[q.id];
    if (q.type == 'multi') return v is Set<String> && v.isNotEmpty;
    return v != null && v.toString().trim().isNotEmpty;
  }

  bool _validateAll() {
    for (final q in _questions) {
      if (!_isAnswered(q)) return false;
    }
    return true;
  }

  Future<void> _saveOnceAndAnswers() async {
    final prefs = await SharedPreferences.getInstance();

    final Map<String, dynamic> payload = {};
    _answers.forEach((k, v) {
      if (v is Set<String>) {
        payload[k] = v.toList();
      } else {
        payload[k] = v;
      }
    });

    await prefs.setString(_answersKey, jsonEncode(payload));
    await prefs.setBool(_onceKey, true);
  }

  void _goChemicalQuestions() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChemicalQuestionsPage(
          treeId: widget.treeId,
          treeName: widget.treeName,
          diseaseId: widget.diseaseId,
          diseaseName: widget.diseaseName,
        ),
      ),
    );
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

    if (!_validateAll()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังตอบไม่ครบทุกข้อ')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _saveOnceAndAnswers();
      if (!mounted) return;

      if (widget.editMode) {
        Navigator.of(context).pop(true);
      } else {
        // ✅ เปลี่ยน flow: บันทึกแล้วไป “คำถามสารเคมี”
        _goChemicalQuestions();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _goNext() {
    final q = _questions[_currentIndex];
    if (!_isAnswered(q)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาตอบคำถามก่อนกดถัดไป')),
      );
      return;
    }
    if (_currentIndex < _questions.length - 1) {
      setState(() => _currentIndex += 1);
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
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

  // =========================
  // UI
  // =========================

  Widget _header() {
    final total = _questions.length;
    final current = total == 0 ? 0 : (_currentIndex + 1);
    final value = total == 0 ? 0.0 : current / total;
    final percent = (value * 100).clamp(0, 100).toStringAsFixed(0);

    final title = widget.editMode ? 'การจัดการสวนส้ม' : 'คำถามการจัดการสวนส้ม';
    final sub = widget.editMode ? 'แก้ไขข้อมูลที่เคยตอบ' : 'ทำครั้งแรกเท่านั้น (ถามครั้งเดียว)';

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
                Expanded(
                  child: Center(
                    child: Text(
                      title,
                      style: const TextStyle(
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
              sub,
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

  Widget _questionCard(_Question q) {
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
            q.text,
            style: const TextStyle(
              fontSize: 16.0,
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          if (q.type == 'single') _singleChoices(q),
          if (q.type == 'multi') _multiChoices(q),
        ],
      ),
    );
  }

  void _pickSingleAndMaybeNext(String qid, String choiceId) {
    setState(() => _answers[qid] = choiceId);

    final isLast = _currentIndex >= _questions.length - 1;

    // ✅ เดิม: ถ้าข้อสุดท้ายจะ auto submit
    // ✅ ใหม่: ข้อสุดท้ายให้ผู้ใช้กด “บันทึก” เอง
    if (!isLast) {
      Future.delayed(const Duration(milliseconds: 140), _goNext);
    }
  }

  Widget _multiChoices(_Question q) {
    final current = _answers[q.id];
    final selected = current is Set<String> ? current : <String>{};

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: q.choices.map((c) {
        final isSelected = selected.contains(c.id);
        return SizedBox(
          height: 44,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: kPrimaryGreen,
              backgroundColor:
                  isSelected ? kPrimaryGreen.withOpacity(0.08) : Colors.transparent,
              side: const BorderSide(color: kPrimaryGreen, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            onPressed: () {
              final next = {...selected};
              if (isSelected) {
                next.remove(c.id);
              } else {
                next.add(c.id);
              }
              setState(() => _answers[q.id] = next);
            },
            child: Text(
              c.label,
              style:
                  const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _singleChoices(_Question q) {
    final selected = _answers[q.id]?.toString();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: q.choices.map((c) {
        final isSelected = selected == c.id;
        return SizedBox(
          height: 44,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: kPrimaryGreen,
              backgroundColor:
                  isSelected ? kPrimaryGreen.withOpacity(0.08) : Colors.transparent,
              side: const BorderSide(color: kPrimaryGreen, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            onPressed: () => _pickSingleAndMaybeNext(q.id, c.id),
            child: Text(
              c.label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _navButtons() {
    if (_questions.isEmpty) return const SizedBox.shrink();

    final q = _questions[_currentIndex.clamp(0, _questions.length - 1)];
    final isLast = _currentIndex >= _questions.length - 1;
    final canProceed = _isAnswered(q);

    // ✅ เดิม: แสดงปุ่มเฉพาะ multi
    // ✅ ใหม่: ข้อสุดท้ายต้องมีปุ่ม “บันทึก” เสมอ
    final shouldShow = (q.type == 'multi') || isLast;
    if (!shouldShow) return const SizedBox(height: 14);

    final label = isLast ? 'บันทึก' : 'ต่อไป';
    final onTap = isLast ? _submit : _goNext;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: (_submitting || !canProceed) ? null : onTap,
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
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingOnce) {
      return const Scaffold(
        backgroundColor: kPageBg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final hasQuestions = _questions.isNotEmpty;
    final total = _questions.length;

    return Scaffold(
      backgroundColor: kPageBg,
      body: Column(
        children: [
          _header(),
          Expanded(
            child: !hasQuestions
                ? const Center(child: Text('ยังไม่มีคำถามการจัดการสวนส้ม'))
                : SafeArea(
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
                                _questionCard(
                                  _questions[_currentIndex.clamp(0, total - 1)],
                                ),
                              ],
                            ),
                          ),
                        ),
                        _navButtons(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
