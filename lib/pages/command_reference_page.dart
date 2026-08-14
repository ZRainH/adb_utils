import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/adb_command_catalog.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';

class CommandReferencePage extends StatefulWidget {
  const CommandReferencePage({super.key, this.state});

  final AppState? state;

  @override
  State<CommandReferencePage> createState() => _CommandReferencePageState();
}

class _CommandReferencePageState extends State<CommandReferencePage> {
  late final List<AdbCommandSection> _sections = buildAdbCommandCatalog();
  String _localQuery = '';

  @override
  void initState() {
    super.initState();
    widget.state?.addListener(_onState);
  }

  @override
  void dispose() {
    widget.state?.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  String get _query {
    final global = widget.state?.searchQuery.trim() ?? '';
    if (global.isNotEmpty) return global;
    return _localQuery;
  }

  List<AdbCommandSection> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _sections;
    return [
      for (final section in _sections)
        AdbCommandSection(
          title: section.title,
          icon: section.icon,
          commandColor: section.commandColor,
          items: [
            for (final item in section.items)
              if (item.command.toLowerCase().contains(q) ||
                  item.description.toLowerCase().contains(q) ||
                  section.title.toLowerCase().contains(q))
                item,
          ],
        ),
    ].where((s) => s.items.isNotEmpty).toList();
  }

  int get _commandCount =>
      _filtered.fold<int>(0, (sum, s) => sum + s.items.length);

  Future<void> _copy(String command) async {
    final text = command.replaceAll('\n', ' ').trim();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制：$text')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _filtered;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              query: _localQuery,
              totalCommands: _sections.fold<int>(0, (s, e) => s + e.items.length),
              visibleCommands: _commandCount,
              onQueryChanged: (v) => setState(() => _localQuery = v),
            ),
            const SizedBox(height: 24),
            if (sections.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    '未找到匹配的命令',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  if (!wide) {
                    return Column(
                      children: [
                        for (var i = 0; i < sections.length; i++) ...[
                          if (i > 0) const SizedBox(height: 16),
                          _SectionCard(section: sections[i], onCopy: _copy),
                        ],
                      ],
                    );
                  }
                  final left = <AdbCommandSection>[];
                  final right = <AdbCommandSection>[];
                  for (var i = 0; i < sections.length; i++) {
                    if (i.isEven) {
                      left.add(sections[i]);
                    } else {
                      right.add(sections[i]);
                    }
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _ColumnList(sections: left, onCopy: _copy)),
                      const SizedBox(width: 16),
                      Expanded(child: _ColumnList(sections: right, onCopy: _copy)),
                    ],
                  );
                },
              ),
            const SizedBox(height: 32),
            const Text(
              '注意：执行命令前请确认目标设备已授权 USB 调试。'
              'root / remount / verity / 备份恢复等操作可能影响系统稳定性，请谨慎使用。'
              '部分命令依赖 Android 版本与 ROM 能力。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.45,
                letterSpacing: 0.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColumnList extends StatelessWidget {
  const _ColumnList({required this.sections, required this.onCopy});

  final List<AdbCommandSection> sections;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _SectionCard(section: sections[i], onCopy: onCopy),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.query,
    required this.totalCommands,
    required this.visibleCommands,
    required this.onQueryChanged,
  });

  final String query;
  final int totalCommands;
  final int visibleCommands;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 24),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ADB 指令手册',
                  style: TextStyle(
                    fontSize: 32,
                    height: 1.25,
                    letterSpacing: -0.8,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '共 $totalCommands 条常用命令'
                  '${visibleCommands == totalCommands ? '' : ' · 当前显示 $visibleCommands 条'}',
                  style: const TextStyle(
                    fontSize: 16,
                    letterSpacing: 0.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 360,
            child: TextField(
              onChanged: onQueryChanged,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: "筛选命令（如 'logcat'、'pm'、'input'）…",
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  letterSpacing: 0.25,
                ),
                filled: true,
                fillColor: AppColors.surfaceElevated,
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(color: AppColors.accentBright),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.onCopy});

  final AdbCommandSection section;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Icon(section.icon, size: 18, color: AppColors.textPrimary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${section.items.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (var i = 0; i < section.items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _CommandBlock(
                    item: section.items[i],
                    commandColor: section.commandColor,
                    onCopy: onCopy,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandBlock extends StatefulWidget {
  const _CommandBlock({
    required this.item,
    required this.commandColor,
    required this.onCopy,
  });

  final AdbCommandItem item;
  final Color commandColor;
  final ValueChanged<String> onCopy;

  @override
  State<_CommandBlock> createState() => _CommandBlockState();
}

class _CommandBlockState extends State<_CommandBlock> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => widget.onCopy(widget.item.command),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDeep,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderSoft),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        widget.item.command,
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 13,
                          height: 1.45,
                          color: widget.commandColor,
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: _hovered ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: _DescriptionText(
            text: widget.item.description,
            codes: widget.item.inlineCodes,
          ),
        ),
      ],
    );
  }
}

class _DescriptionText extends StatelessWidget {
  const _DescriptionText({required this.text, required this.codes});

  final String text;
  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 13,
      height: 1.4,
      letterSpacing: 0.2,
      color: AppColors.textSecondary,
    );

    if (codes.isEmpty || !text.contains('{code}')) {
      return Text(text, style: style);
    }

    final spans = <InlineSpan>[];
    final parts = text.split('{code}');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) {
        spans.add(TextSpan(text: parts[i], style: style));
      }
      if (i < codes.length) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                codes[i],
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 12,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        );
      }
    }
    return Text.rich(TextSpan(children: spans));
  }
}
