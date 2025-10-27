import 'package:flutter/material.dart';
import 'package:myapp/models/item.dart';
import 'package:myapp/models/wishlist.dart';
import 'package:myapp/services/firestore_service.dart';
import 'package:go_router/go_router.dart';

class WishlistDetailsPage extends StatefulWidget {
  final String wishlistId;
  const WishlistDetailsPage({super.key, required this.wishlistId});

  @override
  State<WishlistDetailsPage> createState() => _WishlistDetailsPageState();
}

class _WishlistDetailsPageState extends State<WishlistDetailsPage> {
  final _firestoreService = FirestoreService();

  // This future is used to get the wishlist details for the app bar title
  late final Future<Wishlist?> _wishlistFuture;

  @override
  void initState() {
    super.initState();
    _wishlistFuture = _firestoreService.getWishlist(widget.wishlistId);
  }

  Future<void> _deleteItem(String itemId) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _firestoreService.deleteItemFromWishlist(widget.wishlistId, itemId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Item deleted.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting item: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<Wishlist?>(
          future: _wishlistFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Text('Loading...');
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return const Text('Wishlist');
            }
            final wishlist = snapshot.data!;
            return Text(wishlist.name);
          },
        ),
      ),
      body: StreamBuilder<List<Item>>(
        stream: _firestoreService.getWishlistItems(widget.wishlistId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Text(
                'This wishlist has no items yet. Add one!',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(item.name),
                  subtitle: item.description?.isNotEmpty == true ? Text(item.description!) : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () {
                          context.push('/wishlist/${widget.wishlistId}/item/${item.id!}/edit', extra: item);
                        },
                        tooltip: 'Edit Item',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _deleteItem(item.id!),
                        tooltip: 'Delete Item',
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.push('/wishlist/${widget.wishlistId}/add-item');
        },
        tooltip: 'Add Item',
        child: const Icon(Icons.add),
      ),
    );
  }
}
