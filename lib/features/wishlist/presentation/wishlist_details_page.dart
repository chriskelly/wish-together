import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wishtogether/common/widgets/list_item_actions.dart';
import 'package:wishtogether/common/widgets/stream_list_builder.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wishtogether/features/wishlist/presentation/item_form_page.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_form_page.dart';

class WishlistDetailsPage extends StatefulWidget {
  static const String routeName = 'wishlistDetails';
  static const String route = '/wishlist/:id';

  final String wishlistId;

  const WishlistDetailsPage({super.key, required this.wishlistId});

  @override
  State<WishlistDetailsPage> createState() => _WishlistDetailsPageState();
}

class _WishlistDetailsPageState extends State<WishlistDetailsPage> {
  final WishlistRepository _wishlistRepository = getIt<WishlistRepository>();
  late final ItemRepository _itemRepository;
  late final auth.User? _currentUser;
  bool _isSpoilerFree = true; // Default to spoiler-free for the owner

  @override
  void initState() {
    super.initState();
    _itemRepository = _wishlistRepository.items(widget.wishlistId);
    _currentUser = getIt<AuthService>().currentUser;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<Wishlist?>(
          future: _wishlistRepository.get(widget.wishlistId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Text('Loading...');
            }
            if (!snapshot.hasData || snapshot.data == null) {
              return const Text('Wishlist Not Found');
            }
            return Text(
              snapshot.data!.name,
              style: Theme.of(context).textTheme.headlineSmall,
            );
          },
        ),
        actions: [
          FutureBuilder<Wishlist?>(
            future: _wishlistRepository.get(widget.wishlistId),
            builder: (context, snapshot) {
              if (!snapshot.hasData ||
                  _currentUser == null ||
                  snapshot.data == null) {
                return const SizedBox.shrink();
              }
              final wishlist = snapshot.data!;
              if (wishlist.ownerId == _currentUser.uid) {
                return Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isSpoilerFree
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _isSpoilerFree = !_isSpoilerFree;
                        });
                      },
                      tooltip: _isSpoilerFree
                          ? 'Show claimed status'
                          : 'Hide claimed status',
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () {
                        context.pushNamed(
                          WishlistFormPage.editRouteName,
                          pathParameters: {'id': wishlist.id!},
                          extra: wishlist,
                        );
                      },
                      tooltip: 'Edit Wishlist',
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: StreamListBuilder<Item>(
        stream: _itemRepository.streamAll(),
        itemBuilder: (context, item) => _buildItemCard(item, context),
        emptyMessage: 'This wishlist has no items yet.',
        listPadding: const EdgeInsets.only(bottom: 48),
      ),
      floatingActionButton: FutureBuilder<Wishlist?>(
        future: _wishlistRepository.get(widget.wishlistId),
        builder: (context, snapshot) {
          if (!snapshot.hasData || _currentUser == null) {
            return const SizedBox.shrink();
          }
          if (snapshot.data!.ownerId == _currentUser.uid) {
            return FloatingActionButton(
              onPressed: () => context.pushNamed(
                ItemFormPage.createRouteName,
                pathParameters: {'id': widget.wishlistId},
              ),
              child: const Icon(Icons.add),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildItemCard(Item item, BuildContext context) {
    return FutureBuilder<Wishlist?>(
      future: _wishlistRepository.get(widget.wishlistId),
      builder: (context, wishlistSnapshot) {
        if (!wishlistSnapshot.hasData) return const SizedBox.shrink();
        final isOwner = wishlistSnapshot.data!.ownerId == _currentUser?.uid;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: Theme.of(context).textTheme.titleLarge),
                if (item.description != null && item.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(item.description!),
                  ),
                if (item.url != null && item.url!.isNotEmpty)
                  InkWell(
                    onTap: () => _launchURL(item.url!),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        item.url!,
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                _buildItemActions(item, isOwner, context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemActions(Item item, bool isOwner, BuildContext context) {
    final bool isClaimed = item.claimedBy != null;
    final bool claimedByCurrentUser = item.claimedBy == _currentUser?.uid;

    if (isOwner) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_isSpoilerFree)
            const Spacer()
          else if (isClaimed)
            Text(
              'Claimed on ${DateFormat.yMMMd().format(item.claimedAt!)}',
              style: TextStyle(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            )
          else
            const Text(
              'Available',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ListItemActions(
            onEdit: () {
              context.pushNamed(
                ItemFormPage.editRouteName,
                pathParameters: {
                  'id': widget.wishlistId,
                  'itemId': item.id!,
                },
                extra: item,
              );
            },
            onDelete: () => _deleteItem(item.id!),
          ),
        ],
      );
    }

    // Non-owner view
    if (isClaimed) {
      if (claimedByCurrentUser) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text(
              'You claimed this!',
              style: TextStyle(
                color: Colors.purple,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _unclaimItem(item),
              child: const Text('Unclaim'),
            ),
          ],
        );
      }
      return const Align(
        alignment: Alignment.centerRight,
        child: Chip(label: Text('Claimed'), backgroundColor: Colors.grey),
      );
    }

    // Available to claim
    return Align(
      alignment: Alignment.centerRight,
      child: ElevatedButton(
        onPressed: () => _claimItem(item),
        child: const Text('Claim'),
      ),
    );
  }

  void _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not launch $url')));
      }
    }
  }

  void _claimItem(Item item) async {
    if (_currentUser == null) return;
    try {
      final updatedItem = item.copyWith(
        claimedBy: _currentUser.uid,
        claimedAt: DateTime.now(),
      );
      await _itemRepository.update(updatedItem.id!, updatedItem);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Item claimed!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to claim item: $e')));
      }
    }
  }

  void _unclaimItem(Item item) async {
    try {
      await _itemRepository.unclaim(item.id!);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Item unclaimed.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to unclaim item: $e')));
      }
    }
  }

  void _deleteItem(String itemId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item?'),
        content: const Text(
          'Are you sure you want to delete this item? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _itemRepository.delete(itemId);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Item deleted.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete item: $e')));
        }
      }
    }
  }
}
