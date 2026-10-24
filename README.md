# WishTogether

Give the perfect gift every time!

## Try It Out

You can use the deployed version at [https://wishtogether.gift](https://wishtogether.gift)

## Features

### Create Wishlists
Create and manage your personal wishlists. Add items you'd love to receive, and keep them organized.

### Share with Groups
Create groups with family and friends. Keep wishlists synced between multiple groups. Great for in-laws!

### Spoiler-Free Gifting
By default, no need to worry about spoilers! The owner can enable spoiler mode when they're ready to see what's been claimed.

## Development

WishTogether is a Flutter app. `AGENTS.md` is the working contract for the repo:
architecture, commands, conventions, and the authorization model.

### Agent tooling

The repository carries the official Flutter/Dart and Firebase Agent Skills as git
submodules under `.agents/skills/`. A plain clone leaves those directories empty, so
initialise them once per checkout — and add the same command to the setup of whichever
agent environment you use (Orca's repo setup hook, a Superset `.superset/config.json`, or
your own shell):

```bash
git submodule update --init --recursive
```

For a fresh clone, `git clone --recurse-submodules <url>` does it in one step. Update the
skills with `git submodule update --remote --recursive` and commit the new pointers.
