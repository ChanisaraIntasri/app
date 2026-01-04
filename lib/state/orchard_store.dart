//เพราะ Home ต้องรู้ “ต้นทั้งหมด” เพื่อรวมกลุ่มโรค+severity แล้ววาดลงปฏิทิน

import 'package:flutter/foundation.dart';
import '../models/citrus_tree_record.dart';

class OrchardStore extends ChangeNotifier {
  final List<CitrusTreeRecord> _trees = [];
  List<CitrusTreeRecord> get trees => List.unmodifiable(_trees);

  void setTrees(List<CitrusTreeRecord> items) {
    _trees
      ..clear()
      ..addAll(items);
    notifyListeners();
  }

  void updateTree(CitrusTreeRecord updated) {
    final i = _trees.indexWhere((t) => t.id == updated.id);
    if (i >= 0) {
      _trees[i] = updated;
    } else {
      _trees.add(updated);
    }
    notifyListeners();
  }
}
