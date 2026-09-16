import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/realtime/socket_diagnostics.dart';

/// TEMPORARY diagnostic viewer for the driver-side Socket.IO problem — shows
/// the same log lines that already go to `adb logcat` under RT-SOCKET /
/// RT-DRIVER, but readable on-device without a USB/ADB connection. Reads
/// only from [SocketDiagLog]; does not open any socket or connection of its
/// own. Remove this screen (and its route + dashboard entry point) once the
/// underlying connection issue is diagnosed and fixed.
class SocketDiagnosticsScreen extends StatefulWidget {
  const SocketDiagnosticsScreen({super.key});

  @override
  State<SocketDiagnosticsScreen> createState() => _SocketDiagnosticsScreenState();
}

class _SocketDiagnosticsScreenState extends State<SocketDiagnosticsScreen> {
  final _scrollController = ScrollController();
  late final _sub = SocketDiagLog.instance.onChange.listen((_) {
    if (!mounted) return;
    setState(() {});
    // Auto-scroll to the newest line.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  });

  @override
  void dispose() {
    _sub.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: SocketDiagLog.instance.asText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copied to clipboard')),
    );
  }

  void _clear() {
    SocketDiagLog.instance.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lines = SocketDiagLog.instance.lines;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Socket diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy Logs',
            onPressed: _copy,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Clear Logs',
            onPressed: _clear,
          ),
        ],
      ),
      body: lines.isEmpty
          ? const Center(child: Text('No socket activity logged yet.'))
          : Container(
              color: Colors.black,
              width: double.infinity,
              child: Scrollbar(
                controller: _scrollController,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: lines.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      lines[i],
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
