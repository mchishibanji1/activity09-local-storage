import 'package:flutter/material.dart';

import 'database_helper.dart';

const List<String> kSuits = ['Hearts', 'Diamonds', 'Clubs', 'Spades'];

const Map<String, String> kSuitSymbols = {
  'Hearts': '♥',
  'Diamonds': '♦',
  'Clubs': '♣',
  'Spades': '♠',
};

class CardScreen extends StatefulWidget {
  const CardScreen({super.key, required this.helper, required this.folder});

  final DatabaseHelper helper;
  final Folder folder;

  @override
  State<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends State<CardScreen> {
  List<CardRecord> _cards = [];
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
      final cards = await widget.helper.getCards(widget.folder.id!);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Load cards failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load cards: $error';
        _loading = false;
      });
    }
  }

  Future<void> _openForm({CardRecord? existing}) async {
    final result = await showModalBottomSheet<CardRecord>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _CardFormSheet(folderId: widget.folder.id!, existing: existing),
    );
    if (result == null) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      if (result.id == null) {
        final id = await widget.helper.insertCard(result);
        debugPrint(
          'Inserted card #$id "${result.title}" into folder ${widget.folder.id}',
        );
      } else {
        final affected = await widget.helper.updateCard(result);
        debugPrint('Updated card #${result.id} -> affected $affected row(s)');
      }
      await _load();
    } catch (error, stackTrace) {
      debugPrint('Save card failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not save card: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _confirmDelete(CardRecord card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete card?'),
        content: Text('Delete "${card.title}"? This cannot be undone.'),
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
      final deleted = await widget.helper.deleteCard(card.id!);
      debugPrint('Deleted card #${card.id} -> affected $deleted row(s)');
      await _load();
    } catch (error, stackTrace) {
      debugPrint('Delete card failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not delete card: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _cards.isEmpty) {
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
    if (_cards.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No cards in this folder yet — tap + to add one.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _cards.length,
      itemBuilder: (context, index) {
        final card = _cards[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            leading: _SuitBadge(suit: card.suit),
            title: Text(card.title),
            subtitle: Text(
              card.notes.isEmpty ? card.suit : '${card.suit} — ${card.notes}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  onPressed: _busy ? null : () => _openForm(existing: card),
                  icon: const Icon(Icons.edit),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: _busy ? null : () => _confirmDelete(card),
                  icon: const Icon(Icons.delete),
                ),
              ],
            ),
            onTap: _busy ? null : () => _openForm(existing: card),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.folder.name)),
      floatingActionButton: FloatingActionButton(
        onPressed: _busy ? null : () => _openForm(),
        tooltip: 'Add card',
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_errorMessage != null && _cards.isNotEmpty)
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

class _SuitBadge extends StatelessWidget {
  const _SuitBadge({required this.suit});

  final String suit;

  @override
  Widget build(BuildContext context) {
    final symbol = kSuitSymbols[suit] ?? '?';
    return Container(
      width: 44,
      height: 56,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      alignment: Alignment.center,
      child: Text(
        symbol,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _CardFormSheet extends StatefulWidget {
  const _CardFormSheet({required this.folderId, this.existing});

  final int folderId;
  final CardRecord? existing;

  @override
  State<_CardFormSheet> createState() => _CardFormSheetState();
}

class _CardFormSheetState extends State<_CardFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _imageRefController;
  late String _suit;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _imageRefController = TextEditingController(text: existing?.imageRef ?? '');
    _suit = existing?.suit ?? kSuits.first;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _imageRefController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final imageRef = _imageRefController.text.trim();
    final record = CardRecord(
      id: widget.existing?.id,
      title: _titleController.text.trim(),
      suit: _suit,
      notes: _notesController.text.trim(),
      imageRef: imageRef.isEmpty ? null : imageRef,
      folderId: widget.folderId,
    );
    Navigator.of(context).pop(record);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEditing ? 'Edit card' : 'New card',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final trimmed = (value ?? '').trim();
                if (trimmed.isEmpty) return 'Title is required.';
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _suit,
              decoration: const InputDecoration(
                labelText: 'Suit',
                border: OutlineInputBorder(),
              ),
              items: kSuits
                  .map(
                    (suit) => DropdownMenuItem(
                      value: suit,
                      child: Text('${kSuitSymbols[suit]}  $suit'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _suit = value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _imageRefController,
              decoration: const InputDecoration(
                labelText: 'Image reference (optional)',
                hintText: 'Asset path, file path, or URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: Text(isEditing ? 'Save' : 'Create'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
