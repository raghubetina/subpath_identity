## [Unreleased]

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
