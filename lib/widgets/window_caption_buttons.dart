import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_colors.dart';

/// Custom minimize / maximize / close for frameless Windows chrome.
class WindowCaptionButtons extends StatefulWidget {
  const WindowCaptionButtons({super.key});

  @override
  State<WindowCaptionButtons> createState() => _WindowCaptionButtonsState();
}

class _WindowCaptionButtonsState extends State<WindowCaptionButtons>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _refreshMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => _setMaximized(true);

  @override
  void onWindowUnmaximize() => _setMaximized(false);

  @override
  void onWindowRestore() => _refreshMaximized();

  Future<void> _refreshMaximized() async {
    final value = await windowManager.isMaximized();
    _setMaximized(value);
  }

  void _setMaximized(bool value) {
    if (!mounted || _maximized == value) return;
    setState(() => _maximized = value);
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.textSecondaryOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          tooltip: '最小化',
          icon: Icons.remove,
          color: color,
          onTap: windowManager.minimize,
        ),
        _CaptionButton(
          tooltip: _maximized ? '还原' : '最大化',
          icon: _maximized
              ? Icons.filter_none_rounded
              : Icons.crop_square_rounded,
          color: color,
          onTap: _toggleMaximize,
        ),
        _CaptionButton(
          tooltip: '关闭',
          icon: Icons.close,
          color: color,
          hoverColor: const Color(0xFFE81123),
          hoverIconColor: Colors.white,
          onTap: windowManager.close,
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.onTap,
    required this.color,
    this.tooltip,
    this.hoverColor,
    this.hoverIconColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final String? tooltip;
  final Color? hoverColor;
  final Color? hoverIconColor;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hover
        ? (widget.hoverColor ?? AppColors.chipOf(context))
        : Colors.transparent;
    final iconColor = _hover && widget.hoverIconColor != null
        ? widget.hoverIconColor!
        : widget.color;

    final button = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 46,
          height: 48,
          alignment: Alignment.center,
          color: bg,
          child: Icon(widget.icon, size: 16, color: iconColor),
        ),
      ),
    );

    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}
