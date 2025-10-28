# WishTogether App Blueprint

## Overview

WishTogether is a collaborative wish-listing application designed to make gift-giving for families and groups simple, fun, and spoiler-free. Users can create personal wishlists, share them with family members or friends in private groups, and claim gifts for others without the recipient knowing.

## Key Features & Design

*   **Authentication:** Phone number-based authentication (OTP).
*   **User Profiles:** Users manage a `displayName`. New users are required to set one upon first login.
*   **Wishlists:**
    *   Users get an initial, default wishlist created automatically at sign-up.
    *   Users can create, edit, and delete their own wishlists.
*   **Items:** Users can add, edit, and delete items in their wishlists.
*   **Groups & Sharing:** Users can create groups, invite others, and share their wishlists with groups. They can also un-share wishlists.
*   **Gift Claiming & Spoilers:** Users viewing a shared wishlist can claim and unclaim items. Wishlist owners have a "spoiler-free" mode enabled by default to prevent them from seeing what has been claimed.

## Project Structure & Plan

### Phase 1: Core App Setup & Authentication (Complete)

*   Set up Flutter project with Firebase.
*   Implement phone number authentication (`firebase_auth`).
*   Set up `go_router` for navigation and basic auth redirects.

### Phase 2: Wishlist & Item Management (Complete)

*   **Data Models:** `Wishlist` and `Item`.
*   **Firestore Service:** `FirestoreService` for all wishlist and item CRUD operations.
*   **UI:** `WishlistFormPage`, `WishlistDetailsPage`, and `ItemFormPage`.
*   **Navigation:** `go_router` for wishlist and item pages.

### Phase 3: UI/UX Refinement & Refactoring (Complete)

*   **Unified Forms:** Refactored item creation/editing into a single `ItemFormPage`.
*   **Improved Navigation:** Updated `go_router` to support editing routes.
*   **Code Quality:** Resolved all analysis issues and removed obsolete test files.

### Phase 4: User Profiles & Onboarding (Complete)

*   **Goal:** Create a guided onboarding flow. Users must have a `displayName`.
*   **Implementation:**
    *   `User` data model.
    *   `FirestoreService` methods for user management and default wishlist creation.
    *   `go_router` redirect logic to enforce profile creation for new users.

### Phase 5: Family Groups & Sharing (Complete)

*   **Goal:** Allow users to create groups, invite others, and share/unshare wishlists.
*   **Implementation:**
    *   `Group` data model.
    *   `GroupFormPage` and `GroupDetailsPage`.
    *   Sharing via a standard web URL handled by `go_router`.
    *   UI for sharing and un-sharing wishlists from a group.

### Phase 6: Gift Claiming & Spoiler-Free Mode (In Progress)

*   **Goal:** Implement the core "spoiler-free" gift claiming functionality.
*   **Plan:**
    1.  **Claiming Logic (Done):** Implemented `claimItem` and `unclaimItem` in `FirestoreService`. UI exists for non-owners to claim items.
    2.  **Spoiler-Free State:** Add a `_isSpoilerFree` boolean state variable to `WishlistDetailsPage`, defaulting to `true` for the wishlist owner.
    3.  **Spoiler Toggle:** Add an `IconButton` (e.g., an eye icon) to the `AppBar` of the `WishlistDetailsPage`. This toggle will only be visible to the owner and will update the `_isSpoilerFree` state.
    4.  **Conditional UI:**
        *   When `_isSpoilerFree` is `true`, the owner will not see any "claimed" status. The item will look "Available".
        *   When `_isSpoilerFree` is `false`, the owner will see the true status of the item (e.g., "Claimed on...").
        *   Non-owners will always see the true claim status and have the ability to claim/unclaim.

