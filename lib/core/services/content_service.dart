import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/category_model.dart';
import '../models/channel_model.dart';

class ContentService {
  static Stream<List<CategoryModel>> watchCategories() {
    return FirebaseFirestore.instance
        .collection('categories')
        .orderBy('order')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => CategoryModel.fromMap(d.id, d.data()))
            .toList());
  }

  static Stream<List<CategoryModel>> watchRootCategories() {
    return watchCategories().map(
      (categories) => categories.where((category) => category.parentId == null).toList(),
    );
  }

  static Stream<List<CategoryModel>> watchChildCategories(String parentId) {
    return watchCategories().map(
      (categories) => categories
          .where((category) => category.parentId == parentId)
          .toList(),
    );
  }

  static Stream<List<ChannelModel>> watchChannelsForCategory(
      String categoryId) {
    return FirebaseFirestore.instance
        .collection('channels')
        .where('categoryId', isEqualTo: categoryId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ChannelModel.fromMap(d.id, d.data()))
            .toList());
  }

  /// كل عناصر المحتوى من مجموعة channels نفسها. السجلات القديمة التي لا
  /// تحتوي contentType تبقى قنوات تلقائياً داخل ChannelModel.
  static Stream<List<ChannelModel>> watchMediaContents() {
    return FirebaseFirestore.instance
        .collection('channels')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ChannelModel.fromMap(d.id, d.data()))
            .where((item) => const {'movie', 'series', 'anime'}.contains(item.contentType))
            .toList());
  }

  /// يجلب بيانات قنوات محددة بمعرّفاتها (تُستخدم لشاشة المفضلة).
  /// جلب لحظي واحد (وليس Stream) — يُعاد استدعاؤه كلما تغيّرت قائمة المفضلة.
  static Future<List<ChannelModel>> fetchChannelsByIds(
      List<String> ids) async {
    if (ids.isEmpty) return [];
    final futures = ids.map(
      (id) => FirebaseFirestore.instance.collection('channels').doc(id).get(),
    );
    final snapshots = await Future.wait(futures);
    return snapshots
        .where((snap) => snap.exists && snap.data() != null)
        .map((snap) => ChannelModel.fromMap(snap.id, snap.data()!))
        .toList();
  }
}
