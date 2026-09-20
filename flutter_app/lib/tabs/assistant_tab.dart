import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../models/app_models.dart';
import '../theme/app_theme.dart';

class AssistantTab extends StatefulWidget {
  const AssistantTab({super.key});

  @override
  State<AssistantTab> createState() => _AssistantTabState();
}

class _AssistantTabState extends State<AssistantTab> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<String> _quickChips = [
    'Explain Fail-Safe Mode',
    'Portfolio Risk Stress Test',
    'Analyze Social Panic',
  ];

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSend(QuizProvider provider) {
    final query = _textController.text.trim();
    if (query.isNotEmpty) {
      provider.sendAssistantMessage(query);
      _textController.clear();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<QuizProvider>();
    final isDark = quizProvider.isDarkMode;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;
    final List<AssistantMessage> messages = quizProvider.messages;

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            itemCount:
                messages.length + (quizProvider.isLoadingAssistant ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == messages.length && quizProvider.isLoadingAssistant) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurface : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.emerald,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Thinking...',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.white38
                              : AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final msg = messages[index];
              final isUser = msg.isUser;

              return Padding(
                padding: const EdgeInsets.only(bottom: 14.0),
                child: Row(
                  mainAxisAlignment: isUser
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isUser) ...[
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurface : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white12
                                : AppColors.lightBorder,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          AppIcons.bot,
                          color: AppColors.emerald,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isUser
                              ? (isDark
                                    ? AppColors.emerald.withOpacity(0.2)
                                    : AppColors.emerald.withOpacity(0.15))
                              : (isDark
                                    ? AppColors.darkSurface.withOpacity(0.5)
                                    : Colors.white),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isUser ? 20 : 4),
                            bottomRight: Radius.circular(isUser ? 4 : 20),
                          ),
                          border: Border.all(
                            color: isUser
                                ? AppColors.emerald.withOpacity(0.4)
                                : (isDark
                                      ? Colors.white12
                                      : AppColors.lightBorder),
                            width: 2,
                          ),
                        ),
                        child: Text(
                          msg.content,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.5,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        // Chips and Query Input
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _quickChips
                      .map(
                        (chip) => Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ActionChip(
                            label: Text(
                              chip,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: isDark
                                    ? Colors.white70
                                    : AppColors.lightTextPrimary,
                              ),
                            ),
                            backgroundColor: isDark
                                ? AppColors.darkSurface
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: isDark
                                    ? Colors.white12
                                    : AppColors.lightBorder,
                              ),
                            ),
                            onPressed: () {
                              _textController.text = chip;
                              _handleSend(quizProvider);
                            },
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.white12 : AppColors.lightBorder,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      AppIcons.plus,
                      size: 18,
                      color: AppColors.lightTextMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        onSubmitted: (_) => _handleSend(quizProvider),
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Message assistant...',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white30
                                : AppColors.lightTextMuted,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        AppIcons.send,
                        color: AppColors.emerald,
                        size: 18,
                      ),
                      onPressed: () => _handleSend(quizProvider),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
