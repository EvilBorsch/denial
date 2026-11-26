import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 't3_code_controller.dart';
import 't3_code_models.dart';

/// Dedicated record/mic pill button for the desktop taskbar.
class T3TopBarVoiceButton extends ConsumerStatefulWidget {
  const T3TopBarVoiceButton({required this.horizontal, super.key});

  final bool horizontal;

  @override
  ConsumerState<T3TopBarVoiceButton> createState() =>
      _T3TopBarVoiceButtonState();
}

class _T3TopBarVoiceButtonState extends ConsumerState<T3TopBarVoiceButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      shellSettingsProvider.select((s) => s.t3Code.enabled),
    );
    if (!enabled) return const SizedBox.shrink();

    final voicePhase = ref.watch(
      t3CodeControllerProvider.select((s) => s.voicePhase),
    );
    final recording = voicePhase == T3VoicePhase.recording;
    final busy =
        voicePhase == T3VoicePhase.connecting ||
        voicePhase == T3VoicePhase.finishing ||
        voicePhase == T3VoicePhase.sending;
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final accent = theme.accentPalette;

    final bg = recording
        ? const Color(0xFFDC2626)
        : busy
        ? accent.container
        : _hovered
        ? colors.surfaceContainerHighest
        : theme.cardColor(colors.surfaceContainerHigh);
    final fg = recording
        ? Colors.white
        : busy
        ? accent.onContainer
        : colors.textPrimary;

    return Semantics(
      button: true,
      label: recording
          ? 'Остановить и отправить голосовой запрос T3'
          : 'Голосовой запрос в T3 Code',
      child: MouseRegion(
        cursor: ShellMouseCursors.link,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              unawaited(ref.read(t3CodeControllerProvider.notifier).toggleVoice()),
          child: AnimatedContainer(
            duration: Motion.pill,
            curve: Motion.standard,
            padding: widget.horizontal
                ? const EdgeInsets.symmetric(horizontal: 10)
                : const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: recording
                    ? const Color(0x66FCA5A5)
                    : colors.hairlineSoft,
              ),
            ),
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    )
                  : Icon(
                      recording ? Icons.stop_rounded : Icons.mic_rounded,
                      size: 16,
                      color: fg,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dynamic Island capsule mounted in the center free space of the desktop top
/// bar and the tablet status bar.
class T3DynamicIslandPill extends ConsumerStatefulWidget {
  const T3DynamicIslandPill({
    required this.compact,
    this.horizontal = true,
    super.key,
  });

  /// True in the tablet status bar (narrow height); false in the desktop bar.
  final bool compact;
  final bool horizontal;

  @override
  ConsumerState<T3DynamicIslandPill> createState() =>
      _T3DynamicIslandPillState();
}

class _T3DynamicIslandPillState extends ConsumerState<T3DynamicIslandPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  bool _hovered = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _syncPulse(bool animate) {
    if (animate) {
      if (!_pulse.isAnimating) {
        _pulse.repeat(reverse: true);
      }
    } else if (_pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      shellSettingsProvider.select((s) => s.t3Code.enabled),
    );
    if (!enabled) return const SizedBox.shrink();

    final state = ref.watch(t3CodeControllerProvider);
    final controller = ref.read(t3CodeControllerProvider.notifier);
    final running = state.runningThreads;
    final hasUnread = state.unreadCompletedThreadIds.isNotEmpty;
    final primary = state.primaryThread;
    final activePulse = state.isVoiceActive || running.isNotEmpty;
    _syncPulse(activePulse);

    final accent = context.shellTheme.accentPalette.primary;
    final pillHeight = widget.compact ? 24.0 : 30.0;
    final maxWidth = widget.compact ? 270.0 : 360.0;

    // Determine pill mode:
    // 1. Active voice dictation (waveform + partial transcript + send/cancel)
    // 2. Notice / error banner
    // 3. Running thread(s) thinking bubble
    // 4. Unread completed thread bubble
    // 5. Idle compact trigger (mic + T3 badge in tablet; T3 hub chip in desktop
    //    when recent threads exist or connected).
    Widget inner;
    Color borderColor = const Color(0x33FFFFFF);
    VoidCallback onTap = controller.toggleExpanded;

    if (state.isVoiceActive) {
      borderColor = state.voicePhase == T3VoicePhase.recording
          ? const Color(0x99EF4444)
          : accent.withValues(alpha: 0.7);
      final label = switch (state.voicePhase) {
        T3VoicePhase.connecting => 'Подключение GigaAM...',
        T3VoicePhase.finishing => 'Распознавание...',
        T3VoicePhase.sending => 'Отправка в T3...',
        _ =>
          state.liveTranscript.isNotEmpty
              ? state.liveTranscript
              : 'Слушаю...',
      };
      onTap = () {
        if (state.voicePhase == T3VoicePhase.recording) {
          unawaited(controller.finishVoiceAndSend());
        }
      };
      inner = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, _) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  const Color(0xFFEF4444),
                  const Color(0xFFFCA5A5),
                  _pulse.value,
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          _MiniWaveform(
            bars: state.voiceWaveform,
            height: widget.compact ? 12 : 14,
            color: const Color(0xFFF87171),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.compact ? 11.5 : 12.5,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          if (state.voicePhase == T3VoicePhase.recording) ...[
            const SizedBox(width: 6),
            _PillMiniAction(
              icon: Icons.send_rounded,
              color: const Color(0xFF4ADE80),
              tooltip: 'Отправить',
              onTap: () => unawaited(controller.finishVoiceAndSend()),
            ),
            const SizedBox(width: 4),
            _PillMiniAction(
              icon: Icons.close_rounded,
              color: const Color(0xCCFFFFFF),
              tooltip: 'Отмена',
              onTap: () => unawaited(controller.cancelVoice()),
            ),
          ],
        ],
      );
    } else if (state.errorMessage != null || state.statusNotice != null) {
      final isErr = state.errorMessage != null;
      borderColor = isErr
          ? const Color(0x99F87171)
          : accent.withValues(alpha: 0.6);
      inner = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isErr ? Icons.error_outline_rounded : Icons.auto_awesome_rounded,
            size: 14,
            color: isErr ? const Color(0xFFF87171) : accent,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              state.errorMessage ?? state.statusNotice ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.compact ? 11.5 : 12,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      );
    } else if (running.isNotEmpty) {
      final lead = running.first;
      borderColor = accent.withValues(alpha: 0.65);
      final stepText =
          state.selectedThreadDetail?.threadId == lead.id &&
              (state.selectedThreadDetail?.activeStepSummary?.isNotEmpty ??
                  false)
          ? state.selectedThreadDetail!.activeStepSummary!
          : lead.title;
      inner = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, _) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  accent,
                  Colors.white,
                  _pulse.value * 0.65,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.45 + _pulse.value * 0.35),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              stepText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.compact ? 11.5 : 12.5,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          if (running.length > 1) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '+${running.length - 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ],
      );
    } else if (hasUnread && primary != null) {
      borderColor = const Color(0x994ADE80);
      inner = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 14,
            color: Color(0xFF4ADE80),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              primary.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.compact ? 11.5 : 12.5,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      );
    } else {
      // Idle state:
      // - In tablet status bar: compact Dynamic Island notch with Mic + T3 tap.
      // - In desktop top bar: subtle T3 threads pill when threads exist.
      if (!widget.compact && state.threads.isEmpty) {
        return const SizedBox.shrink();
      }
      inner = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillMiniAction(
            icon: Icons.mic_rounded,
            color: Colors.white.withValues(alpha: 0.9),
            tooltip: 'Голосовой запрос T3',
            onTap: () => unawaited(controller.toggleVoice()),
          ),
          if (state.threads.isNotEmpty) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.auto_awesome_rounded,
              size: 13,
              color: accent.withValues(alpha: 0.9),
            ),
            const SizedBox(width: 4),
            Text(
              'T3',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: widget.compact ? 11 : 12,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ],
      );
    }

    return MouseRegion(
      cursor: ShellMouseCursors.link,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: pillHeight,
          constraints: BoxConstraints(
            minWidth: widget.compact ? 42 : 68,
            maxWidth: maxWidth,
          ),
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 10 : 12),
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xF018181D)
                : const Color(0xE0111116),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 12,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Center(widthFactor: 1, child: inner),
        ),
      ),
    );
  }
}

class _PillMiniAction extends StatelessWidget {
  const _PillMiniAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}

class _MiniWaveform extends StatelessWidget {
  const _MiniWaveform({
    required this.bars,
    required this.height,
    required this.color,
  });

  final List<double> bars;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < bars.length; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 1.5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: 2.2,
                height: (bars[i].clamp(0.12, 1.0) * height),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Floating expanded Dynamic Island popover layer mounted above both the
/// desktop shell and the tablet shell. Shows live agent progress ("что он
/// делает"), formatted final answers when completed, a thread switcher for ALL
/// T3 Code threads (including those created inside T3 Code Desktop), and quick
/// voice/text follow-up controls.
class T3DynamicIslandOverlay extends ConsumerStatefulWidget {
  const T3DynamicIslandOverlay({super.key, this.mobile = false});

  final bool mobile;

  @override
  ConsumerState<T3DynamicIslandOverlay> createState() =>
      _T3DynamicIslandOverlayState();
}

class _T3DynamicIslandOverlayState
    extends ConsumerState<T3DynamicIslandOverlay> {
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocus = FocusNode(debugLabel: 't3-island-reply');
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _replyController.dispose();
    _replyFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendReply(String? threadId) {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    _replyController.clear();
    unawaited(
      ref
          .read(t3CodeControllerProvider.notifier)
          .sendTextPrompt(text, replyToThreadId: threadId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      shellSettingsProvider.select((s) => s.t3Code.enabled),
    );
    if (!enabled) return const SizedBox.shrink();

    final state = ref.watch(t3CodeControllerProvider);
    final showExpanded = state.expanded;
    if (!showExpanded) return const SizedBox.shrink();

    final controller = ref.read(t3CodeControllerProvider.notifier);
    final theme = context.shellTheme;
    final accent = theme.accentPalette.primary;
    final size = MediaQuery.sizeOf(context);
    final topPad = MediaQuery.paddingOf(context).top;
    final cardWidth = math.min(580.0, math.max(300.0, size.width - 32.0));
    final maxHeight = math.min(560.0, math.max(260.0, size.height * 0.64));
    final topOffset = widget.mobile ? (topPad + 38.0) : 52.0;

    final threads = state.islandThreads;
    final selected = state.primaryThread;
    final detail =
        (selected != null && state.selectedThreadDetail?.threadId == selected.id)
        ? state.selectedThreadDetail
        : null;

    return Positioned.fill(
      child: ShellInputRegion(
        debugLabel: 'T3 Dynamic Island',
        active: true,
        pointerPolicy: ShellPointerPolicy.fullScene,
        keyboardPolicy: ShellKeyboardPolicy.capture,
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              controller.collapse();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Click outside to collapse.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: controller.collapse,
                  child: const ColoredBox(color: Color(0x28000000)),
                ),
              ),
              Positioned(
                top: topOffset,
                left: (size.width - cardWidth) / 2,
                width: cardWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: ShellBackdropBlur(
                    blur: theme.effectivePanelOpacity < 1.0,
                    borderRadius: BorderRadius.circular(24),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xEB131318),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: selected?.isRunning == true
                              ? accent.withValues(alpha: 0.6)
                              : const Color(0x33FFFFFF),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x88000000),
                            blurRadius: 28,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header
                            _IslandHeader(
                              selected: selected,
                              connectionState: state.connectionState,
                              accent: accent,
                              onOpenInT3: () => unawaited(
                                controller.openInT3Code(threadId: selected?.id),
                              ),
                              onStop: selected?.isRunning == true
                                  ? () => unawaited(
                                      controller.stopThread(selected!.id),
                                    )
                                  : null,
                              onClose: controller.collapse,
                            ),

                            // Thread switcher strip (Denial + T3 UI threads)
                            if (threads.length > 1)
                              _IslandThreadStrip(
                                threads: threads,
                                selectedId: selected?.id,
                                unreadIds: state.unreadCompletedThreadIds,
                                accent: accent,
                                onSelect: controller.selectThread,
                              ),

                            const Divider(
                              height: 1,
                              color: Color(0x1FFFFFFF),
                            ),

                            // Body: live activity & response
                            Flexible(
                              child: _IslandBody(
                                state: state,
                                selected: selected,
                                detail: detail,
                                accent: accent,
                                scrollController: _scrollController,
                              ),
                            ),

                            const Divider(
                              height: 1,
                              color: Color(0x1FFFFFFF),
                            ),

                            // Footer: follow-up text input + voice buttons
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                10,
                                12,
                                12,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 38,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0x18FFFFFF),
                                        borderRadius: BorderRadius.circular(19),
                                        border: Border.all(
                                          color: const Color(0x22FFFFFF),
                                        ),
                                      ),
                                      alignment: Alignment.centerLeft,
                                      child: TextField(
                                        controller: _replyController,
                                        focusNode: _replyFocus,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13.5,
                                        ),
                                        cursorColor: accent,
                                        onSubmitted: (_) =>
                                            _sendReply(selected?.id),
                                        decoration: InputDecoration.collapsed(
                                          hintText: selected != null
                                              ? 'Ответить в этот тред...'
                                              : 'Спросить T3 Code (~)...',
                                          hintStyle: const TextStyle(
                                            color: Color(0x77FFFFFF),
                                            fontSize: 13.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _IslandFooterButton(
                                    icon: Icons.send_rounded,
                                    tooltip: 'Отправить',
                                    color: accent,
                                    onTap: () => _sendReply(selected?.id),
                                  ),
                                  const SizedBox(width: 6),
                                  _IslandFooterButton(
                                    icon: state.isVoiceActive
                                        ? Icons.stop_rounded
                                        : Icons.mic_rounded,
                                    tooltip: selected != null
                                        ? 'Ответить голосом'
                                        : 'Голосовой запрос',
                                    color: state.isVoiceActive
                                        ? const Color(0xFFEF4444)
                                        : const Color(0x26FFFFFF),
                                    onTap: () => unawaited(
                                      controller.toggleVoice(
                                        replyToThreadId: selected?.id,
                                      ),
                                    ),
                                  ),
                                  if (selected != null) ...[
                                    const SizedBox(width: 6),
                                    _IslandFooterButton(
                                      icon: Icons.add_comment_rounded,
                                      tooltip: 'Новый голосовой тред в ~',
                                      color: const Color(0x26FFFFFF),
                                      onTap: () => unawaited(
                                        controller.toggleVoice(),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IslandHeader extends StatelessWidget {
  const _IslandHeader({
    required this.selected,
    required this.connectionState,
    required this.accent,
    required this.onOpenInT3,
    required this.onStop,
    required this.onClose,
  });

  final T3ThreadSummary? selected;
  final T3ConnectionState connectionState;
  final Color accent;
  final VoidCallback onOpenInT3;
  final VoidCallback? onStop;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (selected?.status) {
      T3ThreadStatus.running ||
      T3ThreadStatus.starting ||
      T3ThreadStatus.preparing ||
      T3ThreadStatus.queued => accent,
      T3ThreadStatus.waiting => const Color(0xFFF59E0B),
      T3ThreadStatus.completed => const Color(0xFF4ADE80),
      T3ThreadStatus.failed => const Color(0xFFF87171),
      _ => const Color(0x88FFFFFF),
    };
    final subtitleParts = <String>[
      if (selected?.projectTitle != null && selected!.projectTitle!.isNotEmpty)
        selected!.projectTitle!,
      if (selected?.model != null && selected!.model!.isNotEmpty)
        selected!.model!,
      if (selected == null)
        switch (connectionState) {
          T3ConnectionState.connected => 'Подключено к T3 Code',
          T3ConnectionState.notInstalled => 'T3 Code не установлен',
          T3ConnectionState.serverStopped => 'T3 Code не запущен',
          T3ConnectionState.connecting => 'Подключение...',
          T3ConnectionState.error => 'Ошибка подключения',
        },
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected?.title ?? 'T3 Code',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitleParts.isNotEmpty)
                  Text(
                    subtitleParts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0x99FFFFFF),
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          if (onStop != null)
            IconButton(
              icon: const Icon(
                Icons.stop_circle_outlined,
                size: 19,
                color: Color(0xFFF87171),
              ),
              tooltip: 'Остановить',
              onPressed: onStop,
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            icon: const Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: Color(0xCCFFFFFF),
            ),
            tooltip: 'Открыть в T3 Code',
            onPressed: onOpenInT3,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 19,
              color: Color(0xAAFFFFFF),
            ),
            tooltip: 'Свернуть',
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _IslandThreadStrip extends StatelessWidget {
  const _IslandThreadStrip({
    required this.threads,
    required this.selectedId,
    required this.unreadIds,
    required this.accent,
    required this.onSelect,
  });

  final List<T3ThreadSummary> threads;
  final String? selectedId;
  final Set<String> unreadIds;
  final Color accent;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        itemCount: threads.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final thread = threads[index];
          final active = thread.id == selectedId;
          final unread = unreadIds.contains(thread.id);
          final dotColor = thread.isRunning
              ? accent
              : thread.status == T3ThreadStatus.failed
              ? const Color(0xFFF87171)
              : unread || thread.status == T3ThreadStatus.completed
              ? const Color(0xFF4ADE80)
              : const Color(0x66FFFFFF);
          return GestureDetector(
            onTap: () => onSelect(thread.id),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 168),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: active
                    ? accent.withValues(alpha: 0.25)
                    : const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active
                      ? accent.withValues(alpha: 0.65)
                      : const Color(0x1AFFFFFF),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      thread.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active
                            ? Colors.white
                            : const Color(0xCCFFFFFF),
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _IslandBody extends StatelessWidget {
  const _IslandBody({
    required this.state,
    required this.selected,
    required this.detail,
    required this.accent,
    required this.scrollController,
  });

  final T3IslandState state;
  final T3ThreadSummary? selected;
  final T3ThreadDetail? detail;
  final Color accent;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    if (selected == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          state.installed
              ? 'Нажмите на микрофон (или дважды Громкость−) или напишите запрос ниже — тред откроется в ~ и появится в T3 Code.'
              : 'T3 Code ещё не установлен. Откройте Настройки → T3 Code, чтобы установить его из EvilBorsch/t3code.',
          style: const TextStyle(
            color: Color(0xBBFFFFFF),
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
      );
    }

    final items = detail?.items ?? const <T3TurnActivity>[];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            if (selected!.isRunning) ...[
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                selected!.lastError ??
                    (selected!.isRunning
                        ? 'Агент работает над запросом...'
                        : 'Загрузка содержимого треда...'),
                style: TextStyle(
                  color: selected!.lastError != null
                      ? const Color(0xFFF87171)
                      : const Color(0xBBFFFFFF),
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Show the most recent turns (up to last 18 items so it stays snappy).
    final visibleItems = items.length > 18
        ? items.sublist(items.length - 18)
        : items;

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in visibleItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ActivityRow(item: item, accent: accent),
            ),
          if (selected!.isRunning)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      detail?.activeStepSummary ?? 'T3 Code думает...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (selected!.lastError != null)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0x28EF4444),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x66EF4444)),
              ),
              child: SelectableText(
                selected!.lastError!,
                style: const TextStyle(
                  color: Color(0xFFFCA5A5),
                  fontSize: 12.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, required this.accent});

  final T3TurnActivity item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    switch (item.kind) {
      case T3ActivityKind.user:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: SelectableText(
              item.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                height: 1.38,
              ),
            ),
          ),
        );

      case T3ActivityKind.assistant:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x12FFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x1AFFFFFF)),
          ),
          child: SelectableText(
            item.text,
            style: const TextStyle(
              color: Color(0xF0FFFFFF),
              fontSize: 13.5,
              height: 1.48,
            ),
          ),
        );

      case T3ActivityKind.tool:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x0DFFFFFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                item.streaming
                    ? Icons.pending_rounded
                    : Icons.terminal_rounded,
                size: 14,
                color: item.streaming ? accent : const Color(0x88FFFFFF),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title.isNotEmpty ? item.title : item.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xBBFFFFFF),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );

      case T3ActivityKind.reasoning:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.psychology_alt_rounded,
                size: 14,
                color: Color(0x77FFFFFF),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0x88FFFFFF),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        );

      case T3ActivityKind.notification:
        return Text(
          item.text,
          style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 12),
        );
    }
  }
}

class _IslandFooterButton extends StatelessWidget {
  const _IslandFooterButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}
