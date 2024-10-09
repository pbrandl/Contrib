import 'package:Contrib/globals/global_widgets.dart';
import 'package:Contrib/globals/keypad.dart';
import 'package:Contrib/globals/pinpad.dart';
import 'package:Contrib/globals/snackbar.dart';
import 'package:Contrib/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parse_server_sdk_flutter/parse_server_sdk_flutter.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class UserList extends StatefulWidget {
  const UserList({super.key});

  @override
  State<UserList> createState() => _UserListState();
}

class _UserListState extends State<UserList> {
  late UserProvider userProvider;
  List<ParseUser> filteredUsers = [];
  TextEditingController searchController = TextEditingController();
  List<ParseUser> users = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    userProvider = UserProvider.of(context)!;
    userProvider.user.addListener(updateState);

    updateState();
  }

  void updateState() {
    setState(() {});
  }

  @override
  void dispose() {
    userProvider.user.removeListener(updateState);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    fetchUsers();
  }

  void filterUsers() {
    setState(() {
      filteredUsers = users
          .where((user) => (user.username ?? '')
              .toLowerCase()
              .startsWith(searchController.text.toLowerCase()))
          .toList();
    });
  }

  Future<void> fetchUsers() async {
    final query = QueryBuilder<ParseUser>(ParseUser.forQuery());

    query.setLimit(1000); // Adjust this value as needed
    query.orderByAscending('username');

    final response = await query.query();

    if (response.success && response.results != null) {
      setState(() {
        users = response.results!.cast<ParseUser>();
        users.sort((a, b) => ((a.username ?? '').toLowerCase())
            .compareTo((b.username ?? '').toLowerCase()));
        filteredUsers = users;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Mitglieder')),
        body: users.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: searchController,
                    onChanged: (value) => filterUsers(),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Suche',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = filteredUsers[index];
                      return ListTile(
                        onTap: () => showBottomSheet(
                          context: context,
                          builder: (BuildContext context) {
                            PinPadController padController = PinPadController();
                            return FractionallySizedBox(
                              heightFactor: 1,
                              child: Center(
                                child: SingleChildScrollView(
                                  child: SizedBox(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: <Widget>[
                                        const SizedBox(width: 700),
                                        const SpaceH(),
                                        const SpaceH(),
                                        const SpaceH(),
                                        H2("PIN"),
                                        const SpaceH(),
                                        SizedBox(
                                          width: 270,
                                          child: PinPad(padController),
                                        ),
                                        const SpaceH(),
                                        const SpaceH(),
                                        SizedBox(
                                          width: 270,
                                          child: FilledButton(
                                            onPressed: () async {
                                              // On log in
                                              if (userProvider.isLoggedIn()) {
                                                await userProvider.user
                                                    .logout();
                                              }
                                              await userProvider.user
                                                  .login(
                                                      user.username!,
                                                      padController
                                                          .numberString)
                                                  .then((success) {
                                                // Handle successful login
                                                GoRouter.of(context).pop();

                                                GoRouter.of(context).pushNamed(
                                                  'detail',
                                                  pathParameters: <String,
                                                      String>{
                                                    'id': 'DnvLyi470Q'
                                                  },
                                                );
                                              }).catchError((e) {
                                                // Handle login error
                                                showError(
                                                  context,
                                                  e.toString(),
                                                );
                                              });
                                            },
                                            child: Text(
                                              AppLocalizations.of(context)!
                                                  .btn_confirm,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        title: Text(user.username ?? 'No Username'),
                      );
                    },
                    separatorBuilder: (context, index) => Divider(),
                  ),
                ),
              ]));
  }
}
