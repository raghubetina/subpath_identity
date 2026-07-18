## [Unreleased]

## [0.2.0] - 2026-07-18

- **Cookie wire format is now v2** (`SharedIdentity::FORMAT_VERSION`), and `decode` rejects any other version. Every v1 cookie is invalidated on upgrade — no `SHARED_SESSION_SECRET` rotation needed, but users re-authenticate once. This is why apps sharing the cookie must move to 0.2.0 together; a v1 and a v2 app can't read each other's cookies.
- `decode` now returns `nil` (never raises) for a validly-encrypted-but-non-object payload — `null`, `true`, `false`, a number, a string, or an array. Previously a `null`/`true`/`false` payload raised `NoMethodError`.
- `require_secrets!` now rejects a secret shorter than `MINIMUM_SECRET_LENGTH` (32), not only a blank one — a one-character `SHARED_SESSION_SECRET` derives a brute-forceable AES key.
- Added `ControllerHelpers#clear_shared_identity` — deletes the cookie and resets the in-request identity to signed-out.
- Boot guard now uses `Rails.env.development? || .test?` instead of `Rails.env.local?`, so the declared Rails 7.0 floor actually works (`local?` only means dev-or-test as of 7.1).

## [0.1.0] - 2026-07-16

- Initial release
