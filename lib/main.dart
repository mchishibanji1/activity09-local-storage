import 'package:flutter/material.dart';

import 'database_helper.dart';

import 'folder_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final helper = DatabaseHelper();
  try {
    await helper.init();
  } catch (error, stackTrace) {
    debugPrint('Database initialization failed: $error\n$stackTrace');
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Could not open local storage. Restart the app and check the logs.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }

  runApp(DirectoryApp(helper: helper));
}

class DirectoryApp extends StatelessWidget {
  const DirectoryApp({super.key, required this.helper});

  final DatabaseHelper helper;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fall Festival Roster',
      theme: ThemeData(useMaterial3: true),
      home: RosterScreen(helper: helper),
    );
  }
}

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key, required this.helper});

  final DatabaseHelper helper;

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();

  List<Map<String, dynamic>> _rows = [];
  int _count = 0;
  bool _loading = true;
  bool _busy = false;
  String? _errorMessage;
  String? _feedbackMessage;

  int? _selectedId; // non-null when editing an existing row

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final rows = await widget.helper.queryAllRows();
      final count = await widget.helper.queryRowCount();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _count = count;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Read failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not read records: $error';
        _loading = false;
      });
    }
  }

  String? _validateName(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Name is required.';
    return null;
  }

  String? _validateAge(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return 'Age is required.';
    final parsed = int.tryParse(raw);
    if (parsed == null) return 'Age must be a whole number.';
    if (parsed < 0 || parsed > 130) return 'Age must be between 0 and 130.';
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _nameController.text.trim();
    final age = int.tryParse(_ageController.text.trim());
    if (age == null) return; // belt-and-suspenders; validator already caught it

    setState(() {
      _busy = true;
      _feedbackMessage = null;
    });

    try {
      if (_selectedId == null) {
        final id = await widget.helper.insert({
          DatabaseHelper.columnName: name,
          DatabaseHelper.columnAge: age,
        });
        _feedbackMessage = 'Inserted record #$id.';
      } else {
        final affected = await widget.helper.update({
          DatabaseHelper.columnId: _selectedId,
          DatabaseHelper.columnName: name,
          DatabaseHelper.columnAge: age,
        });
        if (affected == 1) {
          _feedbackMessage = 'Updated record #$_selectedId.';
        } else {
          _feedbackMessage =
              'Update affected 0 rows — record #$_selectedId no longer exists.';
        }
      }

      // Clear the form only after a successful write.
      _nameController.clear();
      _ageController.clear();
      _selectedId = null;

      // Refresh from the database.
      try {
        final rows = await widget.helper.queryAllRows();
        final count = await widget.helper.queryRowCount();
        if (!mounted) return;
        setState(() {
          _rows = rows;
          _count = count;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Saved, but refresh failed: $error';
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Write failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _feedbackMessage = null;
        _errorMessage = 'Write failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _startEdit(Map<String, dynamic> row) {
    if (_busy) return;
    setState(() {
      _selectedId = row[DatabaseHelper.columnId] as int;
      _nameController.text = row[DatabaseHelper.columnName] as String;
      _ageController.text = row[DatabaseHelper.columnAge].toString();
      _feedbackMessage = 'Editing record #$_selectedId.';
      _errorMessage = null;
    });
  }

  void _cancelEdit() {
    if (_busy) return;
    setState(() {
      _selectedId = null;
      _nameController.clear();
      _ageController.clear();
      _feedbackMessage = 'Edit cancelled.';
    });
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    if (_busy) return;
    final id = row[DatabaseHelper.columnId] as int;
    final name = row[DatabaseHelper.columnName] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete guest?'),
        content: Text('Delete record #$id ($name)? This cannot be undone.'),
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

    if (confirmed != true) {
      setState(() {
        _feedbackMessage = 'Deletion cancelled.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _feedbackMessage = null;
    });

    try {
      final deleted = await widget.helper.delete(id);
      if (deleted == 1) {
        _feedbackMessage = 'Deleted record #$id.';
        if (_selectedId == id) {
          _selectedId = null;
          _nameController.clear();
          _ageController.clear();
        }
      } else {
        _feedbackMessage =
            'Delete affected 0 rows — record #$id no longer exists.';
      }

      try {
        final rows = await widget.helper.queryAllRows();
        final count = await widget.helper.queryRowCount();
        if (!mounted) return;
        setState(() {
          _rows = rows;
          _count = count;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Deleted, but refresh failed: $error';
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Delete failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Delete failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Widget _buildForm() {
    final editing = _selectedId != null;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nameController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            validator: _validateName,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _ageController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Age (0–130)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            validator: _validateAge,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(editing ? 'Save changes' : 'Add guest'),
                ),
              ),
              if (editing) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _cancelEdit,
                    child: const Text('Cancel edit'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null && _rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No festival guests yet — add one above to get the party started!',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: _rows.map((row) {
        final id = row[DatabaseHelper.columnId] as int;
        final name = row[DatabaseHelper.columnName] as String;
        final age = row[DatabaseHelper.columnAge] as int;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            title: Text('ID $id — $name'),
            subtitle: Text('Age: $age'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  onPressed: _busy ? null : () => _startEdit(row),
                  icon: const Icon(Icons.edit),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: _busy ? null : () => _confirmDelete(row),
                  icon: const Icon(Icons.delete),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fall Festival Roster'),
        actions: [
          IconButton(
            tooltip: 'Folders',
            icon: const Icon(Icons.folder_special),
            onPressed: _busy
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FolderScreen(helper: widget.helper),
                      ),
                    );
                  },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildForm(),
              const Divider(height: 32),
              Text(
                'Records: $_count',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_feedbackMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _feedbackMessage!,
                  style: const TextStyle(color: Colors.green),
                ),
              ],
              if (_errorMessage != null && _rows.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 8),
              _buildList(),
            ],
          ),
        ),
      ),
    );
  }
}
