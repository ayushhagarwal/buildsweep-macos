# StoreKit handoff

Create exactly this product in App Store Connect:

- Type: Non-Consumable
- Product ID: `com.ayush.buildsweep.pro.lifetime`
- Reference name: BuildSweep Pro Lifetime
- Display name: BuildSweep Pro
- Description: Unlock safe Xcode storage cleanup forever.
- Base price: USD $4.99 equivalent

Then:

1. Complete localization, pricing, tax, review screenshot, and availability.
2. Attach the IAP to app version 1.0.
3. Test product loading, localized `displayPrice`, verified purchase, cancellation, pending Ask to Buy, restore, offline last-known entitlement, refund, and revocation using the real sandbox product.
4. Confirm purchasing returns to the preserved cleanup review and never starts deletion automatically.
5. Confirm a verified lifetime entitlement bypasses the free-session gate.

There is intentionally no local `.storekit` file and no dummy product identifier.

