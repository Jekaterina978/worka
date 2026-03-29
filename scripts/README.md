# Worka — Scripts

Скрипты для обслуживания Firestore базы данных.

---

## cleanup_guest_and_test.js

Удаляет мусорные данные из Firestore:

| Секция | Что делает |
|--------|-----------|
| **A** | Целиком удаляет тестовые коллекции: `cvs_test`, `jobs_test`, `responses_test`, `app_test` |
| **B** | Удаляет гостевые/анонимные записи из `cvs`, `jobs`, `applications`, `jobOffers` |
| **C** | Чистит legacy коллекцию `responses` |
| **D** | Сканирует подколлекции `users/{uid}/cvs` и `users/{uid}/vacancies` |

**Гостевыми** считаются записи, где `ownerId` / `applicantId` / `employerId` равен: `""`, `"null"`, `"undefined"`, `"guest"`, `"anonymous"`, `"none"`, `"unknown"`, `"test"`, `"dev"`.

### Требования

- Node.js 18+
- Пакет `firebase-admin` (`npm install firebase-admin` в папке `scripts/`)
- Сервисный аккаунт Firebase (JSON-ключ)

### Получить сервисный аккаунт

1. [Firebase Console](https://console.firebase.google.com/) → проект → ⚙️ Project Settings
2. Вкладка **Service accounts**
3. **Generate new private key** → скачать JSON
4. Сохранить как `scripts/serviceAccountKey.json` (в `.gitignore`)

### Установка зависимостей

```bash
cd scripts
npm install firebase-admin
```

### Запуск

#### Предпросмотр (ничего не удаляет)

```bash
node cleanup_guest_and_test.js ./serviceAccountKey.json --dry-run
```

Или через переменную окружения:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json
node cleanup_guest_and_test.js --dry-run
```

#### Реальное удаление

```bash
node cleanup_guest_and_test.js ./serviceAccountKey.json --run
```

#### Удаление + мягко удалённые CV (isDeleted == true)

```bash
node cleanup_guest_and_test.js ./serviceAccountKey.json --run --delete-soft-deleted
```

#### Пропустить подколлекции пользователей (быстрее при большой базе)

```bash
node cleanup_guest_and_test.js ./serviceAccountKey.json --run --skip-subcollections
```

### Флаги

| Флаг | Описание |
|------|---------|
| `--dry-run` | Только считает, в Firestore ничего не пишет |
| `--run` | Реальное удаление (требуется явно) |
| `--delete-soft-deleted` | Дополнительно удалять CV с `isDeleted == true` |
| `--skip-subcollections` | Не сканировать `users/{uid}/cvs` и `users/{uid}/vacancies` |

### Пример вывода

```
╔══════════════════════════════════════════════════════╗
║  Worka — Очистка гостевых и тестовых данных          ║
║  ⚠️  DRY-RUN: реальных удалений НЕ будет             ║
╚══════════════════════════════════════════════════════╝

━━━ A) Тестовые коллекции ━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [dry] cvs_test         удалено: 12
  [dry] jobs_test        удалено:  5
  [dry] responses_test   удалено:  0
  [dry] app_test         удалено:  3

━━━ B) cvs — гостевые записи ━━━━━━━━━━━━━━━━━━━━━━━━
  Просканировано: 234, к удалению: 7
    4x — ownerId пустой/guest
    3x — isDeleted == true (--delete-soft-deleted не задан, пропущено)

...

╔══════════════════════════════════════════════════════╗
║  ИТОГ                                                ║
╠═══════════════════════════╤════════╤════════╤════════╣
║ Секция                    │ Scan.  │ Flag.  │  Del.  ║
╠═══════════════════════════╪════════╪════════╪════════╣
║ cvs_test (вся коллекция)  │     12 │     12 │      0 ║
║ jobs_test (вся коллекция) │      5 │      5 │      0 ║
...
╚═══════════════════════════╧════════╧════════╧════════╝
  ⚠️  DRY-RUN — реальных удалений не было
```

### Безопасность

- Скрипт **никогда** не удаляет документы коллекции `users` (профили пользователей)
- Скрипт **никогда** не удаляет `notifications`
- Коллекции `applications` и `jobOffers` удаляются только при `applicantId`/`employerId` = guest; документы с реальными UID не трогаются
- Рекомендуется всегда сначала запустить `--dry-run` и проверить вывод

---

## migrate_owner_type.js

Миграция схемы: добавляет поле `ownerType` (`"personal"` | `"business"`) в коллекции `jobs`, `applications`, `jobOffers`, `responses`.

### Запуск

```bash
# Предпросмотр
node migrate_owner_type.js ./serviceAccountKey.json --dry-run

# Реальная миграция
node migrate_owner_type.js ./serviceAccountKey.json
```

Исторические записи без `ownerType` получают значение `"personal"` по умолчанию.
Мигрированные документы помечаются флагом `_migratedOwnerType: true`.

---

## cleanup_duplicate_vacancy_copies.js

Безопасная one-off очистка старых дубликатов вакансий-копий в коллекции `jobs`.

### Что считается кандидатом на дубликат

Скрипт обрабатывает **только** вакансии, где:

- `copiedFromJobId` заполнен (есть явная lineage-связь копии)
- документ активный (`isDeleted != true`, `deletedAt == null`, `status` не `deleted/archived/removed`)
- есть `ownerId` (или `ownerUid`)

Группировка дубликатов:

`ownerId + ownerType + copiedFromJobId + normalizedCopyTitle`

> Важно: оригиналы без `copiedFromJobId` не затрагиваются.

### Правило выбора документа, который остаётся

1. Если в группе только один документ имеет активность (`responsesCount`, `applicationsCount`, `offersCount`, `viewsCount`, `views`) — остаётся он.
2. Иначе остаётся самый ранний по `createdAt` (fallback: `updatedAt`, затем `id`).
3. Остальные в группе помечаются как soft-deleted.

### Неоднозначные случаи

Если в группе несколько документов с активностью (`engagement > 0`) — группа пропускается полностью как `SKIP[AMBIGUOUS]`.

### Запуск

```bash
# Предпросмотр (ничего не меняет)
node cleanup_duplicate_vacancy_copies.js ./serviceAccountKey.json --dry-run

# Реальное применение
node cleanup_duplicate_vacancy_copies.js ./serviceAccountKey.json --run
```

### Что делает при реальном запуске

Для лишних документов выставляет soft-delete:

- `isDeleted: true`
- `deletedAt: serverTimestamp`
- `status: "deleted"`
- `cleanup.duplicateCopy: true`
- `cleanup.keptDocId`, `cleanup.sourceDocId`, `cleanup.key`
- `updatedAt: serverTimestamp`

Hard delete не используется.

---

## cleanup_integrity_safe.js

Безопасный staged cleanup для целостности данных в active runtime paths.

### Что проверяет

- `jobs` (vacancies): copy-title, draft/incomplete, garbage fields, owner-invalid, explicit stale-duplicate markers
- `cvs`: copy-title, draft/incomplete, garbage fields, owner-invalid, explicit stale-duplicate markers
- `applications`: orphan responses (нет валидного linked vacancy/CV)
- `jobOffers`: orphan offers (нет валидного linked vacancy/CV)

Также выводит **potential duplicate groups** (owner + normalized title) как `manual_review_only`.

### Режимы

- По умолчанию: `dry-run` (ничего не пишет)
- `--run`: soft cleanup режим
- В `--run` по умолчанию garbage `jobs/cvs` (битые title/category/location/salary) помечаются `isDeleted=true`
- `--hard-delete-*`: только при явном флаге, для явно безопасных категорий

### Запуск

```bash
# Dry-run (default)
node cleanup_integrity_safe.js ./serviceAccountKey.json

# Soft cleanup
node cleanup_integrity_safe.js ./serviceAccountKey.json --run

# Soft cleanup + перевести invalid public docs в unfinished
node cleanup_integrity_safe.js ./serviceAccountKey.json --run --mark-invalid-unfinished

# Soft cleanup + удалить copy-title документы (опционально)
node cleanup_integrity_safe.js ./serviceAccountKey.json --run --soft-delete-copy-title

# Soft-delete explicit duplicate-marked docs
node cleanup_integrity_safe.js ./serviceAccountKey.json --run --soft-delete-explicit-duplicates

# Hard-delete только orphan responses/offers (явно)
node cleanup_integrity_safe.js ./serviceAccountKey.json --run --hard-delete-orphans
```

### Важные safety принципы

- По умолчанию ничего не удаляется
- `hard-delete` не выполняется без явного флага
- Документы без валидного owner и без валидного `users/{uid}` помечаются удалёнными в `--run`
- Потенциальные дубликаты без явных duplicate-маркеров не удаляются автоматически
- Скрипт предназначен для повторного безопасного запуска
