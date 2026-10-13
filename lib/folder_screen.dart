import 'package:flutter/material.dart';

import 'card_screen.dart';
import 'database_helper.dart';

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key, required this.helper});

  final DatabaseHelper helper;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  List<FolderWithCount> _folders = [];
  bool _loading = true;
  bool _busy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final folders = await widget.helper.getFoldersWithCounts();
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Load folders failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load folders: $error';
        _loading = false;
      });
    }
  }

  Future<void> _addFolder() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Folder name',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final trimmed = (value ?? '').trim();
              if (trimmed.isEmpty) return 'Folder name is required.';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(controller.text.trim());
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final now = DateTime.now().toIso8601String();
      final id = await widget.helper.insertFolder(
        Folder(name: name, createdAt: now),
      );
      debugPrint('Inserted folder #$id "$name"');
      await _load();
    } catch (error, stackTrace) {
      debugPrint('Insert folder failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not create folder: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _confirmDelete(Folder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete folder?'),
        content: Text(
          'Delete "${folder.name}" and all of its cards? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final deleted = await widget.helper.deleteFolder(folder.id!);
      debugPrint('Deleted folder #${folder.id} -> affected $deleted row(s)');
      await _load();
    } catch (error, stackTrace) {
      debugPrint('Delete folder failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not delete folder: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _openFolder(Folder folder) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CardScreen(helper: widget.helper, folder: folder),
      ),
    );
    // Refresh counts when returning from the card screen.
    _load();
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _folders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_folders.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No folders yet — tap + to create one.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _folders.length,
      itemBuilder: (context, index) {
        final entry = _folders[index];
        final folder = entry.folder;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            title: Text(folder.name),
            subtitle: Text('${entry.cardCount} cards'),
            trailing: IconButton(
              tooltip: 'Delete folder',
              onPressed: _busy ? null : () => _confirmDelete(folder),
              icon: const Icon(Icons.delete),
            ),
            onTap: _busy ? null : () => _openFolder(folder),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Folders')),
      floatingActionButton: FloatingActionButton(
        onPressed: _busy ? null : _addFolder,
        tooltip: 'Add folder',
        child: const Icon(Icons.create_new_folder),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_errorMessage != null && _folders.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }
}
