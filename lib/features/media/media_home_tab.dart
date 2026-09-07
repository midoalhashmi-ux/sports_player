import 'package:flutter/material.dart';
import '../../core/models/channel_model.dart';
import '../../core/services/content_service.dart';

enum _MediaFilter { all, movie, series, anime }

class MediaHomeTab extends StatefulWidget {
  const MediaHomeTab({super.key});

  @override
  State<MediaHomeTab> createState() => _MediaHomeTabState();
}

class _MediaHomeTabState extends State<MediaHomeTab> {
  _MediaFilter _filter = _MediaFilter.all;
  String _query = '';

  String _labelForType(String type) {
    switch (type) {
      case 'movie':
        return 'فيلم';
      case 'series':
        return 'مسلسل';
      case 'anime':
        return 'أنمي';
      default:
        return 'محتوى';
    }
  }

  List<ChannelModel> _filterItems(List<ChannelModel> items) {
    final result = items.where((item) {
      final typeOk = _filter == _MediaFilter.all ||
          item.contentType == _filter.name;
      final query = _query.trim().toLowerCase();
      final queryOk = query.isEmpty ||
          item.title.toLowerCase().contains(query) ||
          (item.genre ?? '').toLowerCase().contains(query);
      return typeOk && queryOk;
    }).toList();
    result.sort((a, b) => (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return StreamBuilder<List<ChannelModel>>(
      stream: ContentService.watchMediaContents(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MediaMessage(
            icon: Icons.wifi_off,
            text: 'تعذر تحميل المحتوى. تحقق من اتصال الإنترنت وحاول مرة أخرى.',
          );
        }
        if (!snapshot.hasData) {
          return const _MediaSkeleton();
        }

        final allItems = snapshot.data!;
        final items = _filterItems(allItems);
        final featured = allItems.where((item) => item.isFeatured).take(8).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: TextField(
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: 'ابحث باسم الفيلم أو المسلسل…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            if (featured.isNotEmpty && _filter == _MediaFilter.all && _query.isEmpty)
              SizedBox(
                height: 142,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: featured.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, index) => _FeaturedCard(item: featured[index]),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(label: 'الكل', selected: _filter == _MediaFilter.all, color: primary,
                        onTap: () => setState(() => _filter = _MediaFilter.all)),
                    _FilterChip(label: 'أفلام', selected: _filter == _MediaFilter.movie, color: primary,
                        onTap: () => setState(() => _filter = _MediaFilter.movie)),
                    _FilterChip(label: 'مسلسلات', selected: _filter == _MediaFilter.series, color: primary,
                        onTap: () => setState(() => _filter = _MediaFilter.series)),
                    _FilterChip(label: 'أنمي', selected: _filter == _MediaFilter.anime, color: primary,
                        onTap: () => setState(() => _filter = _MediaFilter.anime)),
                  ],
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const _MediaMessage(
                      icon: Icons.movie_outlined,
                      text: 'لا يوجد محتوى متاح حالياً',
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final count = constraints.maxWidth >= 700 ? 4 : 2;
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: count,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: .68,
                          ),
                          itemCount: items.length,
                          itemBuilder: (_, index) => _MediaCard(
                            item: items[index],
                            typeLabel: _labelForType(items[index].contentType),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: color.withOpacity(.2),
        side: BorderSide(color: selected ? color : Theme.of(context).dividerColor),
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  final ChannelModel item;
  const _FeaturedCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Poster(item: item),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(9),
                color: Colors.black54,
                child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const Positioned(top: 7, right: 7, child: _Badge(text: 'مميز')),
          ],
        ),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final ChannelModel item;
  final String typeLabel;
  const _MediaCard({required this.item, required this.typeLabel});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _Poster(item: item)),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 8, 9, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        _MiniTag(typeLabel),
                        if (item.releaseYear != null) ...[
                          const SizedBox(width: 5),
                          Text('${item.releaseYear}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.isPremium)
            const Positioned(top: 7, right: 7, child: _Badge(text: 'Premium')),
          if (item.isFeatured && !item.isPremium)
            const Positioned(top: 7, right: 7, child: _Badge(text: 'مميز')),
        ],
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  final ChannelModel item;
  const _Poster({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.posterUrl?.isNotEmpty == true) {
      return Image.network(item.posterUrl!, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(context));
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.primary.withOpacity(.12),
        child: Icon(Icons.movie_outlined, size: 42, color: Theme.of(context).colorScheme.primary),
      );
}

class _MiniTag extends StatelessWidget {
  final String text;
  const _MiniTag(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          color: Theme.of(context).colorScheme.primary.withOpacity(.14),
        ),
        child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
      );
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.65),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      );
}

class _MediaSkeleton extends StatelessWidget {
  const _MediaSkeleton();

  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: .68,
        ),
        itemCount: 6,
        itemBuilder: (_, __) => Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              Expanded(child: Container(decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 10),
              Container(height: 12, width: double.infinity, color: Colors.white10),
              const SizedBox(height: 7),
              Align(alignment: Alignment.centerRight, child: Container(height: 9, width: 70, color: Colors.white10)),
            ]),
          ),
        ),
      );
}

class _MediaMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MediaMessage({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * .2),
          Icon(icon, size: 48, color: Colors.white38),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
        ],
      );
}
