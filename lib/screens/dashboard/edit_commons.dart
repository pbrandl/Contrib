import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:Contrib/globals/categories.dart';
import 'package:Contrib/globals/global_styles.dart';
import 'package:Contrib/globals/global_widgets.dart';
import 'package:Contrib/globals/snackbar.dart';
import 'package:Contrib/providers/user_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:parse_server_sdk_flutter/parse_server_sdk_flutter.dart';

/// This widget edits an common ParseObject if provided. If [common] is null
/// it will initialize an empty ParseObject, and in both cases save after editing.
class EditCommonsDialog extends StatefulWidget {
  final ParseObject? common;

  const EditCommonsDialog({
    super.key,
    this.common,
  });

  @override
  State<EditCommonsDialog> createState() => _EditCommonsDialogState();
}

class _EditCommonsDialogState extends State<EditCommonsDialog> {
  late UserProvider userProvider; // Provides the current user to the widget
  bool isLoading = true; // Indicates loading request, disables widgets

  late ParseObject _editCommons;
  late ParseObject _commonDetails; // Holds lat, lng, website, description

  /// Form variables to create a new common
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descrController = TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();
  final TextEditingController _websiteController = TextEditingController();

  Uint8List? _selectedCommonLogo; // Stores the provided local logo
  bool logoIsValid = true;

  // Initialize variables for category selection
  String? _selectedCategory = 'Other';
  bool categoryIsValid = true;

  @override
  void initState() {
    super.initState();
    _editCommons = widget.common ?? ParseObject('Commons');
    initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    userProvider = UserProvider.of(context)!;
    userProvider.user.addListener(updateState);
  }

  void updateState() {
    if (mounted) {
      setState(() {});
    } else {
      showError(context, "An error occured. Please reload the page.");
    }
  }

  @override
  void dispose() {
    userProvider.user.removeListener(updateState);
    super.dispose();
  }

  void initialize() {
    fetchDetails().then((commonDetails) {
      setState(() {
        _commonDetails = commonDetails;
        _selectedCategory = _editCommons['domain'] ?? "Other";
        _nameController.text = _editCommons['name'] ?? "";
        _descrController.text = commonDetails['description'] ?? "";
        _websiteController.text = commonDetails['websiteUrl'] ?? "";
        _latController.text =
            commonDetails['location']?.latitude.toString() ?? "";
        _lngController.text =
            commonDetails['location']?.longitude.toString() ?? "";
        isLoading = false;
      });
    }).catchError((error) {
      setState(() {
        isLoading = false;
      });
      showError(context,
          AppLocalizations.of(context)!.arbitrary_error(error.toString()));
    });
  }

  /// Fetch details if Commons is not null. Else return an empty Commons Object.
  Future fetchDetails() async {
    if (widget.common == null) {
      return ParseObject('CommonDetails');
    }

    final QueryBuilder<ParseObject> query =
        QueryBuilder<ParseObject>(ParseObject('CommonDetails'))
          ..whereEqualTo('commonId', widget.common!.toPointer());

    final ParseResponse apiResponse = await query.query();

    if (apiResponse.success && apiResponse.results != null) {
      return apiResponse.results!.first as ParseObject;
    } else {
      return Future.error(apiResponse.error!.message);
    }
  }

  /// Open the browser and select a logo to upload to server.
  /// Only logos with specified height and width are allowed
  Future _pickImageFromGallery() async {
    final XFile? returnedLogo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxHeight: 50,
      maxWidth: 50,
    );

    if (returnedLogo == null) return;

    // Must be an image file and less than 50 x 50 pixels.
    if (await checkLogo(returnedLogo)) {
      final Uint8List imageBytes = await returnedLogo.readAsBytes();
      setState(() {
        _selectedCommonLogo = imageBytes;
        logoIsValid = true;
      });
    } else {
      setState(() {
        _selectedCommonLogo = null;
        logoIsValid = false;
      });
    }
  }

  // Constraints for the logo are checked. Must be an image file and less than 50 x 50 pixels.
  checkLogo(XFile logo) async {
    final pickedImage = img.decodeImage(await logo.readAsBytes());

    return !(logo.path.toLowerCase().endsWith('.png') ||
        pickedImage == null ||
        pickedImage.width >= 50 ||
        pickedImage.height >= 50);
  }

  // Adds the new commons to the database.
  Future<String> editCommon() async {
    // Set widget state to loading
    setState(() {
      isLoading = true;
    });

    ParseUser? user = userProvider.user.getParseUser();

    if (user == null) {
      return Future.error(NoUserException().toString());
    }

    ParseACL acl = ParseACL(owner: user)
      ..setPublicReadAccess(allowed: true)
      ..setPublicWriteAccess(allowed: false);

    // Set Name
    _editCommons
      ..set('name', _nameController.text)
      ..set('domain', _selectedCategory)
      ..set('admin', user.toPointer())
      ..setACL(acl);
    ;

    // Set logo
    if (_selectedCommonLogo != null) {
      _editCommons.set(
        'logo',
        ParseWebFile(_selectedCommonLogo!, name: 'logo.png'),
      );
    }

    final responseCommon = await _editCommons.save();

    if (responseCommon.success) {
      // Set Details
      _commonDetails
        ..set('description', _descrController.text)
        ..set('websiteUrl', _websiteController.text)
        ..set('commonId', _editCommons.toPointer());

      ParseGeoPoint? geoPoint;
      if (_latController.text != "" && _lngController.text != "") {
        geoPoint = ParseGeoPoint(
          latitude: double.parse(_latController.text),
          longitude: double.parse(_lngController.text),
        );
      }
      _commonDetails.set('location', geoPoint);
      _commonDetails.setACL(acl);

      final responseDetails = await _commonDetails.save();

      if (!responseDetails.success) {
        setState(() {
          isLoading = false;
        });
        return Future.error('${responseDetails.error?.message}');
      }
    } else {
      return Future.error('${responseCommon.error?.message}');
    }

    return responseCommon.result.objectId;
  }

  Widget logoUploadWidget() => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              _selectedCommonLogo == null
                  ? _editCommons['logo'] == null
                      ? CommonAvatar(
                          commonName: _editCommons['name']?[0] ?? 'Logo')
                      : CommonLogo(url: _editCommons['logo']['url'])
                  : Image.memory(
                      _selectedCommonLogo!,
                      width: 42,
                      height: 42,
                      color: isLoading ? Colors.grey.withOpacity(0.5) : null,
                    ),
              const SizedBox(width: 16),
              // Upload a logo
              Expanded(
                child: FilledButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          _pickImageFromGallery();
                        },
                  child: Text('Upload'),
                ),
              ),
              const SizedBox(width: 16),
              // Delete the logo
              Expanded(
                child: FilledButton(
                  onPressed: isLoading
                      ? null
                      : () => setState(() {
                            _selectedCommonLogo = null;
                            _editCommons['logo'] = null;
                          }),
                  child: Text(AppLocalizations.of(context)!.delete),
                ),
              ),
            ],
          ),
          if (!logoIsValid)
            Text(
              AppLocalizations.of(context)!.logo_size,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.red,
              ),
            ),
        ],
      );

  Widget categoryDropdown(double width) {
    final Map<String, String> categories = getCategoryTranslations(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownMenu<String>(
          width: width,
          enabled: !isLoading,
          hintText: AppLocalizations.of(context)!.select_category,
          textStyle: TextStyle(color: isLoading ? Colors.grey : null),
          label: Text(AppLocalizations.of(context)!.category),
          inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor:
                  Theme.of(context).colorScheme.background.withOpacity(0.4),
              isDense: true,
              enabledBorder: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(CiRadius.r3),
                  borderSide: BorderSide(
                      width: 1, color: Theme.of(context).splashColor)),
              focusedBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(width: 1, color: Colors.grey.withOpacity(0.5)),
              ),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(CiRadius.r1),
              )),
          onSelected: (String? value) {
            if (value == null) return;
            setState(() {
              _selectedCategory = value;
            });
          },
          initialSelection: _selectedCategory,
          dropdownMenuEntries:
              categories.keys.map<DropdownMenuEntry<String>>((String value) {
            return DropdownMenuEntry<String>(
              value: value,
              label: categories[value]!,
            );
          }).toList(),
        ),
        // Shows an error if constraint not met on confirm
        if (_selectedCategory == null ||
            !categories.keys.contains(_selectedCategory))
          Text(
            AppLocalizations.of(context)!.select_category_list,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.red,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          width: 700,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Required Information
                H1(AppLocalizations.of(context)!.appTitle,
                    color: isLoading ? Colors.grey : null),
                const SpaceHSmall(),
                Text(
                    style: TextStyle(color: isLoading ? Colors.grey : null),
                    AppLocalizations.of(context)!.new_common_describtion),
                const SpaceH(),
                const SpaceH(),
                H3(AppLocalizations.of(context)!.required_information,
                    color: isLoading ? Colors.grey : null),
                const SpaceH(),
                // Commons Name
                TextInputField(
                  enabled: !isLoading,
                  label: AppLocalizations.of(context)!.name,
                  formatter: FilteringTextInputFormatter.allow(
                      RegExp(r'^[a-zA-Z0-9äöüÄÖÜß\s!.-:&]+$')),
                  controller: _nameController,
                  maxLength: 20,
                  validator: (String? text) {
                    if (text == null || text.length < 3) {
                      return AppLocalizations.of(context)!.name_min_limit(3);
                    }
                    if (text.length > 20) {
                      return AppLocalizations.of(context)!.name_max_limit(20);
                    }
                  },
                ),
                const SpaceH(),
                // Describtion of the Common
                TextInputField(
                  enabled: !isLoading,
                  maxLines: 3,
                  maxLength: 500,
                  controller: _descrController,
                  label: AppLocalizations.of(context)!.subtitle_description,
                  validator: (String? text) {
                    if (text == null || text.length < 30) {
                      return AppLocalizations.of(context)!
                          .describtion_min_limit(30);
                    }
                    if (text.length > 500) {
                      return AppLocalizations.of(context)!
                          .describtion_max_limit(500);
                    }
                    return null;
                  },
                ),
                const SpaceH(),
                const SpaceH(),

                // Optional information
                H3(
                  AppLocalizations.of(context)!.optional_information,
                  color: isLoading ? Colors.grey : null,
                ),
                const SpaceHSmall(),
                Text(
                    style: TextStyle(
                      color: isLoading ? Colors.grey : null,
                    ),
                    AppLocalizations.of(context)!
                        .description_optional_information),
                const SpaceH(),
                const SpaceHSmall(),

                Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    categoryDropdown(300),
                    const SpaceH(),
                    logoUploadWidget(),
                  ],
                ),

                const SpaceH(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextInputField(
                        enabled: !isLoading,
                        label:
                            AppLocalizations.of(context)!.latitude_coordinates,
                        controller: _latController,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        validator: (value) {
                          if (value != null && value.isNotEmpty) {
                            final double? latitude = double.tryParse(value);
                            if (latitude == null ||
                                latitude < -90 ||
                                latitude > 90) {
                              return AppLocalizations.of(context)!
                                  .coordinates_error_message;
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 50),
                    Expanded(
                      child: TextInputField(
                        enabled: !isLoading,
                        label:
                            AppLocalizations.of(context)!.longitude_coordinates,
                        controller: _lngController,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        validator: (value) {
                          if (value != null && value.isNotEmpty) {
                            final double? latitude = double.tryParse(value);
                            if (latitude == null ||
                                latitude < -90 ||
                                latitude > 90) {
                              return AppLocalizations.of(context)!
                                  .coordinates_error_message;
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SpaceH(),
                Row(
                  children: [
                    Expanded(
                      child: TextInputField(
                        enabled: !isLoading,
                        label: AppLocalizations.of(context)!.website_commons,
                        controller: _websiteController,
                      ),
                    ),
                  ],
                ),
                const SpaceH(),
                const SpaceH(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Dialog canceled
                    TextButton(
                      onPressed: isLoading
                          ? null
                          : () => Navigator.pop(context, false),
                      child: Text(AppLocalizations.of(context)!.btn_cancel),
                    ),
                    const SizedBox(width: 16),
                    // Dialog confirmed
                    TextButton(
                      onPressed: isLoading
                          ? null
                          : () {
                              if (_formKey.currentState!.validate()) {
                                editCommon().then((commonId) {
                                  debugPrint(commonId);
                                  Navigator.pop(context, true);
                                  context.pushNamed(
                                    'detail',
                                    pathParameters: <String, String>{
                                      'id': commonId,
                                    },
                                    extra: widget.common == null,
                                  );
                                }).catchError((e) {
                                  showError(context, e.toString());
                                });
                              }
                            },
                      child: Text(AppLocalizations.of(context)!.btn_confirm),
                    ),
                  ],
                ),
                const SpaceH(),
                const SpaceH(),
              ],
            ),
          ),
        ),

        // Display the loading widget during adding new common ...
        if (isLoading)
          LoadingWidget(loadingText: AppLocalizations.of(context)!.loading),
      ],
    );
  }
}
