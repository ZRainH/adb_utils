import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/adb_command_catalog.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/command_run_dialog.dart';

class CommandReferencePage extends StatefulWidget {
  const CommandReferencePage({super.key, this.state});

  final AppState? state;

  @override
  State<CommandReferencePage> createState() => _CommandReferencePageState();
}

class _CommandReferencePageState extends State<CommandReferencePage> {
  late final List<AdbCommandSection> _sections = buildAdbCommandCatalog();
  final _commandController = TextEditingController();
  final _commandFocusNode = FocusNode();
  final _transcriptScrollController = ScrollController();
  String _localQuery = '';
  String _transcript = '';
  bool _running = false;

  @override
  void initState() {
    super.initState();
    widget.state?.addListener(_onState);
  }

  @override
  void dispose() {
    widget.state?.removeListener(_onState);
    _commandController.dispose();
    _commandFocusNode.dispose();
    _transcriptScrollController.dispose();
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

  void _loadCommand(String command) {
    final serial = widget.state?.selectedDevice?.id;
    _commandController.text =
        prepareHandbookCommand(command, deviceSerial: serial);
    _commandFocusNode.requestFocus();
    setState(() {});
  }

  void _scrollTranscriptToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_transcriptScrollController.hasClients) return;
      _transcriptScrollController.animateTo(
        _transcriptScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _appendTranscript(String command, String output) {
    final buf = StringBuffer(_transcript);
    if (_transcript.isNotEmpty) buf.writeln();
    buf.writeln('> $command');
    buf.write(output);
    if (output.isNotEmpty && !output.endsWith('\n')) buf.writeln();
    _transcript = buf.toString();
  }

  Future<void> _copy(String command) async {
    final text = command.replaceAll('\n', ' ').trim();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制：$text')),
    );
  }

  Future<void> _executeCommand() async {
    final state = widget.state;
    if (state == null || _running) return;

    final command = _commandController.text.trim();
    final validationError = validateHandbookCommand(state, command);
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationError)),
      );
      return;
    }

    final ok = await confirmDangerousHandbookCommand(context, state, command);
    if (!ok || !mounted) return;

    setState(() => _running = true);
    _scrollTranscriptToBottom();

    final output = await state.adb.runCommand(state.selectedDevice?.id, command);

    if (!mounted) return;
    setState(() {
      _running = false;
      _appendTranscript(command, output);
    });
    _scrollTranscriptToBottom();
  }

  void _clearTerminal() {
    _commandController.clear();
    setState(() => _transcript = '');
  }

  Future<void> _copyTranscript() async {
    if (_transcript.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _transcript));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('终端内容已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _filtered;
    final fontSize = widget.state?.settings.terminalFontSize ?? 13;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PageHeader(
            totalCommands:
                _sections.fold<int>(0, (s, e) => s + e.items.length),
            visibleCommands: _commandCount,
          ),
          const SizedBox(height: 12),
          _SearchBar(onQueryChanged: (v) => setState(() => _localQuery = v)),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: sections.isEmpty
                      ? Center(
                          child: Text(
                            '未找到匹配的命令',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : Scrollbar(
                          thumbVisibility: true,
                          child: ListView(
                            padding: const EdgeInsets.only(bottom: 8),
                            children: [
                              for (var i = 0; i < sections.length; i++) ...[
                                if (i > 0) const SizedBox(height: 16),
                                _SectionCard(
                                  section: sections[i],
                                  onLoad: _loadCommand,
                                  onCopy: _copy,
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _CmdTerminalPanel(
                    state: widget.state,
                    fontSize: fontSize,
                    commandController: _commandController,
                    commandFocusNode: _commandFocusNode,
                    transcript: _transcript,
                    running: _running,
                    scrollController: _transcriptScrollController,
                    onRun: _executeCommand,
                    onClear: _clearTerminal,
                    onCopy: _copyTranscript,
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

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.totalCommands,
    required this.visibleCommands,
  });

  final int totalCommands;
  final int visibleCommands;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ADB 指令手册',
          style: TextStyle(
            fontSize: 24,
            height: 1.25,
            letterSpacing: -0.5,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '共 $totalCommands 条'
          '${visibleCommands == totalCommands ? '' : ' · 显示 $visibleCommands 条'}'
          ' · 点击左侧命令填入终端',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onQueryChanged});

  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onQueryChanged,
      style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: "筛选命令（如 'logcat'、'pm'、'install'）…",
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceElevated,
        prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.accentBright),
        ),
      ),
    );
  }
}

class _CmdTerminalPanel extends StatelessWidget {
  const _CmdTerminalPanel({
    required this.state,
    required this.fontSize,
    required this.commandController,
    required this.commandFocusNode,
    required this.transcript,
    required this.running,
    required this.scrollController,
    required this.onRun,
    required this.onClear,
    required this.onCopy,
  });

  static const _cmdBg = Color(0xFF0C0C0C);
  static const _cmdText = Color(0xFFCCCCCC);
  static const _cmdPrompt = Color(0xFFE5E5E5);

  final AppState? state;
  final double fontSize;
  final TextEditingController commandController;
  final FocusNode commandFocusNode;
  final String transcript;
  final bool running;
  final ScrollController scrollController;
  final VoidCallback onRun;
  final VoidCallback onClear;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final device = state?.selectedDevice;
    final title = device == null
        ? 'ADB 终端 · 未选择设备'
        : 'ADB 终端 · ${device.name}';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _cmdBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.6))),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
                IconButton(
                  tooltip: '复制',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(Icons.copy_rounded, size: 14, color: AppColors.textSecondary),
                  onPressed: transcript.isEmpty ? null : onCopy,
                ),
                IconButton(
                  tooltip: '清屏',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(Icons.delete_outline, size: 14, color: AppColors.textSecondary),
                  onPressed: running ? null : onClear,
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: SelectableText(
                  transcript.isEmpty
                      ? 'Microsoft Windows [Version 10.0.26200]\n(c) adb_utils. 保留所有权利。\n\n输入 adb 命令，或点击左侧手册命令填入。\n'
                      : transcript,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: fontSize,
                    height: 1.4,
                    color: _cmdText,
                  ),
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _cmdBg,
              border: Border(top: BorderSide(color: AppColors.border.withValues(alpha: 0.6))),
            ),
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'adb>',
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: fontSize,
                    color: _cmdPrompt,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: commandController,
                    focusNode: commandFocusNode,
                    enabled: !running,
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: fontSize,
                      color: _cmdText,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: '',
                    ),
                    cursorColor: _cmdText,
                    onSubmitted: running ? null : (_) => onRun(),
                  ),
                ),
                if (running)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _cmdText.withValues(alpha: 0.8),
                      ),
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.onLoad,
    required this.onCopy,
  });

  final AdbCommandSection section;
  final ValueChanged<String> onLoad;
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
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
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${section.items.length}',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                    onLoad: onLoad,
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
    required this.onLoad,
    required this.onCopy,
  });

  final AdbCommandItem item;
  final Color commandColor;
  final ValueChanged<String> onLoad;
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
              onTap: () => widget.onLoad(widget.item.command),
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
                      child: IconButton(
                        tooltip: '复制',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        icon: Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => widget.onCopy(widget.item.command),
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
    final style = TextStyle(
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
                style: TextStyle(
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
