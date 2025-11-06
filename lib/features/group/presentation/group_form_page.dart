import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/primary_app_bar.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';

class GroupFormPage extends StatefulWidget {
  static const String createRoute = '/create-group';
  static const String editRoute = 'edit';
  static const String editRouteName = 'editGroup';

  final Group? group;

  const GroupFormPage({super.key, this.group});

  @override
  State<GroupFormPage> createState() => _GroupFormPageState();
}

class _GroupFormPageState extends State<GroupFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final _groupRepository = getIt<GroupRepository>();
  final _authService = getIt<AuthService>();
  bool _isLoading = false;

  bool get _isEditing => widget.group != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group?.name ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _nameTextFormField(),
              const SizedBox(height: 24),
              _submitButton(),
              if (_isLoading) _loadingIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  PrimaryAppBar _buildAppBar() =>
      PrimaryAppBar(title: _isEditing ? 'Edit Group' : 'Create a New Group');

  TextFormField _nameTextFormField() => TextFormField(
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
  );

  ElevatedButton _submitButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _saveGroup,
      child: Text(_isEditing ? 'Update Group' : 'Create Group'),
    );
  }

  Future<void> _saveGroup() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      if (_isEditing) {
        await _updateGroup();
      } else {
        await _addGroup(_authService.currentUser!);
      }
      if (mounted) {
        _showSnackbarAndExit();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar(e);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateGroup() async {
    final updatedGroup = widget.group!.copyWith(
      name: _nameController.text.trim(),
    );
    await _groupRepository.update(updatedGroup.id!, updatedGroup);
  }

  Future<void> _addGroup(User user) async => await _groupRepository.add(
    Group(
      name: _nameController.text.trim(),
      ownerId: user.uid,
      members: [user.uid],
    ),
  );

  void _showSnackbarAndExit() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Group ${_isEditing ? 'updated' : 'created'}!')),
    );
    context.pop();
  }

  void _showErrorSnackbar(Object e) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Error saving group: $e')));

  Padding _loadingIndicator() => const Padding(
    padding: EdgeInsets.only(top: 16.0),
    child: Center(child: CircularProgressIndicator()),
  );

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
