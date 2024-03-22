import 'package:flutter/material.dart';
import 'package:flutter_application_test/globals/categories.dart';
import 'package:flutter_application_test/globals/global_widgets.dart';
import 'package:flutter_application_test/globals/custom_future_builder.dart';
import 'package:flutter_application_test/globals/shimmer_widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:parse_server_sdk_flutter/parse_server_sdk_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapsWidget extends StatefulWidget {
  const MapsWidget({super.key});

  @override
  State<MapsWidget> createState() => _MapsWidgetState();
}

class _MapsWidgetState extends State<MapsWidget> {
  final MapController _mapController = MapController();

  MapOptions _mapOptions({Position? center}) => MapOptions(
        center: center != null
            ? LatLng(center.latitude, center.longitude)
            : LatLng(51.0, 10.0),
        zoom: 8.0,
        maxZoom: 17.0,
        minZoom: 4.0,
        interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate,
      );

  List<ParseObject> _geoLocations = [];

  @override
  void initState() {
    super.initState();
    fetchGeoLocations().then((locations) {
      setState(() {
        _geoLocations = locations;
      });
    });
  }

  Future<List<ParseObject>> fetchGeoLocations() async {
    final queryBuilder = QueryBuilder<ParseObject>(ParseObject('CommonDetails'))
      ..keysToReturn(['commonId', 'location']);

    final response = await queryBuilder.query();

    if (response.success && response.results != null) {
      return response.results as List<ParseObject>;
    } else {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    Marker drawMarker(String commonId, LatLng geoPoint) {
      return Marker(
        point: geoPoint,
        builder: (context) => CustomMarker(commonId: commonId),
      );
    }

    return Scaffold(
      body: FlutterMap(
        mapController: _mapController,
        options: _mapOptions(),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
          ),
          MarkerLayer(
            markers: _geoLocations
                // Filter null locations
                .where((location) => location.get('location') != null)
                // Fetch geo location and common details, then draw marker
                .map((location) {
              ParseGeoPoint point = location.get('location');
              ParseObject commonPointer = location.get('commonId');
              final String commonId = commonPointer.get('objectId');

              final double latitude = point.latitude;
              final double longitude = point.longitude;

              return drawMarker(commonId, LatLng(latitude, longitude));
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class CustomMarker extends StatelessWidget {
  final String commonId;

  const CustomMarker({
    super.key,
    required this.commonId,
  });

  Future<ParseObject?> fetchCommon(String commonsId) async {
    final queryBuilder = QueryBuilder<ParseObject>(ParseObject('Commons'))
      ..whereEqualTo('objectId', commonsId);

    final response = await queryBuilder.query();

    if (response.success && response.results != null) {
      return response.results![0];
    } else {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return SizedBox(
            height: 145,
            width: 400,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: CloseButton(
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  CustomFutureBuilder(
                    future: fetchCommon(commonId),
                    onLoaded: (ParseObject common) {
                      return Flexible(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: CommonNavListTile(
                            titleName: common['name'],
                            subtitleName:
                                translateCategory(context, common['domain']),
                            leadingLogoUrl: common['logo']?['url'],
                            commonObjectId: common['objectId'],
                            trailingWidget: const Icon(Icons.chevron_right),
                          ),
                        ),
                      );
                    },
                    onError: (error) => Text(error.toString()),
                    onLoading: const ShimmerListTile(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      child: Icon(
        Icons.location_on,
        color: Theme.of(context).primaryColorDark,
      ),
    );
  }
}
