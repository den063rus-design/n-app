import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class EditUserScreen extends StatefulWidget {
  final User user;

  const EditUserScreen({super.key, required this.user});

  @override
  State<EditUserScreen> createState() => _EditUserScreenState();
}

class _EditUserScreenState extends State<EditUserScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _ageController;
  late final TextEditingController _notesController;
  late final TextEditingController _avatarController;
  final _apiService = ApiService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.user.fullName);
    _ageController = TextEditingController(
      text: widget.user.age?.toString() ?? '',
    );
    _notesController = TextEditingController(
      text: widget.user.notes ?? '',
    );
    _avatarController = TextEditingController(
      text: widget.user.avatarUrl ?? '',
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _ageController.dispose();
    _notesController.dispose();
    _avatarController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final data = <String, dynamic>{
        'fullName': _fullNameController.text.trim(),
      };

      final ageText = _ageController.text.trim();
      if (ageText.isNotEmpty) {
        data['age'] = int.tryParse(ageText);
      } else {
        data['age'] = null;
      }

      data['notes'] = _notesController.text.trim();
      data['avatarUrl'] = _avatarController.text.trim();

      await _apiService.updateUser(widget.user.id, data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Данные пользователя сохранены')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактирование данных'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: 'ФИО',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите ФИО';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ageController,
                decoration: const InputDecoration(
                  labelText: 'Возраст',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Заметки администратора',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _avatarController,
                decoration: const InputDecoration(
                  labelText: 'URL �������',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.image),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Сохранить данные',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


