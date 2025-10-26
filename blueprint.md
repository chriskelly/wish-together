# WishTogether: A Family Gift-Sharing App

## Overview

WishTogether is a Flutter web application designed to simplify gift-giving within families. It allows users to create and manage personal wishlists, form private family groups, and share wishlists with group members. A key feature is the ability to anonymously claim gifts from shared wishlists, with a spoiler-free option for users who want to be surprised.

## Features

*   **Authentication:** Simple and secure login using a phone number and a one-time code.
*   **Wishlists:** Create multiple wishlists (e.g., "Birthday," "Christmas").
*   **Wishlist Items:** Add detailed items to wishlists, including a title, description, and a URL.
*   **Family Groups:** Create and join private family groups to share wishlists.
*   **Wishlist Sharing:** Share specific wishlists with members of your family groups.
*   **Anonymous Gift Claiming:** Anonymously mark items as "claimed" on shared wishlists.
*   **Spoiler-Free Mode:** A toggle to hide the claimed status of items, so users don't see what has been purchased for them.

## Project Plan

### Phase 1: Foundational Setup & Theming

1.  **Firebase Setup:**
    *   Enable Firebase Authentication with phone number sign-in.
    *   Set up Cloud Firestore for data storage (users, wishlists, groups).
2.  **Project Structure:**
    *   Organize the project into a feature-first structure (e.g., `auth`, `wishlists`, `groups`).
3.  **Theming:**
    *   Implement a modern, family-friendly theme using Material 3.
    *   Use `google_fonts` for custom typography.
    *   Set up a `ThemeProvider` to manage light/dark modes.
4.  **Routing:**
    *   Configure `go_router` for declarative navigation and authentication-based redirects.

### Phase 2: Authentication

1.  **Login Screen:**
    *   Create a UI for users to enter their phone number.
2.  **Verification Screen:**
    *   Build a screen for users to enter the one-time code sent to their phone.
3.  **Authentication Logic:**
    *   Implement the Firebase phone authentication flow.
    *   Create a `User` model and a service to manage user data in Firestore.

### Phase 3: Wishlists

1.  **Wishlist Screen:**
    *   Display a user's wishlists.
    *   Provide an option to create a new wishlist.
2.  **Wishlist Detail Screen:**
    *   Show the items in a selected wishlist.
    *   Allow users to add, edit, and delete items.
3.  **Data Models:**
    *   Create `Wishlist` and `Item` models.
    *   Implement Firestore services for wishlist management.

### Phase 4: Family Groups & Sharing

1.  **Groups Screen:**
    *   Display a user's family groups.
    *   Allow users to create or join a group.
2.  **Group Detail Screen:**
    *   Show the members of a group.
    *   Provide an interface to share wishlists with the group.
3.  **Sharing Logic:**
    *   Implement the logic to share and un-share wishlists.
    *   Update Firestore rules to manage access control.

### Phase 5: Gift Claiming & Spoiler-Free Mode

1.  **Shared Wishlist View:**
    *   Display a shared wishlist with the ability to claim items.
2.  **Claiming Logic:**
    *   Implement the anonymous gift claiming feature.
3.  **Spoiler-Free Toggle:**
    *   Add a UI element to enable/disable spoiler-free mode.
    *   Implement the logic to hide the claimed status of items.
