# ai_specs index

Maintained by agents: update this table whenever a spec is created, changes status, or is archived (see `spec-driven-rules.md`).

## Active

| # | Feature | Type | Size | Status | Date | Files |
|---|---------|------|------|--------|------|-------|
| 051 | Подпись release-сборок upload-ключами | feature | M | refined | 2026-10-22 | ledger, spec |
| 049 | Экран заказов в бизнес-приложении | feature | L | refined | 2026-09-06 | ledger, spec, plan |
| 047 | Переезд Firebase в europe-west1 | infrastructure | L | approved | 2026-09-09 | plan |

## Archived (`archive/`)

| # | Feature | Type | Status | Date | Files |
|---|---------|------|--------|------|-------|
| 001 | Specific architecture docs | feature | done | 2026-05-11 | request, spec, plan |
| 002 | Not ready features | feature | done | 2026-05-12 | request, spec, plan |
| 003 | Rework offers schedule | refactor | done | 2026-05-23 | request, spec, plan |
| 004 | Fix offer creating | fix | done | 2026-05-23 | request, spec, plan |
| 005 | Refactor business account | refactor | done | 2026-05-23 | request, spec, plan |
| 006 | Checkout partnership system | feature | done | 2026-05-25 | request, spec, plan |
| 007 | Favorite restaurants | feature | done | 2026-06-04 | request, spec, plan |
| 008 | Rewrite orders screen | refactor | done | 2026-06-09 | request, spec, plan |
| 009 | Optimization business sign-in | refactor | done | 2026-06-10 | request, spec, plan |
| 010 | Reviews feature | feature | done | 2026-06-10 | request (impl), spec, plan |
| 011 | Refactor email verification | refactor | done | 2026-06-11 | spec, plan |
| 012 | Refactor booking flow | refactor | done | 2026-06-14 | spec, plan |
| 012a | Fix booking flow: remove payment | fix | done (superseded by 012) | 2026-06-14 | spec |
| 013 | Admin dev menu | feature | done | 2026-06-26 | spec, plan |
| 020 | Admin page navigation | feature | done (duplicate of 013) | 2026-07-05 | request |
| 014 | Review details location fix | fix | done | 2026-06-27 | spec |
| 015 | Refactor review details screen | refactor | done | 2026-06-27 | request, spec, plan |
| 016 | Order payment status fix | fix | done | 2026-06-28 | spec |
| 017 | Send changes to Firebase | feature | done | 2026-06-28 | request, spec, plan |
| 018 | Refactor create offer flow | refactor | done | 2026-07-04 | request, spec, plan |
| 019 | Delete offer | feature | done (already implemented, see 023/025/026) | 2026-05-23 | request |
| 021 | Wire team list into settings tab | refactor | done | 2026-07-06 | spec |
| 022 | Fix store settings border stretch | fix | done | 2026-07-06 | spec |
| 023 | Fix delete item error | fix | done | 2026-07-06 | spec, plan |
| 024 | Fix flickering reservations list | fix | done | 2026-07-07 | spec |
| 025 | Fix item delete navigation | fix | done | 2026-07-08 | spec |
| 026 | Fix disposed Ref in SettingsContentController | fix | done | 2026-07-10 | spec |
| 027 | Fix SliverBusinessOrders empty-state crash | fix | done | 2026-07-10 | spec |
| 028 | Fix item screen reservations flickering | fix | done | 2026-07-11 | request, spec, plan |

| 029 | Adaptive design for schedule widget | feature | done | 2026-08-04 | request |

| 030 | Redirect to home when offer deleted | fix | done | 2026-07-12 | spec |

| 031 | Toolkit compliance refactoring | refactor | done | 2026-07-12 | request, spec, plan |

| 032 | Fix riverpod_lint warnings | chore | done | 2026-07-26 | spec |

| 033 | Fix keepAlive lint on geolocatorService | chore | done | 2026-07-26 | spec |

| 034 | Order flow notifications | feature | done | 2026-07-27 | request, spec, plan |

| 035 | Fix offers list flashing then disappearing after GPS resolves | fix | done | 2026-07-30 | spec |

| 036 | Fix expireOrders transaction read-after-write | fix | done | 2026-07-30 | spec |

| 037 | Fix cancelOrder transaction read-after-write | fix | done | 2026-07-31 | spec |

| 038 | Wire flash offer entry point | fix | done | 2026-07-31 | spec |

| 039 | Fix broken idempotency guard and unrestored partner claims in completeMerchantOnboarding | fix | done | 2026-07-31 | spec |

| 040 | Fix missing businesses/{businessId} write rule for verification submit | fix | done | 2026-07-31 | spec |

| 041 | Fix Firestore rules blocking review submission (rating vs storeRating/offerRating) | fix | done | 2026-07-31 | spec |

| 042 | Enforce pickup window on order status transitions | fix | done | 2026-08-01 | spec |

| 043 | Fix section header overflow on compact screens | fix | done | 2026-08-03 | spec |

| 044 | Fix missing Firestore composite indexes for item reviews and current offer | fix | done | 2026-08-03 | spec |

| 045 | Fix schedule day row overflow in the create-item form | fix | done | 2026-08-04 | spec |

| 046 | Подготовка к переезду Firebase в europe-west1 | infrastructure | done | 2026-08-06 | plan |

| 048 | Небезопасное чтение custom claims в isPartner() и canCreateStore() | fix | done | 2026-08-16 | spec |

| 050 | Разделение сборки на flavor'ы client и business | refactor | done | 2026-09-09 | ledger, spec, plan |

Next number: **052**.

Renumbered during 2026-07-05 migration (one number = one feature): `004-rework-offer-feature` → `019-delete-offer`, `013-detail-managing-business-ui` → `020-admin-page-navigation`; unnumbered `specific-architecture-*` → `001-*`.
