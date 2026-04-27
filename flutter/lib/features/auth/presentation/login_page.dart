import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_endpoint_store.dart';
import '../../../core/network/api_client.dart';
import '../domain/login_user_option.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  static const _fallbackLoginUsers = <LoginUserOption>[
    LoginUserOption(username: 'admin', role: 'admin'),
  ];

  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  late Future<List<LoginUserOption>> _loginUsersFuture;
  String _selectedUsername = '';
  String _apiBaseUrl = '';

  @override
  void initState() {
    super.initState();
    _loginUsersFuture = ref.read(authRepositoryProvider).fetchLoginUsers();
    _apiBaseUrl = ref.read(apiBaseUrlProvider);
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _openVirtualKeyboard({
    required TextEditingController controller,
    required String title,
    TextInputType keyboardType = TextInputType.text,
    bool obscurePreview = false,
  }) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _VirtualKeyboardDialog(
        title: title,
        initialValue: controller.text,
        keyboardType: keyboardType,
        obscurePreview: obscurePreview,
      ),
    );

    if (result == null) return;
    controller
      ..text = result
      ..selection = TextSelection.collapsed(offset: result.length);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    await ref
        .read(authControllerProvider.notifier)
        .signIn(
          username: _selectedUsername,
          password: _passwordController.text,
        );
  }

  Future<void> _openServerSettings() async {
    final controller = TextEditingController(text: _apiBaseUrl);
    final formKey = GlobalKey<FormState>();
    String localError = '';
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF17284B),
              title: const Text('Server sozlamalari'),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Backend API manzilini kiriting',
                        style: TextStyle(
                          color: Color(0xFF9FB5DA),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: controller,
                        readOnly: true,
                        onTap: () => _openVirtualKeyboard(
                          controller: controller,
                          title: 'Server URL',
                          keyboardType: TextInputType.url,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Server URL',
                          hintText: 'http://192.168.0.237:4000/api',
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) {
                            return 'Server URL kiriting';
                          }
                          final normalized = ApiEndpointStore.normalize(text);
                          final uri = Uri.tryParse(normalized);
                          if (uri == null ||
                              !uri.hasScheme ||
                              uri.host.trim().isEmpty) {
                            return 'To‘g‘ri URL kiriting';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Masalan: http://192.168.0.237:4000/api',
                        style: const TextStyle(
                          color: Color(0xFF7F96BF),
                          fontSize: 12.5,
                        ),
                      ),
                      if (localError.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          localError,
                          style: const TextStyle(
                            color: Color(0xFFFF8A8A),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Bekor qilish'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setLocalState(() {
                            saving = true;
                            localError = '';
                          });
                          try {
                            final normalized = ApiEndpointStore.normalize(
                              controller.text,
                            );
                            await ApiEndpointStore.saveBaseUrl(normalized);
                            ref.read(apiBaseUrlProvider.notifier).state =
                                normalized;
                            if (!mounted) return;
                            setState(() {
                              _apiBaseUrl = normalized;
                              _loginUsersFuture = ref
                                  .read(authRepositoryProvider)
                                  .fetchLoginUsers();
                            });
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                          } catch (error) {
                            setLocalState(() {
                              localError = error.toString().replaceFirst(
                                'Exception: ',
                                '',
                              );
                              saving = false;
                            });
                          }
                        },
                  child: Text(saving ? 'Saqlanmoqda...' : 'Saqlash'),
                ),
              ],
            );
          },
        );
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 200));
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);
    final error = authState.hasError
        ? controller.formatError(authState.error!)
        : null;
    final isLoading = authState.isLoading;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: FutureBuilder<List<LoginUserOption>>(
                future: _loginUsersFuture,
                builder: (context, snapshot) {
                  final loginUsers =
                      (snapshot.data == null || snapshot.data!.isEmpty)
                      ? _fallbackLoginUsers
                      : snapshot.data!;
                  final hasUsers = loginUsers.isNotEmpty;

                  if (hasUsers &&
                      !loginUsers.any(
                        (user) => user.username == _selectedUsername,
                      )) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        _selectedUsername = loginUsers.first.username;
                      });
                    });
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: FilledButton.tonal(
                              onPressed: _openServerSettings,
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Icon(Icons.settings_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _LoginCard(
                          formKey: _formKey,
                          loginUsers: loginUsers,
                          selectedUsername: _selectedUsername,
                          onUsernameChanged: (value) {
                            setState(() {
                              _selectedUsername = value;
                            });
                          },
                          passwordController: _passwordController,
                          apiBaseUrl: _apiBaseUrl,
                          error: snapshot.hasError
                              ? 'Foydalanuvchilar ro‘yxatini olib bo‘lmadi. Default kirish: admin / 0000'
                              : error,
                          isLoading:
                              isLoading ||
                              snapshot.connectionState == ConnectionState.waiting,
                          onSubmit: _submit,
                          onOpenPasswordKeyboard: () => _openVirtualKeyboard(
                            controller: _passwordController,
                            title: 'Parol',
                            obscurePreview: true,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.loginUsers,
    required this.selectedUsername,
    required this.onUsernameChanged,
    required this.passwordController,
    required this.apiBaseUrl,
    required this.error,
    required this.isLoading,
    required this.onSubmit,
    required this.onOpenPasswordKeyboard,
  });

  final GlobalKey<FormState> formKey;
  final List<LoginUserOption> loginUsers;
  final String selectedUsername;
  final ValueChanged<String> onUsernameChanged;
  final TextEditingController passwordController;
  final String apiBaseUrl;
  final String? error;
  final bool isLoading;
  final Future<void> Function() onSubmit;
  final VoidCallback onOpenPasswordKeyboard;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kirish', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 10),
              Text(
                'Foydalanuvchini tanlang va parolni kiriting.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Server: $apiBaseUrl',
                style: const TextStyle(
                  color: Color(0xFF8FA8D7),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                initialValue:
                    loginUsers.any((user) => user.username == selectedUsername)
                    ? selectedUsername
                    : null,
                decoration: const InputDecoration(labelText: 'Foydalanuvchi'),
                items: loginUsers
                    .map(
                      (user) => DropdownMenuItem(
                        value: user.username,
                        child: Text(user.displayLabel),
                      ),
                    )
                    .toList(),
                onChanged: isLoading
                    ? null
                    : (value) {
                        if (value != null) onUsernameChanged(value);
                      },
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Foydalanuvchini tanlang'
                    : null,
                hint: const Text('Foydalanuvchini tanlang'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                readOnly: true,
                onTap: onOpenPasswordKeyboard,
                decoration: const InputDecoration(labelText: 'Parol'),
                validator: (value) =>
                    (value == null || value.isEmpty) ? 'Parol kiriting' : null,
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Text(
                  error!,
                  style: const TextStyle(
                    color: Color(0xFFFF8A8A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isLoading ? null : onSubmit,
                child: Text(isLoading ? 'Kirilmoqda...' : 'Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VirtualKeyboardDialog extends StatefulWidget {
  const _VirtualKeyboardDialog({
    required this.title,
    required this.initialValue,
    required this.keyboardType,
    this.obscurePreview = false,
  });

  final String title;
  final String initialValue;
  final TextInputType keyboardType;
  final bool obscurePreview;

  @override
  State<_VirtualKeyboardDialog> createState() => _VirtualKeyboardDialogState();
}

class _VirtualKeyboardDialogState extends State<_VirtualKeyboardDialog> {
  late final TextEditingController _controller;

  bool get _isNumeric =>
      widget.keyboardType == TextInputType.number ||
      widget.keyboardType == TextInputType.phone;

  static const _alphaRows = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm', '-', '.', ':', '@', '/'],
  ];

  static const _numericRows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['0', '00', '.'],
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _append(String value) {
    setState(() {
      _controller.text += value;
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  void _backspace() {
    if (_controller.text.isEmpty) return;
    setState(() {
      _controller.text =
          _controller.text.substring(0, _controller.text.length - 1);
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _isNumeric ? _numericRows : _alphaRows;
    final width = _isNumeric ? 420.0 : 780.0;

    return AlertDialog(
      backgroundColor: const Color(0xFF17284B),
      title: Text(widget.title),
      content: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1D39),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF355386)),
              ),
              child: Text(
                widget.obscurePreview
                    ? ('*' * _controller.text.length)
                    : (_controller.text.isEmpty
                          ? 'Matn kiriting...'
                          : _controller.text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _controller.text.isEmpty
                      ? const Color(0xFF7F96BF)
                      : Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (final row in rows) ...[
              Row(
                children: [
                  for (var i = 0; i < row.length; i++) ...[
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i == row.length - 1 ? 0 : 8),
                        child: _KeyboardKey(
                          label: row[i],
                          onTap: () => _append(row[i]),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _KeyboardKey(
                    label: 'Bo‘sh joy',
                    onTap: () => _append(' '),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _KeyboardKey(
                    label: 'Tozalash',
                    onTap: () {
                      setState(() {
                        _controller.clear();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _KeyboardKey(
                    label: 'O‘chirish',
                    onTap: _backspace,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Bekor'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Tayyor'),
        ),
      ],
    );
  }
}

class _KeyboardKey extends StatelessWidget {
  const _KeyboardKey({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}
