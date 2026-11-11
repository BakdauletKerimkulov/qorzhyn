# Glossary

Канонический словарь домена. Один концепт = один идентификатор в коде + одно слово на локаль в UI + слова, с которыми его нельзя путать.

Правила и формат — `spec-driven-rules.md` § 3. Термин, решённый во время работы, пишется сюда **в том же прогоне**, не батчем. Расхождение кода с этим файлом — находка ревью, а не уборка на потом.

Засеяно из `lib/src/features/*/domain/`, enum'ов и `lib/l10n/app_{ru,kk,en}.arb`. Пункты с `<!-- TODO: canonical? -->` — реальные расхождения, найденные в коде; их решает человек, а не агент.

## Terminology

**Business** (`Business`, ru «бизнес», kk «бизнес», en "business") — юридическое лицо, владеющее одним или несколькими `Store`. Проходит верификацию в 3 шага (`BusinessVerificationDraft`, `VerificationStatus`), держит участников с ролями (`BusinessMembershipRole`).
NOT: `Store` — это точка, а не владелец. NOT «магазин» в UI.

**Store** (`Store`, en "store") — конкретная точка продажи: ресторан, пекарня, кафе. Принадлежит `Business`, имеет адрес, гео-локацию, тип (`StoreType`) и роли персонала (`StoreRole`).
UI-слово не решено:
- ru «заведение» — `storeNotFound`, `moreInfoAboutStore`, `howWasTheStore`
- ru «магазин» — `orderCancelledByStore`, `reviewStoreDetails`
- kk «дүкен» (= магазин), en "store"

<!-- TODO: canonical? «заведение» или «магазин» в ru. Сейчас в ARB живут оба слова для одного концепта; kk и en однозначны. Выбор влияет на ~15 ключей ARB. -->

**Item** (`Item`, ru «товар», kk «тауар», en "item") — то, что заведение определяет у себя: конкретный продукт или сюрприз-пакет. Разовый или по недельному расписанию (`WeeklySchedule`). Item сам не продаётся — из активных Item'ов `daily-sync-offers` порождает `Offer`.
NOT: `Offer` — Item это шаблон, Offer это опубликованный экземпляр. NOT «предложение».

**Offer** (`Offer`, ru «предложение», kk «ұсыныс», en "offer") — опубликованный экземпляр `Item` с количеством, окном самовывоза, гео-локацией, бейджами (`BadgeType`) и рейтингом. То, что покупатель видит на карте и бронирует. Статусы — `OfferStatus`.
NOT: `Item` (шаблон), NOT `Order` (покупка).

**Surprise bag** (нет класса в домене, ru «сюрприз-пакет», kk «тосын-пакет», en "Surprise Bag") — разновидность `Item`: набор товаров, состав которого покупатель не знает заранее. Существует **только как UI-слово**: в коде это `Item` без отдельного типа.

**Flash offer** (нет класса в домене, ru «быстрое предложение» / «разовое предложение», en "Flash offer") — `Offer`, созданный бизнесом напрямую через `createOneTimeOffer` на конкретную дату/окно самовывоза, минуя `Item` и `daily-sync-offers`. Существует **только как UI-слово** поверх `Offer`.
NOT «one-time item» — это `Item` без `WeeklySchedule` (создаётся через обычную форму Item и всё равно проходит `daily-sync-offers`).

<!-- TODO: canonical? Слово несёт продуктовый смысл (ядро модели TGTG), но в домене ему ничего не соответствует — ни поля, ни подтипа Item. Либо это признак Item, либо термин надо убрать из UI. -->

**Order** (`Order`, ru «заказ», kk «тапсырыс», en "order") — покупка `Offer` конкретным покупателем. Жизненный цикл `OrderStatus`: `confirmed → preparing → readyForPickup → completed | cancelled | expired`. Отмена хранит инициатора (`CancelledBy`).
NOT «бронь»: бронирование — это действие, создающее Order (`reserve-offer`, ru «Забронировать»), а не отдельная сущность.

<!-- TODO: canonical? В ARB есть третье слово для предмета заказа: termsAndConditionsReserve говорит «Бронируя этот обед». «Обед» не соответствует ни Item, ни Offer. -->

**Active order** (`Order.isActive`, ru «активный заказ», kk «белсенді тапсырыс», en "active order") — `Order` в одном из статусов `confirmed`, `preparing`, `readyForPickup`: заказ, который ещё требует действия от заведения. Терминальные `completed`, `cancelled`, `expired` активными не считаются.
NOT «текущий заказ» — то же самое другими словами, не вводить. NOT «прошлый заказ»: «прошлые» (`pastOrders`) — это всё неактивное вместе, а не отдельная группа статусов.

**Pickup window** (`pickupWindow`, ru «время самовывоза», kk TODO, en "pickup window") — интервал, в который покупатель обязан забрать заказ. Живёт на `Offer`, порождает напоминания (`sendOrderReminders`) и `expired`-переход.
NOT «доставка»: доставки в продукте нет, только самовывоз (`payOnPickup`).

**Review** (`Review`, ru «отзыв», en "review") — оценка `Store` после завершённого `Order`. Запрашивается отложенным пушем.
NOT `Rating` — `Rating` это агрегат на `Offer`/`Store`, а `Review` это одна запись от покупателя.

**Client app / Business app** (flavor'ы Android `client` / `business`, аудитории пушей `PushAudience.client` / `PushAudience.business`, ru «клиентское приложение» / «бизнес-приложение») — две сборки из одного Dart-пакета: покупательская и для заведений. Имена flavor'ов совпадают с членами `PushAudience` — при добавлении третьей сборки эти два списка меняются вместе.
NOT `Business` — это юрлицо в домене; «бизнес-приложение» это сборка, а не сущность. NOT «merchant app», NOT «партнёрское приложение», NOT «админка» — ни одно из этих слов в проекте не канонично.

**Business console** (`lib/src/features/business_console/`, ru «бизнес-консоль», en "business console") — web-развёртывание бизнес-приложения: тот же Dart-код и тот же entry point `lib/main_business.dart`, собранный под web (`flutter build web -t lib/main_business.dart`) и раздаваемый Firebase Hosting. Клиент остаётся mobile-only, поэтому web-развёртывание в проекте ровно одно.
NOT «бизнес-приложение» — это сборка (Android flavor `business`, `applicationId kz.qorzhyn.business`); «бизнес-консоль» — её веб-ипостась. Разница существенна там, где речь про flavor'ы: у консоли их нет, её отделяет только `-t`. NOT «веб-консоль для бизнеса» — то же самое другими словами; эта формулировка жила в `ai_docs/RELEASE_READINESS.md:24` и выровнена по термину 2026-10-04 (R14).

**Qorzhyn** (бренд; `applicationId` `kz.qorzhyn.app` / `kz.qorzhyn.business`, Android-namespace `kz.qorzhyn`, ярлыки на устройстве «Qorzhyn» и «Qorzhyn Business») — утверждённое название продукта (`ai_docs/RELEASE_READINESS.md`, раздел «Бренд»). Ярлык клиентского приложения — «Qorzhyn» без суффикса; «Business» добавляется только бизнес-сборке.
NOT «Sarqyt» — прежнее имя. Оно осознанно остаётся [L1 спеки 050] в `package:sarqyt/`, в `name: sarqyt` в `pubspec.yaml` и в ключах ARB `appTitle` / `appTitleBusiness`, поэтому внутри UI пользователь пока видит «Sarqyt», а на ярлыке — «Qorzhyn». Расхождение временное и живёт до отдельной спеки по переименованию пакета; чинить его попутно нельзя — это 243 файла и другой класс риска. NOT «Qorjyn», NOT «Коржын», NOT «kz.sarqyt.app» — этот идентификатор занят третьей стороной.

**Upload key** (`signingConfigs` `clientUpload` / `businessUpload` в `android/app/build.gradle.kts`, ru «upload-ключ», en "upload key") — ключ, которым мы подписываем release-сборку перед загрузкой в Google Play. У каждого приложения свой: у клиентского и у бизнес-приложения. При включённом Play App Signing Google проверяет им загрузку и переподписывает сборку своим ключом; потерянный upload-ключ сбрасывается через поддержку Play.
NOT «ключ подписи приложения» (app signing key) — он хранится у Google, у нас его нет. NOT debug-ключ — локальный ключ Android SDK, которым Play подписанные сборки не принимает. NOT «release-ключ», NOT «ключ загрузки» — не вводить.

**AppUser** (`AppUser`, ru «пользователь», en "user") — авторизованный пользователь. Роль в системе — `UserRole`; роль внутри заведения — `StoreRole`; роль внутри бизнеса — `BusinessMembershipRole`. Три разные шкалы, не смешивать.

<!-- TODO: остальные термины по мере работы: Money/Currency, SalesTax, PackagingOption, DietaryType, SubscriptionPlan, PushAudience, SortBy/PickupTimeFilter. Добавлять по одному, когда термин становится спорным — не заполнять впрок. -->
