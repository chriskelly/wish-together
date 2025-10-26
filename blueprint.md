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
*   **Groups & Sharing:** (Not Started)
*   **Gift Claiming:** (Not Started)

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

### Phase 4: User Profiles & Onboarding (In Progress)

*   **Goal:** Create a guided onboarding flow. Users must have a `displayName`, which is then used to personalize the app and create their first wishlist.
*   **Plan:**
    1.  **Data Model:** Create an `AppUser` data model (`user.dart`) with `uid`, `displayName`, and `phoneNumber`.
    2.  **Firestore Service:**
        *   Add `createUser`, `getUser`, and `updateUser` methods to `FirestoreService`.
        *   When `createUser` is called, it will also create a default wishlist for the user named "[displayName]'s Wishlist".
    3.  **Auth Integration:** After a user signs up for the first time, automatically call `createUser` to create their user document and initial wishlist in Firestore.
    4.  **UI - Profile Page:** Create a `ProfilePage` where a user is prompted to set or update their `displayName`.
    5.  **Forced Profile Navigation:** Update the `go_router` redirect logic:
        *   After login, check if the user's `displayName` exists in their Firestore document.
        *   If it does not exist, force a redirect to `/profile`.
        *   Allow navigation away from `/profile` only after the `displayName` has been set.
    6.  **Homepage Personalization:** Update the `HomePage` to fetch and display the user's `displayName` and their new default wishlist.

### Phase 5: Family Groups & Sharing (Not Started)

*   **Goal:** Allow users to create groups and invite others to join via a simple, shareable web link.
*   **Plan:**
    *   Create a `Group` data model.
    *   Build `GroupFormPage` and `GroupDetailsPage`.
    *   Implement sharing via a standard web URL with query parameters, handled by `go_router`.

### Phase 6: Gift Claiming & Spoiler-Free Mode (Not Started)

*   **Goal:** Implement the core "spoiler-free" gift claiming functionality.
*   **Plan:**
    *   Display shared wishlists with the ability to "claim" items.
    *   Implement the anonymous gift claiming logic in `FirestoreService`.
