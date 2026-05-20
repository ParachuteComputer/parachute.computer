---
title: "Multi-user Phase 1 — admin-creates-user, force-password-change, per-user vault assignment"
description: "Phase 1 multi-user for parachute-hub: admin creates accounts with a default password, users force-change on first login, and each account is pinned to a single assigned vault. Enables one hub to serve N vaults for N people without per-user hosting."
---
# Multi-user Phase 1 — admin-creates-user, force-password-change, per-user vault assignment

**Date:** 2026-05-20
**Status:** Design proposal — informs the hub code PR chain that follows. Companion to **hub#252** (the broader multi-user UX issue).

**Companions:**
- [`2026-04-20-hub-as-portal-oauth-and-service-catalog.md`](./2026-04-20-hub-as-portal-oauth-and-service-catalog.md) — OAuth architecture with hub-as-issuer (the substrate this builds on)
- [`2026-05-18-v06-deploy-architecture.md`](./2026-05-18-v06-deploy-architecture.md) — single-container deploy shape (Phase 1's deployment target)
- [`2026-04-20-module-architecture.md`](./2026-04-20-module-architecture.md) — module + scope shape

## The decision

Phase 1 ships the minimum surface that lets an admin run **one hub for twenty different people, with twenty different vaults**. Concretely:

1. Admin creates a user account, choosing a default password.
2. User signs in with the default password and is force-redirected to change it.
3. Each user is pinned to a single assigned vault. Hub-minted tokens carry a per-vault scope claim; vault / notes / scribe already enforce per-vault scope server-side.

No self-service signup, no invite links, no multi-vault membership, no per-vault role granularity. Those are Phase 2+. Phase 1 is the foundation everything else stacks on.

## The shape Aaron asked for

From the 2026-05-19 voice memo (paraphrased):

> "Take a little bit more time on the multi-user setup. Making it where users can have scopes set specifically. But, also, if we can set up a user and get them, like, a default password and then, like, once they log in to the system, they can change their password and making it where, like, a user could only have access to a certain vault so that I could have one thing set up where I have, like, twenty vaults set up for twenty different people, and I can just give them a direct account and not even worry about getting them set up with their own hosting or anything."

The use case is **one operator hosting Parachute for friends and family**. Aaron runs the hub; he provisions an account per person, hands them a default password, points them at the URL. Each person sees their own vault. Nobody else needs to spin up a Render container, install Bun, run the wizard.

Four concrete asks:

1. Admin creates a user with an admin-chosen default password.
2. User force-changes the password on first sign-in.
3. Per-user vault scoping — user pinned to one (Phase 1) vault.
4. One hub serves N vaults for N different people, no per-user hosting.

Phase 1 ships exactly those four. Nothing more; nothing less.

## Phasing

### Phase 1 — foundation (this design)

**In:**
- `users` table gains `password_changed: boolean` + `assigned_vault: string | null`.
- Admin SPA gains `/admin/users` page: list / create (username + default password) / delete / assign a vault per user.
- Sign-in flow: if `password_changed === false`, force-redirect to `/account/change-password` after auth.
- OAuth issuer mints tokens for non-admin users with `sub: <userId>` + `vault_scope: [<assigned_vault>]` claim. Existing per-vault `vault:<name>:<verb>` scope vocabulary at vault / notes / scribe enforces it (no changes to vault-side).
- Wizard's first-boot admin is special-case: `password_changed: true` from the start (the admin already chose their password during wizard step 2).

**Not in (explicit punts):**
- Self-service signup. Account creation is admin-only.
- Invite links. The default-password path is the only onboarding shape.
- Multi-vault membership per user.
- Per-vault read/write/admin role granularity.
- Email collection or magic-link recovery.
- Audit log UI.
- Bulk CSV import.
- 2FA / SSO.

### Phase 2 — multi-vault + self-service polish

- A user can be a member of multiple vaults (`assigned_vaults: string[]`).
- Self-service profile page (`/account/profile`) — username display, last sign-in, change password, sign out everywhere.
- Invite-link onboarding as an alternative to default-password (admin issues a one-shot URL; user sets their own password on first click).
- Per-vault role granularity (`read` / `write` / `admin`) recorded per `(user, vault)` pair.
- Email collection for password reset.

### Phase 3 — later

- SSO (OIDC / SAML, probably via a plug-in).
- Audit log surfaced in admin SPA (already partly captured in the `tokens` registry).
- Bulk CSV / API user import.
- Per-vault group membership (vault has-many groups, group has-many users).
- 2FA enforcement.

## Phase 1 implementation map

### Schema changes

**Migration version 8** in `src/hub-db.ts` (last live migration is v7). One ALTER per added column; backfill the wizard admin to `password_changed=1`.

```sql
ALTER TABLE users ADD COLUMN password_changed INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN assigned_vault TEXT;

-- Backfill: every existing row pre-dates this migration. The only user who
-- could already exist is the wizard's first admin (or any account created
-- via the env-var seed path) — both already chose their password through a
-- form, so flip them to "changed."
UPDATE users SET password_changed = 1;
```

No FK on `assigned_vault`. The column holds a vault instance name (e.g. `"aaron"`, `"work"`) that resolves through `services.json` at token-mint time, not a row reference. Vaults can be renamed / archived without a DB cascade; mint-time resolution catches stale assignments by failing the lookup.

`password_changed` is stored as `INTEGER` (0/1) because SQLite doesn't have a native boolean. Helper functions in `users.ts` translate to TypeScript `boolean`.

### `users.ts` helper extensions

- `User` interface gains `passwordChanged: boolean` + `assignedVault: string | null`.
- `createUser` gains optional `assignedVault: string | null` (defaults to `null` for forward-compat with admin-without-assignment; the wizard admin remains `assignedVault: null`).
- New `markPasswordChanged(db, userId)` — sets `password_changed = 1`, called after a successful `/account/change-password` POST.
- New `setAssignedVault(db, userId, vaultName | null)` — admin path; sets the column, returns the updated User.
- `setPassword(db, userId, newPassword)` — existing helper, no signature change. Caller decides whether to also flip `password_changed`.

### New admin SPA page: `/admin/users`

Mounted under the SPA's `/admin` basename. Style + chrome match existing pages (`Tokens.tsx`, `Permissions.tsx`, `VaultsList.tsx`).

Surface:

- **List view.** Table: username, assigned vault (or `—`), password-changed status, created-at, actions (assign vault, reset password, delete).
- **Create.** Form: username + default password + assigned vault (dropdown of existing vault instance names from services.json). Submits to `POST /api/users`. Returns 201 + the created User.
- **Assign vault.** Per-row dropdown that switches the assigned vault (or `(none)`). PATCH `/api/users/:id` with `{ assigned_vault: "name" | null }`.
- **Reset password.** Per-row button → confirm modal → admin enters a new default password → POST `/api/users/:id/reset-password` with `{ password: "..." }`. Side effect: `password_changed` flips back to 0 so the next sign-in re-forces a change.
- **Delete.** Per-row button → confirm modal → DELETE `/api/users/:id`. Cascades sessions + tokens (see security section).

The page itself is admin-gated. Server-side, every `/api/users/*` endpoint requires a bearer with `parachute:host:admin` (today's mint via `/admin/host-admin-token`; same gate the existing `/api/vaults` and `/api/grants` use).

The wizard's first admin is **not deletable from the SPA**. The list view shows them with a "first admin" badge and disables the delete button — the safety rail keeps the hub from being self-locked. This is enforced in the API (DELETE returns 409 with `error: "first_admin_undeletable"`) so a malicious / buggy client can't bypass the UI guard.

### Sign-in flow change: force-change-password

Adds one server-side check at the end of `POST /login`:

```
on POST /login success:
  if user.password_changed === false:
    set session cookie  (so the user is authenticated for the change-password page)
    302 → /account/change-password?next=<original-next>
  else:
    set session cookie
    302 → next (today's behavior)
```

New server-rendered surfaces (sibling to `/login`):

- `GET /account/change-password` — form: current password + new password + confirm new password. Server-rendered HTML, no SPA bundle. Same chrome family as `/login`.
- `POST /account/change-password` — verify current password, set new password via `setPassword`, call `markPasswordChanged`, redirect to `next` (or `/admin/` if no `next`).

The redirect is **session-level**, not token-level. Once `password_changed` flips to `true`, the OAuth issuer can mint tokens for this user freely. We don't carry "must change password" forward as a scope restriction; that would force every resource server (vault, notes, scribe) to learn about the flag, and there's no reason to: the only path where this matters is interactive sign-in to the hub.

### OAuth claim shape: `sub` + `vault_scope`

Today the hub mints tokens with `sub: <userId>` and a `scope` string of space-separated scopes. The Phase 1 addition is a new claim that names which vault this user owns:

```jsonc
{
  "sub": "user-uuid-here",
  "scope": "vault:aaron:read vault:aaron:write",
  "vault_scope": ["aaron"],
  "iss": "https://hub.example.com",
  "aud": "vault",
  "exp": 1737240000,
  "iat": 1737153600
}
```

Two design notes:

1. **`vault_scope` is a list, not a string.** Phase 1 always has length 1; Phase 2 widens it without a wire-shape change. The pattern matches today's `aud` (single-string in practice, list-shape in the spec).
2. **Existing `vault:<name>:<verb>` scopes still carry the per-vault info.** `vault_scope` is informational — a "this is the user's home vault" hint for clients (notes' default-vault selector, the SPA's "switch vault" UI). Authorization-bearing remains the scope string; scope-guard at vault / notes / scribe already enforces `vault:<name>:<verb>`. We're not introducing a parallel authz channel.

How tokens get the right scopes:

- Admin minting their own token: today's flow (broad `vault:read` etc., narrows on consent picker per `narrowVaultScopes`). Unchanged.
- Non-admin user minting their own token: the issuer reads the user's `assigned_vault`. The consent picker is pre-populated and locked to that vault. The user picks "Approve" or "Deny" — they can't pick a different vault because they don't have access. The minted token carries `vault:<assigned_vault>:<verb>` for every requested verb the client asked for; `vault_scope: [<assigned_vault>]` rides along.

### Wizard interaction

The setup wizard already creates the first admin. Two tiny adjustments:

1. `createUser` call inside the wizard passes `passwordChanged: true` (the new arg's only non-default site). The admin chose their password through the wizard form; no need to make them change it again on first sign-in.
2. The wizard makes no `assigned_vault` decision for the admin. Admin's mental model is "I have access to every vault"; `assigned_vault: null` is the "no pin" sentinel that the OAuth issuer treats as "this user can request any vault on the hub" (i.e. today's behavior).

The env-var seed path (`PARACHUTE_INITIAL_ADMIN_USERNAME` + `PARACHUTE_INITIAL_ADMIN_PASSWORD`) keeps the same treatment: env-seeded admins are `password_changed: true`, `assigned_vault: null`.

### Test plan

End-to-end smoke against a live hub:

1. Run the wizard, create admin `aaron`. Verify `password_changed=1`, `assigned_vault=null` in the DB.
2. Create vault `bob` via existing admin flow.
3. As admin, hit `/admin/users` → create user `bob-user` with default password `bob-temp-pw-2026`, assigned vault `bob`.
4. Sign out. Sign in as `bob-user` / `bob-temp-pw-2026`. Verify redirect to `/account/change-password`.
5. Submit the change-password form with a new password. Verify redirect to `/admin/`.
6. Open notes via the OAuth flow; verify the consent picker is pre-locked to vault `bob`. Approve.
7. Verify minted token's `scope` claim is narrowed to `vault:bob:<verb>` and `vault_scope` claim is `["bob"]`.
8. Open the bob vault — succeeds. Try to hit `/vault/aaron/*` with the bob-user token — server returns 403.
9. As admin, change bob-user's `assigned_vault` to `null`. Sign in as bob-user, mint a new token. Verify the consent picker now shows all vaults.

Unit + integration tests cover:

- Migration v8 against a v7-state fixture DB; verify backfill flips existing rows to `password_changed=1`.
- `createUser` with + without `assignedVault`.
- `markPasswordChanged`, `setAssignedVault` happy paths and `UserNotFoundError`.
- `/login` flow: `password_changed=false` redirects to `/account/change-password`; `=true` redirects to `next`.
- `/account/change-password` POST: wrong current password rejected; new ≠ confirm rejected; success flips the flag and redirects.
- Admin API: list / create / patch / delete users; first-admin-undeletable; `assigned_vault` validates against services.json vaults.
- OAuth issuer: non-admin with `assigned_vault=foo` minting `vault:read` produces a token with `vault:foo:read` scope and `vault_scope: ["foo"]`.

## Trade-offs and decisions to flag for Aaron's review

### 1. Single-vault per user (Phase 1) vs multi-vault from day one

**Pick:** Single-vault. `assigned_vault: string | null` in the schema.

The simplification matters because most onboarding flows want a "this is your vault" notion — picking from a dropdown of three is confusing for a first-time user. Phase 2 widens to `assigned_vaults: string[]` (the migration is additive). The schema column gets renamed at that point or kept as "primary" with a separate join table.

If Aaron's "twenty vaults for twenty people" use case never sprouts multi-vault membership, we never widen.

**Alternative considered:** Land the join table now (`user_vaults (user_id, vault_name, role)`). Rejected: solves a Phase 2 problem with Phase 1 complexity. The single-column shape covers Aaron's stated use case completely.

### 2. Default-password vs invite-link

**Pick:** Default-password.

The admin types a password in the create-user form; the user signs in with it; the user force-changes on first login. Three reasons:

- It's what Aaron explicitly asked for.
- It works without email (Parachute Phase 1 has no email).
- The force-change-on-first-login flow handles the obvious worry (admin sees the password, user wants privacy).

Invite-link is Phase 2 (`/account/setup/<one-shot-token>` lands the user on a "pick your password" form, no admin-typed-password ever exists). Equivalent privacy, no email needed, but more moving parts.

### 3. Per-vault permissions (read / write / admin)

**Pick:** Punt to Phase 2.

Phase 1 grants the assigned user every `vault:<name>:<verb>` the client requests. That's effectively `read+write` for a typical Notes client. No per-user read-only / admin distinction.

The shape is forward-compatible: when Phase 2 adds a role column, the migration sets every existing row to `role='write'` (today's effective behavior) and the issuer learns to narrow scopes by role.

**To weigh in on:** is "the assigned user has full vault access" the right default, or do we want read-only-by-default and the admin opts each user into write?

### 4. Username constraints

**Pick proposal:** length 2-32 chars, charset `[a-z0-9_-]` (lowercase letters, digits, underscore, hyphen). Reserved words: `admin`, `root`, `system`, `setup`, `parachute`, `hub`.

Reserved-word list keeps URL-shaped surfaces safe (we don't yet have `/users/<username>` URLs, but Phase 2 might). Lowercase-only avoids the "user `Bob` vs `bob`" confusion that needs case-folding helpers everywhere.

**To weigh in on:** the reserved list, and whether lowercase-only is too strict.

### 5. Password rules

**Pick proposal:** min length 8. No complexity rules. No max length.

Phase 1 is "the friend's hub" — not a public service. Password hygiene matters less here than the basic ability to set one. We can layer complexity rules in a Phase 2 hardening pass.

**To weigh in on:** does Aaron want a higher floor (12? 16? a passphrase nudge?), or is 8 fine.

### 6. What happens when admin deletes a user with active sessions / minted tokens

**Pick proposal:** Hard delete in the `users` row, cascade-delete the user's sessions (already FK-referencing `users.id`), and **revoke every token** the user owns by writing `revoked_at` rows in the `tokens` table (the existing revocation-list machinery picks them up within the 60-second poll window).

The cascading delete on `tokens` would be cleaner but loses audit trail — keeping the rows and flipping `revoked_at` preserves "this user existed and held these tokens" for incident response.

**To weigh in on:** is hard-delete the right shape, or do we want soft-delete (a `deleted_at` column on users) so the admin can undo for a window?

## What changes in the existing hub_settings + DB shape

Only the `users` table changes. Migration v8 is the minimum diff:

```sql
ALTER TABLE users ADD COLUMN password_changed INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN assigned_vault TEXT;
UPDATE users SET password_changed = 1;
```

No new tables. No new `hub_settings` keys. The existing `sessions`, `tokens`, `grants`, `auth_codes`, `clients` tables are unchanged.

`services.json` is unchanged. The vault list the SPA renders in the assigned-vault dropdown comes from today's `listVaultNames(manifest)` helper in `oauth-handlers.ts`.

## Security considerations

### Default password storage

The admin-typed default password is **never stored in plaintext**. The flow is:

1. Admin POSTs `/api/users` with `{ username, password, assigned_vault }`.
2. Server runs `argon2id` over the password (same path as `createUser`).
3. Server stores only the hash.

If the admin needs to re-display the password (because they wrote it on a sticky note and lost it), they don't. They reset it: admin clicks "reset password," types a new default password, the row gets a new hash + `password_changed=0`.

The default password lives briefly in the admin's browser (until the form submits) and on the wire as part of the POST body — both already protected by TLS. After the POST returns 201, no other system has it.

### Force-change-password as session-level, not token-level

`password_changed` is a property of the user's account, not the user's token. Once the user changes their password, the bit flips and there's no "must change password" trace on minted tokens. This is the right shape because:

- The check only matters for interactive sign-in. Programmatic token use (the user pasting their token into Notes' MCP config) doesn't need to know about it.
- Carrying a "must change password" claim forward would force vault / notes / scribe to learn about the flag — gratuitous coupling.
- The change-password redirect happens at `/login`, before any token is minted; tokens minted post-change are already on the "password-changed" side of the flip.

The trade-off: if an admin creates a user, the user signs in (forcing the change), then the admin resets their password (flipping the bit back to `password_changed=0`), the user's **existing sessions stay valid**. If the admin wants to force re-auth, they have two existing levers: revoke the user's sessions (delete from `sessions`) and / or revoke active tokens.

For Phase 1 we don't auto-cascade reset-password → session-revoke. The Phase 2 self-service profile page can offer "sign out everywhere" as an explicit user action; the admin can already do it via the existing token-revoke flow.

### Admin-creates-user audit trail

Every user-mutation API call logs to the existing access-log surface (the structured log line that already records every authenticated request). Phase 1 does not surface this in the admin SPA — the operator reads it from the hub's stdout or wherever the deploy target captures logs.

Phase 2 adds a `/admin/audit` SPA page that filters those entries.

### User cannot escalate their own scope

`assigned_vault` is admin-mutable only. The user has no API endpoint that lets them set it — the only `/api/users/*` mutations are admin-bearer-gated.

The OAuth issuer reads `assigned_vault` at mint time, not at session-creation time. A user who cleverly held onto their session cookie across an admin-side `assigned_vault` change gets the new value on their next token mint; existing tokens carry their original `vault_scope` (and their original `scope` narrowing) until expiry.

The user **can change their own password** (via `/account/change-password`) and **can sign themselves out** (via `/logout`). Phase 2's self-service profile broadens this to "view own account, sign out everywhere, regenerate own tokens" — all bounded by the user's existing scope, never broadening.

### `assigned_vault` validation

When the admin sets `assigned_vault: "foo"`, the API verifies `foo` exists in the manifest's vault list before persisting. A vault that's been removed from services.json after the assignment becomes a stale pointer — the issuer at mint time refuses to issue (`invalid_request: assigned vault no longer exists`) and the admin SPA shows a warning badge next to the affected user.

We don't auto-clear the pointer because the admin may be temporarily reconfiguring; an explicit "the vault is gone, please reassign" is more correct than silent drop.

## Sequencing — the implementation PR plan

The work splits into five PRs against `parachute-hub`. Each is independently shippable; PR N+1 depends on PR N being on `main`.

### PR 1 (small) — schema + helpers

**Touches:** `src/hub-db.ts`, `src/users.ts`, `src/__tests__/users.test.ts`.

- Migration v8: two `ALTER TABLE` + the wizard backfill.
- `User` interface + `rowToUser` carry the new fields.
- `createUser` accepts optional `assignedVault`.
- New `markPasswordChanged`, `setAssignedVault` helpers.
- Tests cover migration against a v7 fixture, helper happy paths, error paths.

No UI surface, no API endpoint. **Lands by itself** so the rest of the chain has a known-good substrate.

### PR 2 (medium) — admin API + admin SPA `/admin/users` page

**Touches:** `src/admin-users.ts` (new), `web/ui/src/routes/Users.tsx` (new), `web/ui/src/lib/api.ts`, `src/hub-server.ts` (route wiring), `web/ui/src/App.tsx` (nav entry).

- API endpoints: `GET /api/users`, `POST /api/users`, `PATCH /api/users/:id`, `DELETE /api/users/:id`, `POST /api/users/:id/reset-password`. All bearer-gated on `parachute:host:admin`.
- SPA page mirroring `Tokens.tsx` / `Permissions.tsx` patterns. Confirm-modal pattern from `Permissions.tsx` for destructive actions.
- First-admin-undeletable guard in both API and SPA.
- Assigned-vault dropdown sources from `listVaultNames(manifest)`.

### PR 3 (small) — force-change-password flow

**Touches:** `src/login-ui.ts` (or wherever `/login` lives today), `src/account-change-password-ui.ts` (new), `src/hub-server.ts` (route wiring).

- `/login` POST: detect `password_changed=false`, set session cookie, 302 to `/account/change-password?next=<original>`.
- `GET /account/change-password` — server-rendered form (same chrome family as `/login`).
- `POST /account/change-password` — verify current, set new, flip the flag, redirect.

### PR 4 (small) — OAuth issuer integration

**Touches:** `src/oauth-handlers.ts`.

- Non-admin authorize flow: pre-lock the consent picker to the user's `assigned_vault` (if non-null).
- Narrow requested scopes to `vault:<assigned_vault>:<verb>` for every requested unnamed `vault:<verb>`.
- Add `vault_scope: [<assigned_vault>]` to the minted token's claims.
- Reject mint if `assigned_vault` is non-null and no longer resolves in the manifest.

### PR 5 (small) — verification + smoke

**Touches:** integration tests in `src/__tests__/` exercising the end-to-end happy path; no production code changes.

End-to-end test: spin up a hub fixture, run wizard, create a non-admin user with an assigned vault, sign in as that user, force-change the password, mint a token via the OAuth flow, verify the token's scope narrowing + `vault_scope` claim + that the existing scope-guard at the vault-side test fixtures accepts it.

Cited bundles + counts go in each PR's commit message per the hub `CLAUDE.md` test-gate convention.

## What I want Aaron to weigh in on before code starts

These are the live trade-offs from the section above, summarized:

1. **Per-vault role default.** Does the assigned user get full `read+write+admin`, or just `read+write` (no `vault:<name>:admin`), or read-only by default with admin opt-in for write?
2. **Username constraints.** Reserved-word list + lowercase-only — too strict, fine, looser?
3. **Password minimum.** 8 chars, no complexity. Higher floor wanted?
4. **Delete-user semantics.** Hard-delete + token-revocation, or soft-delete with undo window?
5. **Default-password vs invite-link timing.** Phase 1 ships default-password only. Phase 2 adds invite-link. Reasonable, or does the invite-link variant need to land sooner?
6. **First-admin-undeletable.** Confirming this is the right safety rail. Alternative: allow deletion as long as another admin exists.

Everything else in the doc is committed-shape unless Aaron flags it. The PR chain starts the day these six are settled.
