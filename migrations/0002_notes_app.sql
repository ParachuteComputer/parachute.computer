-- Migration 0002 — notes_app column
--
-- Adds the optional "what do you take notes in today?" user-research signal
-- collected by the landing-page interest form (2026-07-02 team-direction
-- landing page). One of a small known set: apple-notes | notion | obsidian |
-- paper | nothing. NULL when the visitor skips the question (it's optional).
--
-- Additive + nullable, so the existing deployed Worker keeps working until
-- the updated worker/subscribe.ts is redeployed. Apply this BEFORE deploying
-- the new Worker (the standard order in DEPLOY-subscribe.md):
--   npx wrangler d1 migrations apply parachute-interests --remote
--   npx wrangler deploy

ALTER TABLE interests ADD COLUMN notes_app TEXT;
