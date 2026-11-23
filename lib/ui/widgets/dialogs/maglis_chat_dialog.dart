import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/app_state.dart';
import '../../../maglis/maglis_controller.dart';
import '../../../maglis/maglis_core.dart';
import 'dialog_base.dart';

/// Modern tactile Chat BottomSheet / Modal for participants in a Majlis session.
/// Sends real-time messages directly via WebRTC DataChannel without third-party servers.
class MaglisChatSheet extends StatefulWidget {
  const MaglisChatSheet({super.key});

  static Future<void> show(BuildContext context) {
    MaglisController.instance.markChatAsRead();
    final isWide = MediaQuery.sizeOf(context).width > 600;
    if (isWide) {
      return showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
            child: const MaglisChatSheet(),
          ),
        ),
      );
    }
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MaglisChatSheet(),
    );
  }

  @override
  State<MaglisChatSheet> createState() => _MaglisChatSheetState();
}

class _MaglisChatSheetState extends State<MaglisChatSheet> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    MaglisController.instance.markChatAsRead();
    _textCtrl.addListener(() {
      final hasText = _textCtrl.text.trim().isNotEmpty;
      if (hasText != _canSend) {
        setState(() => _canSend = hasText);
      }
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutQuad,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    MaglisController.instance.sendChatMessage(text);
    _textCtrl.clear();
    _scrollToBottom();
  }

  String _formatTimestamp(int ms, bool isAr) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final formatted = '$hour:$min';
    return isAr ? QuranTypography.toArabicDigits(formatted) : formatted;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
    final bool isDark = app.isDarkMode;
    final bool isAr = app.isArabic;
    final bool isId = app.isIndonesian;
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    final String title = isId
        ? 'Obrolan Majlis'
        : (isAr ? 'محادثة المجلس' : 'Majlis Chat');
    final String hintText = isId
        ? 'Tulis pesan...'
        : (isAr ? 'اكتب رسالة...' : 'Type a message...');
    final String emptyText = isId
        ? 'Belum ada pesan. Mulai obrolan dengan peserta lain!'
        : (isAr
            ? 'لا توجد رسائل بعد. ابدأ المحادثة مع المشاركين!'
            : 'No messages yet. Say hello to everyone!');

    return AnimatedBuilder(
      animation: MaglisController.instance,
      builder: (context, _) {
        final messages = MaglisController.instance.chatMessages;

        return Container(
          height: MediaQuery.sizeOf(context).height * 0.75,
          margin: EdgeInsets.only(bottom: bottomInset),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131922) : const Color(0xFFFAFBFD),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.08),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                blurRadius: 28,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            children: [
              // ── Header Handle & Title ──
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 8),
                child: Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.22)
                          : Colors.black.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: c.primary.withValues(alpha: isDark ? 0.20 : 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.forum_rounded,
                        size: 19,
                        color: c.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontFamily: 'cairo',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: c.text,
                            ),
                          ),
                          Text(
                            isId
                                ? '${MaglisController.instance.participantCount} peserta'
                                : (isAr
                                    ? '${QuranTypography.toArabicDigits(MaglisController.instance.participantCount)} مشاركين'
                                    : '${MaglisController.instance.participantCount} participants'),
                            style: TextStyle(
                              fontFamily: 'cairo',
                              fontSize: 11.5,
                              color: c.muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: c.muted,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.06),
                height: 1,
              ),

              // ── Messages List ──
              Expanded(
                child: messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 44,
                                color: c.muted.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                emptyText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'cairo',
                                  fontSize: 13,
                                  color: c.muted,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        itemCount: messages.length,
                        itemBuilder: (context, idx) {
                          final msg = messages[idx];
                          final isMe = msg.isLocal ||
                              msg.senderId ==
                                  MaglisController.instance.localPeerId;

                          return Align(
                            alignment:
                                isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * 0.76,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? c.primary
                                    : (isDark
                                        ? const Color(0xFF1F2937)
                                        : const Color(0xFFE2E8F0)),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isMe ? 16 : 3),
                                  bottomRight: Radius.circular(isMe ? 3 : 16),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: isDark ? 0.2 : 0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1.5),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (!isMe) ...[
                                    Text(
                                      msg.senderName,
                                      style: TextStyle(
                                        fontFamily: 'cairo',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? const Color(0xFF60A5FA)
                                            : const Color(0xFF2563EB),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                  ],
                                  Text(
                                    msg.text,
                                    style: TextStyle(
                                      fontFamily: 'cairo',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: isMe
                                          ? Colors.white
                                          : (isDark
                                              ? const Color(0xFFF1F5F9)
                                              : const Color(0xFF0F172A)),
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _formatTimestamp(msg.ts, isAr),
                                    style: TextStyle(
                                      fontFamily: 'cairo',
                                      fontSize: 9.5,
                                      color: isMe
                                          ? Colors.white.withValues(alpha: 0.75)
                                          : c.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // ── Input Bar ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF171E29)
                      : const Color(0xFFF1F5F9),
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                      width: 1,
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF212B3B)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : Colors.black.withValues(alpha: 0.10),
                            ),
                          ),
                          child: TextField(
                            controller: _textCtrl,
                            focusNode: _focusNode,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            style: TextStyle(
                              fontFamily: 'cairo',
                              fontSize: 14,
                              color: c.text,
                            ),
                            decoration: InputDecoration(
                              hintText: hintText,
                              hintStyle: TextStyle(
                                fontFamily: 'cairo',
                                fontSize: 13,
                                color: c.muted,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: _canSend
                              ? c.primary
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06)),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.send_rounded,
                            size: 19,
                            color: _canSend ? Colors.white : c.muted,
                          ),
                          onPressed: _canSend ? _sendMessage : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
