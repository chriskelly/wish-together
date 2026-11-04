import 'package:flutter/material.dart';

import 'package:wishtogether/common/widgets/brand_card.dart';
import 'package:wishtogether/common/widgets/brand_hero.dart';
import 'package:wishtogether/common/widgets/button_loading_indicator.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/common/widgets/list_content_builder.dart';
import 'package:wishtogether/common/widgets/primary_app_bar.dart';
import 'package:wishtogether/common/widgets/status_pill.dart';
import 'package:wishtogether/core/design_tokens.dart';

/// Every primitive and the component states no dev scenario reaches, in one
/// scrollable page. It follows the platform brightness, so a screenshot in
/// light and one in dark are the same surface.
class ThemeGallery extends StatelessWidget {
  const ThemeGallery({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const PrimaryAppBar(title: 'Theme gallery'),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        tooltip: 'Gallery action',
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Full-bleed, as the shipped hero is: the gallery has to show that.
          BrandHero(
            title: 'WishTogether',
            titleStyle: heroLoginTextStyle,
            actions: <Widget>[
              IconButton(
                onPressed: () {},
                tooltip: 'Hero action',
                icon: const Icon(Icons.person_outline),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(BrandGeometry.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Section(
                  title: 'Home hero, two lines',
                  children: <Widget>[
                    BrandHero(
                      title: 'Welcome,\nGrace!',
                      titleStyle: heroHomeTextStyle,
                    ),
                  ],
                ),
                _Section(
                  title: 'Type scale',
                  children: <Widget>[
                    Text('Display large', style: theme.textTheme.displayLarge),
                    Text(
                      'Display medium',
                      style: theme.textTheme.displayMedium,
                    ),
                    Text(
                      'Headline medium',
                      style: theme.textTheme.headlineMedium,
                    ),
                    Text(
                      'Headline small',
                      style: theme.textTheme.headlineSmall,
                    ),
                    Text('Title large', style: theme.textTheme.titleLarge),
                    Text('Title medium', style: theme.textTheme.titleMedium),
                    Text('Body large', style: theme.textTheme.bodyLarge),
                    Text('Body medium', style: theme.textTheme.bodyMedium),
                    Text('Body small', style: theme.textTheme.bodySmall),
                    Text('Label large', style: theme.textTheme.labelLarge),
                  ],
                ),
                _Section(
                  title: 'Buttons',
                  children: <Widget>[
                    Wrap(
                      spacing: BrandGeometry.spacingSm,
                      runSpacing: BrandGeometry.spacingSm,
                      children: <Widget>[
                        FilledButton(
                          onPressed: () {},
                          child: const Text('Filled'),
                        ),
                        ElevatedButton(
                          onPressed: () {},
                          child: const Text('Claim'),
                        ),
                        OutlinedButton(
                          onPressed: () {},
                          child: const Text('Outlined'),
                        ),
                        TextButton(onPressed: () {}, child: const Text('Text')),
                        FilledButton(
                          onPressed: null,
                          child: const Text('Disabled'),
                        ),
                        ElevatedButton(
                          onPressed: null,
                          child: const ButtonLoadingIndicator(),
                        ),
                      ],
                    ),
                  ],
                ),
                _Section(
                  title: 'Text fields',
                  children: <Widget>[
                    const TextField(
                      decoration: InputDecoration(
                        labelText: 'Wishlist name',
                        hintText: 'Birthday list',
                      ),
                    ),
                    const SizedBox(height: BrandGeometry.spacingSm),
                    const TextField(
                      enabled: false,
                      decoration: InputDecoration(labelText: 'Disabled field'),
                    ),
                  ],
                ),
                _Section(
                  title: 'Cards and list rows',
                  children: <Widget>[
                    BrandCard(
                      child: ListTile(
                        title: Text('Beach trip'),
                        subtitle: Text('3 items'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {},
                      ),
                    ),
                    BrandCard(
                      child: ListTile(
                        title: Text('Family'),
                        subtitle: Text('4 members'),
                        onTap: () {},
                      ),
                    ),
                  ],
                ),
                _Section(
                  title: 'Claim pills and chips',
                  children: <Widget>[
                    Wrap(
                      spacing: BrandGeometry.spacingSm,
                      runSpacing: BrandGeometry.spacingSm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: const <Widget>[
                        StatusPill(
                          label: 'Claimed',
                          tone: StatusPillTone.neutral,
                        ),
                        StatusPill(
                          label: 'You claimed this!',
                          tone: StatusPillTone.accent,
                        ),
                        Chip(label: Text('Filter')),
                      ],
                    ),
                  ],
                ),
                _Section(
                  title: 'Empty state',
                  children: const <Widget>[
                    ListEmptyPlaceholder(
                      message: 'No wishlists yet. Create one!',
                    ),
                  ],
                ),
                _Section(
                  title: 'Dialog and snackbar',
                  children: <Widget>[
                    Wrap(
                      spacing: BrandGeometry.spacingSm,
                      runSpacing: BrandGeometry.spacingSm,
                      children: <Widget>[
                        OutlinedButton(
                          onPressed: () => showConfirmationDialog(
                            context: context,
                            title: 'Confirm Deletion',
                            content: 'Are you sure you want to delete this wishlist?',
                            confirmText: 'Delete',
                          ),
                          child: const Text('Open dialog'),
                        ),
                        OutlinedButton(
                          onPressed: () => _showSnackBar(context),
                          child: const Text('Show snackbar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Wishlist deleted.')));
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: BrandGeometry.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: BrandGeometry.spacingSm),
          ...children,
        ],
      ),
    );
  }
}
