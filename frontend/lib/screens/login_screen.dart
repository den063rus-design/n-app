import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _storage = const FlutterSecureStorage();
  bool _obscurePassword = true;
  bool _saveCredentials = true;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Загружает сохранённые логин и пароль
  Future<void> _loadSavedCredentials() async {
    try {
      final savedLogin = await _storage.read(key: 'saved_login');
      final savedPassword = await _storage.read(key: 'saved_password');
      if (savedLogin != null && savedPassword != null) {
        _loginController.text = savedLogin;
        _passwordController.text = savedPassword;
      }
    } catch (e) {
      // Игнорируем ошибки чтения
    }
  }

  /// Сохраняет логин и пароль в SecureStorage
  Future<void> _persistCredentials(String login, String password) async {
    try {
      await _storage.write(key: 'saved_login', value: login);
      await _storage.write(key: 'saved_password', value: password);
    } catch (e) {
      // Игнорируем ошибки записи
    }
  }

  /// Удаляет сохранённые логин и пароль
  Future<void> _clearSavedCredentials() async {
    try {
      await _storage.delete(key: 'saved_login');
      await _storage.delete(key: 'saved_password');
    } catch (e) {
      // Игнорируем ошибки удаления
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final login = _loginController.text.trim();
    final password = _passwordController.text;

    final success = await authProvider.login(login, password);

    if (success && mounted) {
      // Сохраняем или удаляем credentials в зависимости от чекбокса
      if (_saveCredentials) {
        await _persistCredentials(login, password);
      } else {
        await _clearSavedCredentials();
      }

      final isAdmin = authProvider.isAdmin;
      Navigator.pushReplacementNamed(
        context,
        isAdmin ? '/admin' : '/user',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Natalie-Eng',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Войдите в систему',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _loginController,
                  decoration: const InputDecoration(
                    labelText: 'Логин',
                    prefixIcon: Icon(Icons.person),
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
                    labelText: 'Пароль',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Введите пароль';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                // Чекбокс "Запомнить логин и пароль"
                Row(
                  children: [
                    Checkbox(
                      value: _saveCredentials,
                      onChanged: (value) {
                        setState(() {
                          _saveCredentials = value ?? true;
                        });
                      },
                    ),
                    const Text('Запомнить логин и пароль'),
                  ],
                ),
                const SizedBox(height: 4),
                Consumer<AuthProvider>(
                  builder: (context, auth, _) {
                    if (auth.error != null) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          auth.error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const SizedBox(height: 16),
                Consumer<AuthProvider>(
                  builder: (context, auth, _) {
                    return ElevatedButton(
                      onPressed: auth.isLoading ? null : _handleLogin,
                      child: auth.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Войти'),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}