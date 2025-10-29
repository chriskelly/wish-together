import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/primary_app_bar.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';

class GroupFormPage extends StatefulWidget {
  final Group? group;

  const GroupFormPage({super.key, this.group});

  @override
  State<GroupFormPage> createState() => _GroupFormPageState();
}

class _GroupFormPageState extends State<GroupFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final _groupRepository = GroupRepository();
  bool _isLoading = false;

  bool get _isEditing => widget.group != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveGroup() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = auth.FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('You must be logged in to perform this action.');
      }

      if (_isEditing) {
        final updatedGroup = widget.group!.copyWith(
          name: _nameController.text.trim(),
        );
        await _groupRepository.update(updatedGroup.id!, updatedGroup);
      } else {
        await _groupRepository.add(
          Group(
            name: _nameController.text.trim(),
            ownerId: user.uid,
            members: [user.uid],
          ),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Group ${_isEditing ? 'updated' : 'created'}!'),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving group: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PrimaryAppBar(
        title: _isEditing ? 'Edit Group' : 'Create a New Group',
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Group Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a group name.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveGroup,
                child: Text(_isEditing ? 'Update Group' : 'Create Group'),
              ),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 16.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
