## [Unreleased]

## [0.5.2] - 2026-07-22

- Trust-model correction (docs only; no code change). The section claimed that gating mutations behind your real auth session "keeps the damage to display/PII rather than data changes." That's only true when the identity owner and relying parties are on **separate origins**. On **one shared origin** (path-based routing under a single hostname), it is false: a compromised relying party's same-origin script can ride a logged-in visitor's real session straight through the auth check and mutate data in their browser — the check authorizes it because the session is genuine. The Trust model now states this conditionally, and notes that asymmetric issuance closes only the forge-and-read vector, not the browser-authority one — an untrusted relying party needs both a verify-only credential *and* its own origin. Surfaced by an adversarial review of the path-based reference deployment, where the identity owner and relying parties share one hostname.

## [0.5.1] - 2026-07-21

- Doc fix: `ControllerHelpers#shared_identity_expires_at` returns `nil` when there's no valid shared cookie, not when `signed_in?` is false — an anonymous preferences-only cookie has a deadline and returns it. Behavior unchanged; the contract now matches it, with a regression test.

## [0.5.0] - 2026-07-21

- **`write_shared_identity` now updates the in-request identity** (`current_shared_identity` and the deadline), exactly as `clear_shared_identity` already did. Previously two writes in one request each merged over the identity that arrived on the request and the second write's cookie silently discarded the first's claims — e.g. a relying party's cache-key reissue in a `before_action` wiped out by the action's own dark-mode toggle.
- **`decode` honors its exact-claims contract again**: it returns a Hash with exactly the configured `allowed_claims` keys (0.4.0 leaked an internal `:_expires_at` key, which also broke `encode(secret, **decode(secret, token))` round-trips). The identity's absolute deadline moved to the new `SharedIdentity.decode_with_expiry(secret, value)` → `[claims, expires_at]`, and to a new `ControllerHelpers#shared_identity_expires_at` reader. Wire format is unchanged (still v3).
- **Rollout note for the v2→v3 wire change (0.4.0), which this release inherits:** independently deployed services cannot upgrade atomically — during the deploy window (or a stuck/rolled-back service), old apps read new cookies as signed-out and vice versa, and an old-side preference write can replace a new-format cookie with an old-format one. For a demo cluster this is a brief signed-out blip healed by the next login. For a deployment with real users, do a two-phase migration instead: first ship a reader that accepts both versions to every service (deriving the v2 deadline as `iat + cookie_ttl` so it doesn't become a sliding lease again) while writers keep emitting v2; once every service reads both, flip writers to v3; drop v2 reading after `cookie_ttl` has elapsed.


## [0.4.0] - 2026-07-21

- **The cookie's expiry is now absolute, and the wire format is v3.** v2 re-stamped a fresh `expires_in` on every re-encode, so any ordinary claim write (a relying party's dark-mode toggle) silently renewed the whole identity's lifetime — the documented "24h bound on a captured cookie" was really an idle timeout any cookie holder could extend forever, including for an account closed since. v3 carries the deadline as an `exp` claim: `write_shared_identity` preserves the existing identity's deadline across ordinary writes and only mints a fresh window when there's no signed-in identity or when the caller passes the new `renew_lifetime: true` (pass it only from actions backed by the identity owner's real authentication — login/signup hooks). `decode` enforces `exp` (alongside the encryptor's own metadata) and exposes it as `:_expires_at`. All outstanding v2 cookies are invalidated on upgrade; users re-authenticate once.
- `required_ruby_version` raised to `>= 3.3`, and CI now runs the declared floor against the committed lockfile. The lock pins `parallel 2.1.0`, whose own floor is Ruby 3.3 — so the previously declared 3.2 couldn't even `bundle install` from a fresh clone.

## [0.3.1] - 2026-07-18

- Declared floors raised to what CI actually tests: `activesupport`/`railties >= 8.1`, `rack >= 3.0`. Rails 7 support was inherited from scaffolding defaults, never a deliberate commitment; rather than carry a 7.0 compatibility matrix for a version the maintainer will never run, the claim now matches the tested toolchain. (The short-lived `gemfiles/rails_7.gemfile` floor job added after 0.3.0 is removed; the portable `rack/mock` test require stays — it works on every Rack.)

## [0.3.0] - 2026-07-18

- **`SECRET_KEY_BASE_DUMMY` no longer skips the secret guard.** It's Rails' build-only asset-precompile flag; honoring it as "no real secrets needed" meant a serving process that inherited the flag (set on the image or runtime env rather than a single build `RUN`) would boot with the public `dev-only-insecure-*` defaults — a forgeable worker header and forgeable identity cookies. The guard now runs on every non-development/test boot, asset compilation included. **Upgrade note:** your image build's `assets:precompile` step must now supply throwaway `SHARED_SESSION_SECRET` and `WORKER_SHARED_SECRET` values alongside `SECRET_KEY_BASE_DUMMY`, since the gem no longer falls open (see the demo's Dockerfile).

## [0.2.0] - 2026-07-18

- **Cookie wire format is now v2** (`SharedIdentity::FORMAT_VERSION`), and `decode` rejects any other version. Every v1 cookie is invalidated on upgrade — no `SHARED_SESSION_SECRET` rotation needed, but users re-authenticate once. This is why apps sharing the cookie must move to 0.2.0 together; a v1 and a v2 app can't read each other's cookies.
- `decode` now returns `nil` (never raises) for a validly-encrypted-but-non-object payload — `null`, `true`, `false`, a number, a string, or an array. Previously a `null`/`true`/`false` payload raised `NoMethodError`.
- `require_secrets!` now rejects a secret shorter than `MINIMUM_SECRET_LENGTH` (32), not only a blank one — a one-character `SHARED_SESSION_SECRET` derives a brute-forceable AES key.
- Added `ControllerHelpers#clear_shared_identity` — deletes the cookie and resets the in-request identity to signed-out.
- Boot guard now uses `Rails.env.development? || .test?` instead of `Rails.env.local?`, so the declared Rails 7.0 floor actually works (`local?` only means dev-or-test as of 7.1).

## [0.1.0] - 2026-07-16

- Initial release
