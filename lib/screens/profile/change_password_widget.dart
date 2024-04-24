import 'package:Contrib/globals/global_widgets.dart';
import 'package:Contrib/globals/snackbar.dart';
import 'package:Contrib/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:parse_server_sdk_flutter/parse_server_sdk_flutter.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ChangePasswordWidget extends StatefulWidget {
  const ChangePasswordWidget({
    super.key,
  });

  @override
  State<ChangePasswordWidget> createState() => _ChangePasswordWidgetState();
}

class _ChangePasswordWidgetState extends State<ChangePasswordWidget> {
  final _controllerNewPassword = TextEditingController();
  final _controllerConfirmPassword = TextEditingController();

  bool _isPasswordMatching = true; // Is confirmation and new password equal
  late UserProvider _userProvider;

  bool _isWidgetLocked = false;
  _lockWidget() => setState(() => _isWidgetLocked = true);
  _releaseWidget() => setState(() => _isWidgetLocked = false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _userProvider = UserProvider.of(context)!;
    _userProvider.user.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controllerNewPassword.dispose();
    _controllerConfirmPassword.dispose();
    super.dispose();
  }

  setPassword(String password) async {
    _lockWidget();
    ParseUser? user = _userProvider.user.getParseUser();

    if (user == null) {
      return Future.error(NoUserException());
    }

    user.set('password', password);

    ParseResponse response = await user.save();

    if (response.success) {
    } else if (response.error != null) {}
    _releaseWidget();
  }

  Future<void> changePasswordRequest(String password) async {
    ParseUser? user = _userProvider.user.getParseUser();
    if (user == null) {
      return Future.error("No user logged in.");
    }
    user.set('password', password);
    ParseResponse response = await user.save();

    if (!response.success) {
      return Future.error(response.error!.message);
    }
  }

  _changePassword() {
    if (_controllerNewPassword.text == _controllerConfirmPassword.text) {
      setState(() {
        _isPasswordMatching = true;
      });
      setPassword(_controllerNewPassword.text).then((_) {
        showSuccess(context,
            AppLocalizations.of(context)!.password_changed_successfully);
        Navigator.of(context).pop();
      });
    } else {
      setState(() {
        _isPasswordMatching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            H2("Change Password"),
            const SpaceH(),
            TextInputField(
              label: AppLocalizations.of(context)!.new_password,
              controller: _controllerNewPassword,
              isPasswordField: true,
            ),
            const SpaceH(),
            TextInputField(
              label: AppLocalizations.of(context)!.confirm_password,
              controller: _controllerConfirmPassword,
              isPasswordField: true,
            ),
            const SpaceHSmall(),
            if (!_isPasswordMatching)
              Text(
                AppLocalizations.of(context)!.passwords_unequal,
                style: const TextStyle(color: Colors.red),
              ),
            const SpaceH(),
            FilledButton(
              onPressed: _isWidgetLocked ? null : () => _changePassword(),
              child: _isWidgetLocked
                  ? const SmallProgressIndicator()
                  : Text(AppLocalizations.of(context)!.btn_confirm),
            ),
          ],
        ),
      ),
    );
  }
}
