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
- 2FA enforcement (Phase 2). 2FA *enrollment* is the optional Phase 1.5 PR 6 surface — see the 2FA orientation section + sequencing below. SSO (OIDC / SAML) is Phase 3.

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

PR 2 identifies the first admin via `SELECT id FROM users ORDER BY created_at ASC LIMIT 1`. No new column needed — `created_at` is already in the users table and the wizard's first-boot admin (or env-seeded admin) is guaranteed to be the earliest row by construction.

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

**Direct navigation:** `/account/change-password` is a regular signed-in surface — a user with `password_changed=true` can still navigate to it whenever they want to change their password again. The force-redirect at `/login` is the only behavior gated on `password_changed===false`; the page itself doesn't refuse access just because the user has already changed their password once. Same on the POST: it works for any signed-in user against their own account.

### OAuth claim shape: `sub` + `vault_scope`

Today the hub mints tokens with `sub: <userId>` (a UUID — the stable `users.id` column, not the human-readable username) and a `scope` string of space-separated scopes. The username surfaces in the admin UI, logs, and the consent screen; tokens reference the user by their stable UUID so a future username-rename feature wouldn't invalidate outstanding tokens. The Phase 1 addition is a new claim that names which vault this user owns:

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
- Non-admin user minting their own token: the issuer reads the user's `assigned_vault`. The consent picker is pre-populated and locked to that vault. The user picks "Approve" or "Deny" — they can't pick a different vault because they don't have access. The minted token carries `vault:<assigned_vault>:<verb>` for every requested verb the client asked for, including `admin` when requested by the client; `vault_scope: [<assigned_vault>]` rides along.

**Note on `admin` vs `write` for an assigned user.** Per [`parachute-patterns/patterns/oauth-scopes.md`](https://github.com/openparachute/parachute-patterns/blob/main/patterns/oauth-scopes.md), `vault:<name>:write` covers all note + tag mutations; `vault:<name>:admin` inherits write and adds `/.parachute/config*` access — vault-server-level configuration (provider settings, retention, schema management). The reason Phase 1 grants an assigned user `admin` by default is that an assigned user *owns* the vault as their workspace — they should be able to manage their vault's settings (retention, providers, schema), not just its content. If they're going to live in this vault, they need the lever to configure it. Admin scope on an *unassigned* vault would be a privilege escalation, which is exactly the invariant the server-side `assigned_vault` check protects.

**Decision pin — consent picker for non-admin users: Phase 1 locks the picker; Phase 2 hides other vaults entirely.** Phase 1 (this design): pre-fill the consent screen with `assigned_vault` and render the vault selector read-only (visible label, no dropdown). Pragmatic. The user sees *which* vault they're approving access to (informational clarity beats hiding it), but can't pick a different one. Phase 2 (the ideal shape Aaron flagged): non-admin users locked to a single vault don't see any other vaults at all — no dropdown rendered, no other vault names disclosed. A non-admin shouldn't be aware of vaults they don't have scope for. Phase 1 ships lock-the-picker because it's the smallest diff; Phase 2 hardens to don't-show-other-vaults once the multi-vault membership shape lands and the picker has to reconcile multiple sources of truth anyway.

Server-side defense is independent of the UI evolution: the authorize handler refuses to mint a token whose picked vault disagrees with `assigned_vault` regardless of how the picker is rendered. A malicious client hand-crafting the POST hits the same invariant on either phase.

### Wizard interaction

The setup wizard already creates the first admin. Two tiny adjustments:

1. `createUser` call inside the wizard passes `passwordChanged: true` (the new arg's only non-default site). The admin chose their password through the wizard form; no need to make them change it again on first sign-in.
2. The wizard makes no `assigned_vault` decision for the admin. Admin's mental model is "I have access to every vault"; `assigned_vault: null` is the "no pin" sentinel that the OAuth issuer treats as "this user can request any vault on the hub" (i.e. today's behavior).

The env-var seed path (`PARACHUTE_INITIAL_ADMIN_USERNAME` + `PARACHUTE_INITIAL_ADMIN_PASSWORD`) keeps the same treatment: env-seeded admins are `password_changed: true`, `assigned_vault: null`.

**Note:** this is the post-PR-1 behavior. PR 1 must wire `passwordChanged: true` into the seed path (in addition to the migration v8 backfill that flips existing rows). Today's `seedInitialAdminIfNeeded` in `parachute-hub/src/commands/serve.ts` calls `createUser(db, username, password)` with no `passwordChanged` argument; with the migration's `DEFAULT 0`, a freshly env-seeded admin would land as `password_changed: 0` and get forced through the change-password flow on first sign-in. PR 1 extends the seed call to pass `passwordChanged: true` so env-seeded admins skip the redirect, matching the wizard-admin treatment.

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

## Decisions

The trade-offs below were the live questions before code started. Aaron has weighed in on all of them; the answers and rationale are captured here so the implementation chain has a single referent.

### 1. Single-vault per user (Phase 1) vs multi-vault from day one

**Decision:** Single-vault. `assigned_vault: string | null` in the schema. Phase 2 widens to `assigned_vaults: string[]` (the migration is additive); the schema column gets renamed at that point or kept as "primary" with a separate join table.

**Rationale:** Most onboarding flows want a "this is your vault" notion — picking from a dropdown of three is confusing for a first-time user. If Aaron's "twenty vaults for twenty people" use case never sprouts multi-vault membership, we never widen.

**Alternative considered:** Land the join table now (`user_vaults (user_id, vault_name, role)`). Rejected: solves a Phase 2 problem with Phase 1 complexity. The single-column shape covers Aaron's stated use case completely.

### 2. Default-password vs invite-link timing

**Decision (confirmed):** Default-password lands in Phase 1; invite-link lands in Phase 2.

**Rationale:** It's what Aaron explicitly asked for, it works without email (Parachute Phase 1 has no email), and the force-change-on-first-login flow handles the obvious worry (admin sees the password, user wants privacy). Invite-link is the more polished shape — `/account/setup/<one-shot-token>` lands the user on a "pick your password" form, no admin-typed-password ever exists — but it's strictly more moving parts and not blocking on Aaron's stated use case. Phase 2.

### 3. Per-vault role default for the assigned user

**Decision:** `vault:<assigned_vault>:admin`. Phase 1 grants the assigned user the full `read + write + admin` ladder for their assigned vault.

**Aaron:** "if I'm just giving somebody a user for a vault, then they are generally gonna have admin privileges on that vault."

**Rationale:** An assigned user *owns* their vault as their workspace. The whole shape of Phase 1 is "one hub, twenty people, twenty vaults" — each user is the de-facto admin of their own vault. They should be able to manage retention, providers, and schema settings, not just contents. Admin scope on an *unassigned* vault would be a privilege escalation; admin scope on the user's own assigned vault is the natural default. The server-side `assigned_vault` invariant protects against the escalation case.

Phase 2 will add explicit role granularity (`read` / `write` / `admin`) recorded per `(user, vault)` pair for the multi-vault case — at which point the default for a user added to *someone else's* vault is probably `read` or `write`, not `admin`. Phase 1's single-vault shape doesn't need that distinction.

### 4. Username constraints

**Decision (confirmed):** length 2-32 chars, charset `[a-z0-9_-]` (lowercase letters, digits, underscore, hyphen). Reserved words: `admin`, `root`, `system`, `setup`, `parachute`, `hub`.

**Aaron:** "those username constraints are good. Um, I'm not necessarily sure if we need to reserve those words, but it doesn't feel too harmful to do it."

**Rationale:** Reserved-word list keeps URL-shaped surfaces safe (Phase 2 may grow `/users/<username>` paths). Lowercase-only avoids the "user `Bob` vs `bob`" confusion that needs case-folding helpers everywhere. The reserved list is cheap insurance; if it ever bites a legitimate user the operator can edit the row in SQL.

### 5. Password rules

**Decision:** min length **12 chars**. No complexity rules (no required uppercase / digit / symbol). No max length.

**Aaron:** "We should have some minimum password rules" — bumped from the proposed 8-char floor to 12.

**Rationale:** A 12-char floor lets users use a memorable passphrase (`correct horse battery staple`) without forcing weird character-class mixes. Complexity rules drive people toward predictable patterns like `Password1!` that are easier to guess than a random 12-char string. Length-only is the modern consensus (NIST 800-63B aligns).

### 6. Delete-user semantics

**Decision:** Hard-delete + token revocation. The `users` row is removed; sessions cascade-delete via the existing FK on `users.id`; minted tokens get `revoked_at` rows (the existing revocation-list machinery picks them up within the 60-second poll window).

**Aaron:** hard-delete with token revocation is fine for delete-user semantics.

**Rationale:** Hard-delete is the simplest mental model — "this user is gone" means gone. Token rows stay (with `revoked_at` set) so the audit trail of "this user existed and held these tokens" survives for incident response. Soft-delete with an undo window was the alternative; rejected because the operator's path to "I deleted them by mistake" is "create a new user with the same username" — the new account doesn't recover the old vault assignment automatically (admin re-assigns), which is the right shape: the admin is back in control of the access decision either way.

### 7. First-admin-undeletable

**Decision (confirmed):** Yes. The wizard-created (or env-seeded) first admin cannot be deleted from the admin SPA or API. DELETE returns 409 with `error: "first_admin_undeletable"`.

**Aaron:** "making sure that we have a undeletable admin account is probably a good shape."

**Rationale:** The safety rail keeps the hub from being self-locked. If the operator deletes the only admin, there's no path back into the hub short of editing SQL directly. Phase 2 may relax this to "allow deletion as long as another admin exists" once the role model lands; Phase 1 keeps it absolute because Phase 1 has no role model — every non-first-admin user is non-admin, so the first admin is *the* admin by construction.

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

## 2FA orientation

Aaron's direction for Phase 1: start orienting more deliberately toward 2FA as a strongly recommended thing — especially because some hubs in the Phase 1 use case (the rented Render box, the friend's hosted hub) will be reachable on the public internet, and password-only is a thin wall when `/login` is one IP-shaped form away from anyone on the planet.

**Phase 1 doesn't redesign 2FA primitives.** The hub already has TOTP support: `parachute auth 2fa enroll | disable | backup-codes` exists today (see [`parachute-hub/src/commands/auth.ts`](https://github.com/openparachute/parachute-hub/blob/main/src/commands/auth.ts) — the `VAULT_FORWARDED_SUBCOMMANDS` set forwards `2fa` to `parachute-vault`, which is the current TOTP storage). The post-exposure nudge already exists too: [`parachute-hub/src/commands/expose-2fa-warning.ts`](https://github.com/openparachute/parachute-hub/blob/main/src/commands/expose-2fa-warning.ts) prints a contextual warning after `parachute expose public` if vault's `config.yaml` doesn't carry a `totp_secret`. The primitive Phase 1 needs is per-user TOTP storage in `hub.db` (today's TOTP lives in vault's config and is implicitly the operator's, not per-user); the lift from there is incremental.

**For multi-user Phase 1:**

- 2FA is **optional but strongly recommended.** Not required.
- When the user is in the force-change-password flow on first sign-in, offer an inline 2FA enrollment step. Skippable, but with a clear "we recommend this — takes 30 seconds" framing in the page chrome. Re-uses the existing TOTP enroll surface (QR code + backup codes).
- After the user is signed in, the existing `/account/change-password` page broadens to `/account/security` (or a sidebar within the change-password page) that exposes "enable 2FA" / "regenerate backup codes" / "disable 2FA" as user-self-service actions. Same as the CLI surface, just web-shaped.

**Public-expose nudge (stronger when the hub is reachable from outside).** The hub already stores `setup_expose_mode` in `hub_settings` (`localhost` / `tailnet` / `public`). When the user lands on the inline 2FA step:

- `setup_expose_mode === "localhost"`: standard "recommended" framing. Skippable.
- `setup_expose_mode ∈ {"tailnet", "public"}`: stronger nudge. "This hub is reachable from outside your machine — anyone who guesses your password can sign in. We strongly recommend enabling 2FA." Still skippable in Phase 1 (forcing it would block the user from getting to their vault on first sign-in, which is the wrong tradeoff for a phase whose goal is "make onboarding work"), but the framing is prominent and the rationale is explicit.

The existing `printPublic2FAWarning` already takes the CLI-operator side of this: after `parachute expose public`, the *operator* sees a warning if 2FA isn't enrolled. The new Phase 1 surface takes the *user* side: every new user gets the same nudge on first sign-in, scaled to the hub's exposure posture.

**TOTP storage migration.** Today's `totp_secret` in vault's `config.yaml` is the operator's, by construction (vault is single-user). Multi-user Phase 1 means TOTP becomes per-user, which means it migrates into hub.db. The simplest shape: a new `users.totp_secret` column (nullable) + `users.totp_backup_codes` (nullable JSON array of hash-of-code strings) on migration v9 (or folded into v8 if PR 1 is still open). The existing operator TOTP gets migrated into the first-admin's row on the same migration; `parachute auth 2fa <op>` keeps working but now reads/writes the hub-db column instead of forwarding to vault. The vault-side TOTP code path retires once Phase 1 ships.

**Scope: do this in Phase 1 if it's small (one extra PR — call it PR 6 below); defer to a Phase 1.5 if the TOTP migration turns out to be more than ~200 LOC.** The principle is "don't ship multi-user without making 2FA the obvious next step on the path" — even if the actual code lands a release later, the design space here is committed.

**Phase 2 (future) — harder enforcement:**

- Admin setting: "require 2FA for all users on this hub." Default off in Phase 2; on by default in Phase 3 for `public`-mode hubs.
- Admin setting: "require 2FA for non-localhost expose modes." Once the hub flips to tailnet or public exposure, every user without 2FA enrolled gets force-redirected to enrollment on their next sign-in. Aaron flagged this as a candidate Phase 2 hardening; not Phase 1 because force-enrollment is a behavior change that needs the user-self-service profile page (Phase 2 work) to coexist cleanly.

The endgame is: the public-internet hub posture defaults to "2FA required for all users, password reset requires a backup code," and the operator opts *out* if they have a specific reason. Phase 1 plants the nudge; Phase 2 grows the enforcement lever; Phase 3 flips defaults.

## Sequencing — the implementation PR plan

The work splits into six PRs against `parachute-hub` (five for the multi-user foundation, plus an optional PR 6 for the 2FA enrollment surface — see scope note in the 2FA orientation section). Each is independently shippable. Dependency shape: PR 1 lands first (everyone depends on the schema + helpers). **PRs 2 and 3 both depend on PR 1 but can run in parallel** — PR 2 is the admin-creates-user surface, PR 3 is the force-change-password redirect; they touch independent code paths and don't conflict. PR 4 depends on PR 1 (for `assigned_vault`) but is independent of PRs 2 and 3 (the OAuth issuer change is read-only against the user row). PR 5 (verification) waits on PRs 1-4. PR 6 (if it lands in Phase 1) depends on PR 3 — the inline 2FA enrollment hangs off the change-password flow.

### PR 1 (small) — schema + helpers

**Touches:** `src/hub-db.ts`, `src/users.ts`, `src/__tests__/users.test.ts`.

- Migration v8: two `ALTER TABLE` + the wizard backfill.
- `User` interface + `rowToUser` carry the new fields.
- `createUser` accepts optional `assignedVault`.
- New `markPasswordChanged`, `setAssignedVault` helpers.
- Password validator helper enforcing the 12-char minimum (no complexity rules; no max length). Shared between `createUser`, the admin reset-password path, and the user-self-service change-password path so a single source of truth defines the rule.
- Username validator: enforces the 2-32 char + `[a-z0-9_-]` rule, refuses reserved words.
- Tests cover migration against a v7 fixture, helper happy paths, error paths, validator boundaries (11 chars rejected / 12 accepted; uppercase username rejected; reserved word rejected).

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
- `POST /account/change-password` — verify current, run new password through the PR-1 validator (12-char minimum), set new, flip the flag, redirect.
- Server-rendered page wires the 12-char minimum into the inline form-error rendering so the UX matches what the validator enforces.

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

### PR 6 (optional, small/medium) — inline 2FA enrollment on first sign-in

**Touches:** `src/account-change-password-ui.ts` (the surface PR 3 introduces), `src/users.ts` (new TOTP columns + helpers if not already in PR 1), `src/hub-db.ts` (migration v9 for per-user `totp_secret` + `totp_backup_codes`), `src/commands/auth.ts` (retire `VAULT_FORWARDED_SUBCOMMANDS.has("2fa")` — rewrite `parachute auth 2fa <enroll|disable|backup-codes>` to read/write hub.db instead of forwarding to `parachute-vault`), `src/commands/expose-2fa-warning.ts` (point `is2FAEnrolled` at the hub.db column for the first-admin row instead of probing vault's `config.yaml`; the `readVaultAuthStatus` helper retires once the migration completes), `src/__tests__/account-change-password.test.ts`, `src/__tests__/expose-2fa-warning.test.ts` (update fixtures from vault-config-yaml probing to hub.db reads).

- After the user submits a new password on `/account/change-password`, present an inline "set up 2FA — recommended" step (QR + backup codes) before redirecting to `next`.
- "Skip for now" link present and prominent.
- Strengthened framing when `setup_expose_mode ∈ {tailnet, public}` (see 2FA orientation section above for the exact copy beats).
- Re-uses the existing TOTP enroll logic; the migration moves operator-TOTP from vault's `config.yaml` into the first-admin's row on `users`.
- Out-of-band: the existing `parachute auth 2fa enroll | disable | backup-codes` CLI surface keeps working against hub.db once the migration completes (instead of vault's config.yaml).

**Scope gate:** if the TOTP migration alone exceeds ~200 LOC, split into a Phase 1.5 follow-up — the multi-user PR chain doesn't block on it. The point of including this option in the plan is to keep the door open for shipping the 2FA orientation in the same release wave, not to make it a hard prerequisite.
