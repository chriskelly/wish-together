# WishTogether: A Family Gift-Sharing App

## Overview

WishTogether is a Flutter web application designed to simplify gift-giving within families. It allows users to create and manage personal wishlists, form private family groups, and share wishlists with group members. A key feature is the ability to anonymously claim gifts from shared wishlists, with a spoiler-free option for users who want to be surprised.

## Current Status & Features

*   **Authentication:** Users can securely log in with their phone number.
*   **Wishlist & Item Management (CRD):** Users can create, read, and delete wishlists and the items within them.
*   **Core Setup:** The project is set up with `go_router` for navigation and a Material 3 theme.

## Project Plan

### Phase 1: Foundational Setup & Theming (Complete)

*   **[x] Firebase Setup:** Enabled Firebase Authentication and Firestore.
*   **[x] Project Structure:** Organized by feature (`auth`, `wishlists`, `groups`).
*   **[x] Theming:** Implemented a Material 3 theme with `google_fonts`.
*   **[x] Routing:** Configured `go_router` for navigation and auth redirects.

### Phase 2: Authentication (Complete)

*   **[x] Login & Verification Screens:** Created UIs for phone number input and OTP verification.
*   **[x] Authentication Logic:** Implemented the full Firebase phone auth flow.

### Phase 3: Wishlists & Item Management (In Progress)

*   **[x] Wishlist & Item Creation:** Users can create wishlists and add items to them.
*   **[x] Wishlist & Item Deletion:** Users can delete wishlists and the items within them.
*   **[x] Wishlist Details Page:** A dedicated page to view and manage items within a wishlist.

*   **Next Steps (Editing & Refactoring):**
    1.  **Refactor and Generalize Form Pages:**
        *   Rename `create_wishlist_page.dart` to `wishlist_form_page.dart`.
        *   Rename `add_item_page.dart` to `item_form_page.dart`.
        *   Modify both pages to accept an optional existing object (a `Wishlist` or `Item`). When an object is passed, the page will operate in "edit mode" by pre-filling the form. Otherwise, it will be in "create mode."
    2.  **Implement Update Logic in Firestore Service:**
        *   Add an `updateWishlist(Wishlist wishlist)` method to `FirestoreService`.
        *   Add an `updateItemInWishlist(String wishlistId, Item item)` method to `FirestoreService`.
    3.  **Update UI and Navigation:**
        *   Add an "edit" icon button to each wishlist card on the `HomePage`.
        *   Modify the `onTap` action for each item in the `WishlistDetailsPage` to navigate to the `item_form_page.dart` in edit mode.
        *   Update the `go_router` configuration to handle passing the objects to the form pages.

### Phase 4: Family Groups & Sharing (Not Started)

*   **Create/Join Group:** Allow users to create a new group or join an existing one with a code.
*   **Group Details Page:** Display group members and the join code. Provide an interface for sharing/un-sharing wishlists with the group.
*   **Sharing Logic:** Implement the backend logic to manage wishlist visibility within groups.

### Phase 5: Gift Claiming & Spoiler-Free Mode (Not Started)

*   **Shared Wishlist View:** Display a shared wishlist with the ability to claim items.
*   **Claiming Logic:** Implement the anonymous gift claiming feature.
*   **Spoiler-Free Toggle:** Add a UI element and logic to hide the claimed status of items.
