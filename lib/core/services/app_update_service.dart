import 'package:cloud_firestore/cloud_firestore.dart';

class AppUpdateInfo {
  final String? minVersion;
  final String? message;
  final bool forceUpdate;

  const AppUpdateInfo({
    this.minVersion,
    this.message,
    this.forceUpdate = false,
  });

  factory AppUpdateInfo.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const AppUpdateInfo();
    return AppUpdateInfo(
      minVersion: map['forceUpdateMinVersion'] as String?,
      message: map['updateMessage'] as String?,
      forceUpdate: (map['forceUpdate'] as bool?) ?? false,
    );
  }
}

class AppUpdateService {
  static Future<AppUpdateInfo> fetchUpdateInfo() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('settings').doc('app').get();
      return AppUpdateInfo.fromMap(snapshot.data());
    } on Exception {
      return const AppUpdateInfo();
    }
  }
}
