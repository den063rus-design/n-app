import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';

class CreateUserScreen extends StatefulWidget {
  const CreateUserScreen({super.key});

  @override
  State<CreateUserScreen> createState() => _CreateUserScreenState();
}

class _CreateUserScreenState extends State<CreateUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _ageController = TextEditingController();
  final _notesController = TextEditingController();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _fullNameController.dispose();
    _ageController.dispose();
    _notesController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final data = <String, dynamic>{
        'fio': _fullNameController.text.trim(),
        'login': _loginController.text.trim(),
        'password': _passwordController.text,
      };

      final ageText = _ageController.text.trim();
      if (ageText.isNotEmpty) {
        data['age'] = int.tryParse(ageText) ?? 0;
      } else {
        data['age'] = 0;
      }

      final notesText = _notesController.text.trim();
      if (notesText.isNotEmpty) {
        data['notes'] = notesText;
      }

      await _apiService.createUser(data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пользователь успешно создан')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      String errorMessage = 'Ошибка создания пользователя';
      if (e is DioException && e.response?.data != null) {
        try {
          final body = e.response!.data;
          if (body is Map && body['message'] != null) {
            final msg = body['message'];
            if (msg is List) {
              errorMessage = msg.join('\n');
            } else {
              errorMessage = msg.toString();
            }
          }
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5),
          ),
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
        title: const Text('Создание пользователя'),
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
                  labelText: 'ФИО *',
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
              const SizedBox(height: 16),
              TextFormField(
                controller: _loginController,
                decoration: const InputDecoration(
                  labelText: 'Логин *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.login),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите логин';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Пароль *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Введите пароль';
                  }
                  if (value.length < 6) {
                    return 'Пароль должен быть не менее 6 символов';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _createUser,
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
                        'Создать пользователя',
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
