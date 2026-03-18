RULE: Follow established naming patterns in the codebase and standard conventions for each language. Consistency over preference.

## Naming Conventions

### Core Principle
When naming anything — files, functions, variables, classes, endpoints — your first job is to match what already exists. Your second job is to follow the language's standard conventions. Your personal preference is irrelevant.

### 1. Consistency First
Before creating any new name, scan the existing codebase for the established pattern:
- If the project uses `UserRepository`, name yours `OrderRepository` — not `order_repo` or `OrderService`
- If the project uses `get_user()`, name yours `get_order()` — not `fetchOrder()`
- If files are named `user-profile.ts`, name yours `order-history.ts` — not `OrderHistory.ts`

When a codebase has inconsistent naming (mixed patterns), follow the pattern used in the **most recent, most reviewed code** — not the oldest code.

### 2. Language Conventions
Follow the standard convention for each language. Do not import conventions across languages.

**JavaScript / TypeScript:**
- Functions and variables: `camelCase`
- Classes and components: `PascalCase`
- Constants: `UPPER_SNAKE_CASE`
- Files: match the default export (`UserProfile.tsx` for a component, `userHelpers.ts` for utilities) or follow the project's established pattern

**Python:**
- Functions, variables, and files: `snake_case`
- Classes: `PascalCase`
- Constants: `UPPER_SNAKE_CASE`
- Modules and packages: `snake_case`

**Rust:**
- Functions and variables: `snake_case`
- Types, traits, and enums: `PascalCase`
- Constants and statics: `UPPER_SNAKE_CASE`
- Modules and files: `snake_case`

**Go:**
- Exported names: `PascalCase`
- Unexported names: `camelCase`
- Files: `snake_case`
- Acronyms stay capitalized: `HTTPServer`, `userID`

**Swift / Kotlin:**
- Functions and variables: `camelCase`
- Types and protocols/interfaces: `PascalCase`
- Constants: `camelCase` (Swift) or `UPPER_SNAKE_CASE` (Kotlin)

**CSS:**
- Class names: `kebab-case` (or follow the project's methodology — BEM, CSS Modules, Tailwind)
- Custom properties: `--kebab-case`

**SQL:**
- Tables and columns: `snake_case`
- Avoid pluralization inconsistency — if existing tables use `user`, don't create `orders`

**API endpoints:**
- Paths: `kebab-case` (`/user-profiles` not `/userProfiles` or `/user_profiles`)
- Follow REST conventions if the project uses REST

### 3. Namespaces and Grouping
Group related code under consistent prefixes and directories:
- If authentication code lives under `auth/`, don't create `login/` for related functionality
- If services follow `FooService`, don't introduce `BarManager` or `BazHandler` for the same pattern
- If hooks follow `useFoo`, don't create `withBar` for the same concept

### 4. Abbreviations
Spell it out unless the abbreviation is universally understood in the domain:
- **Allowed:** `URL`, `HTTP`, `API`, `DB`, `ID`, `UUID`, `JSON`, `HTML`, `CSS`, `SQL`, `DOM`, `UI`, `IO`
- **Not allowed:** `usr`, `mgr`, `svc`, `btn`, `cfg`, `ctx`, `util`, `misc`, `tmp`, `prev`, `curr`
- When in doubt, spell it out. `configuration` is better than `cfg`. `manager` is better than `mgr`.

Exception: loop variables (`i`, `j`, `k`), lambda parameters where the type is obvious, and universally understood short forms in the specific domain.

### 5. Naming Should Describe Purpose, Not Implementation
- `getUsersByRole()` not `queryDatabaseForUsers()`
- `isExpired()` not `checkTimestamp()`
- `sendNotification()` not `callWebhook()`
