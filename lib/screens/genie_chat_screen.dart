import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../models/genie.dart';
import '../widgets/genie_app_bar.dart';
import 'book_list_screen.dart';
import 'add_book_screen.dart';

class GenieChatScreen extends StatefulWidget {
  const GenieChatScreen({super.key});

  @override
  State<GenieChatScreen> createState() => _GenieChatScreenState();
}

class _GenieMessage {
  final String text;
  final bool isUser;
  final List<GenieAction> actions;

  _GenieMessage({
    required this.text,
    required this.isUser,
    this.actions = const [],
  });
}

class _GenieChatScreenState extends State<GenieChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_GenieMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // specific initial greeting
    _messages.add(_GenieMessage(
      text: "Hello! I'm the Genie. You can ask me to add books or search your library.",
      isUser: false,
    ));
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add(_GenieMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await apiService.sendGenieChat(text);

      setState(() {
        _messages.add(_GenieMessage(
          text: response.text,
          isUser: false,
          actions: response.actions,
        ));
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(_GenieMessage(
          text: "Sorry, I had trouble talking to the spirits. Please try again.",
          isUser: false,
        ));
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleAction(GenieAction action) {
    if (action.actionType == 'SearchBook') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BookListScreen(initialSearchQuery: action.payload),
        ),
      );
    } else if (action.actionType == 'AddBook') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const AddBookScreen(), 
        ),
      );
    }
  }

  Widget _buildMessageBubble(_GenieMessage message) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? Colors.blueAccent : Colors.grey.shade200,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: isUser ? Colors.white : Colors.black87,
                fontSize: 16,
              ),
            ),
            if (message.actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: message.actions.map((action) {
                  return ActionChip(
                    label: Text(action.label),
                    onPressed: () => _handleAction(action),
                    backgroundColor: Colors.white,
                    elevation: 1,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GenieAppBar(title: 'The Genie'),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessageBubble(_messages[index]);
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                 BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  offset: const Offset(0, -2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Ask the Genie...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blueAccent),
                  onPressed: () => _sendMessage(_controller.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
