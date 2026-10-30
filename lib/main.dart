import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  initializeDateFormatting('zh');
  runApp(const KcalPlanApp());
}

class KcalPlanApp extends StatelessWidget {
  const KcalPlanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kcal Plan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

const _kWorkoutTypes = [
  '跑步', '快走', '骑行', '游泳', '健身', '瑜伽', '球类', '其他',
];

class WorkoutEntry {
  final DateTime date;
  final int kcal;
  final String type;

  WorkoutEntry({required this.date, required this.kcal, required this.type});

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'kcal': kcal,
        'type': type,
      };

  factory WorkoutEntry.fromJson(Map<String, dynamic> json) => WorkoutEntry(
        date: DateTime.parse(json['date'] as String),
        kcal: json['kcal'] as int,
        type: json['type'] as String,
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _kEntries = 'entries';
  static const _kGoal = 'weeklyGoal';

  int _weeklyGoal = 2000;
  List<WorkoutEntry> _entries = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _weeklyGoal = sp.getInt(_kGoal) ?? 2000;
      _entries = (jsonDecode(sp.getString(_kEntries) ?? '[]') as List)
          .map((e) => WorkoutEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _loaded = true;
    });
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kGoal, _weeklyGoal);
    await sp.setString(
        _kEntries, jsonEncode(_entries.map((e) => e.toJson()).toList()));
  }

  // 本周一 00:00
  DateTime get _weekStart {
    final now = DateTime.now();
    final weekday = now.weekday; // Mon=1
    return DateTime(now.year, now.month, now.day - (weekday - 1));
  }

  List<WorkoutEntry> get _weekEntries =>
      _entries.where((e) => !e.date.isBefore(_weekStart)).toList();

  int get _weekTotal =>
      _weekEntries.fold(0, (sum, e) => sum + e.kcal);

  int get _remaining => _weeklyGoal - _weekTotal;

  double get _progress =>
      _weeklyGoal <= 0 ? 0 : (_weekTotal / _weeklyGoal).clamp(0.0, 1.0);

  /// 按天统计（本周 7 天）
  List<double> get _dailyTotals {
    final totals = List<double>.filled(7, 0);
    for (final e in _weekEntries) {
      final diff = DateTime(e.date.year, e.date.month, e.date.day)
          .difference(DateTime(_weekStart.year, _weekStart.month,
              _weekStart.day))
          .inDays;
      if (diff >= 0 && diff < 7) totals[diff] += e.kcal;
    }
    return totals;
  }

  /// 按周统计（最近 8 周）
  List<double> get _weeklyTotals {
    final totals = List<double>.filled(8, 0);
    final thisWeekStart = _weekStart;
    for (final e in _entries) {
      final diff = DateTime(e.date.year, e.date.month, e.date.day)
              .difference(thisWeekStart)
              .inDays ~/
          7;
      final idx = 7 + diff; // diff 为负表示过去的周
      if (idx >= 0 && idx < 8) totals[idx] += e.kcal;
    }
    return totals;
  }

  Future<void> _addEntry() async {
    final kcalCtrl = TextEditingController();
    String type = _kWorkoutTypes.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加记录'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: kcalCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '卡路里 (Kcal)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(
                  labelText: '运动类型',
                  border: OutlineInputBorder(),
                ),
                items: _kWorkoutTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) =>
                    setDialogState(() => type = v ?? type),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final kcal = int.tryParse(kcalCtrl.text.trim());
    if (kcal == null || kcal <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入有效的卡路里数值')),
        );
      }
      return;
    }
    setState(() {
      _entries.add(WorkoutEntry(date: DateTime.now(), kcal: kcal, type: type));
    });
    await _persist();
  }

  Future<void> _setGoal() async {
    final ctrl = TextEditingController(text: '$_weeklyGoal');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置每周卡路里目标 (Kcal)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            suffixText: 'Kcal',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final goal = int.tryParse(ctrl.text.trim());
    if (goal == null || goal <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入有效的目标数值')),
        );
      }
      return;
    }
    setState(() => _weeklyGoal = goal);
    await _persist();
  }

  Future<void> _deleteEntry(WorkoutEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: Text(
            '确定删除这条记录吗？\n${DateFormat('M/d EEEE', 'zh').format(entry.date)} · ${entry.type} · ${entry.kcal} Kcal'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _entries.remove(entry));
    await _persist();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('记录已删除'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () async {
              setState(() => _entries.add(entry));
              await _persist();
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final daily = _dailyTotals;
    final weekly = _weeklyTotals;
    final remaining = _remaining;

    return Scaffold(
      appBar: AppBar(
        title: const Text('每周卡路里记录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: '设置每周目标',
            onPressed: _setGoal,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 目标进度卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('本周目标',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text('$_weeklyGoal Kcal',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _progress, minHeight: 10),
                  const SizedBox(height: 12),
                  Text('已消耗 $_weekTotal Kcal'),
                  const SizedBox(height: 4),
                  Text(
                    remaining > 0
                        ? '距离目标还差 $remaining Kcal'
                        : '已超出目标 ${-remaining} Kcal 🎉',
                    style: TextStyle(
                      color: remaining > 0 ? Colors.orange : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 按天图表
          _ChartCard(
            title: '按天统计（本周）',
            barGroups: List.generate(7, (i) {
              return BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: daily[i],
                  color: Theme.of(context).colorScheme.primary,
                  width: 16,
                  borderRadius: BorderRadius.circular(4),
                ),
              ]);
            }),
            xLabels: const ['一', '二', '三', '四', '五', '六', '日'],
          ),
          const SizedBox(height: 16),
          // 按周图表
          _ChartCard(
            title: '按周统计（最近 8 周）',
            barGroups: List.generate(8, (i) {
              return BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: weekly[i],
                  color: Theme.of(context).colorScheme.secondary,
                  width: 16,
                  borderRadius: BorderRadius.circular(4),
                ),
              ]);
            }),
            xLabels: List.generate(8, (i) {
              final start =
                  _weekStart.subtract(Duration(days: (7 - i) * 7));
              return DateFormat('M/d').format(start);
            }),
          ),
          const SizedBox(height: 16),
          // 记录列表（仅本周，可删除）
          _RecordsCard(
            entries: _entries
                .where((e) => !e.date.isBefore(_weekStart))
                .toList(),
            onDelete: _deleteEntry,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEntry,
        icon: const Icon(Icons.add),
        label: const Text('记录'),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final List<BarChartGroupData> barGroups;
  final List<String> xLabels;

  const _ChartCard({
    required this.title,
    required this.barGroups,
    required this.xLabels,
  });

  @override
  Widget build(BuildContext context) {
    final maxY = () {
      double maxV = 0;
      for (final g in barGroups) {
        for (final rod in g.barRods) {
          if (rod.toY > maxV) maxV = rod.toY;
        }
      }
      return maxV == 0 ? 100.0 : maxV * 1.2;
    }();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (v, meta) => Text(
                          v.toInt().toString(),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, meta) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            (v.toInt() >= 0 && v.toInt() < xLabels.length)
                                ? xLabels[v.toInt()]
                                : '',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                  ),
                  barGroups: barGroups,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordsCard extends StatelessWidget {
  final List<WorkoutEntry> entries;
  final void Function(WorkoutEntry) onDelete;

  const _RecordsCard({required this.entries, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final sorted = List<WorkoutEntry>.from(entries)
      ..sort((a, b) => b.date.compareTo(a.date));

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('本周记录（${sorted.length}）',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            if (sorted.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('暂无记录')),
              )
            else
              ...sorted.map((e) => ListTile(
                    leading: const Icon(Icons.directions_run),
                    title: Text(
                        '${DateFormat('M/d EEEE', 'zh').format(e.date)} · ${e.type}'),
                    subtitle: Text(DateFormat('HH:mm').format(e.date)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${e.kcal} Kcal',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: '删除',
                          onPressed: () => onDelete(e),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
