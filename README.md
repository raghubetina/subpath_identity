# SubpathIdentity

Share a little bit of identity across independently deployed Rails apps that all live under one domain by path (`mydomain.com/app1`, `mydomain.com/app2`), routed by an edge router (Cloudflare Worker, nginx, etc.) rather than subdomains.

These apps don't share a database, a session store, or a deploy. What they can share is a small, encrypted, explicitly allowlisted cookie — this gem is that cookie, plus a way for each app's origin to verify a request actually came through the shared router instead of being sent directly to a public origin URL.

This gem is deliberately narrow: it's the mechanism, not a design. It doesn't decide who's allowed to write the cookie, doesn't run your auth, and doesn't pick which app owns which claims. See [`subpath_identity-provider`](https://github.com/raghubetina/subpath_identity-provider) if one app in your cluster is the identity owner (running Rodauth, Devise, etc.), and [`subpath_identity-client`](https://github.com/raghubetina/subpath_identity-client) for the apps that read from it.

## Installation

Not yet released to RubyGems, so install from GitHub — pin a tag for a
reproducible build:

```ruby
# Gemfile
gem "subpath_identity", github: "raghubetina/subpath_identity", tag: "v0.3.1"
```

(Once it's published, `bundle add subpath_identity` will be the one-liner;
until then `bundle add` can't resolve it.)

## Setup

Two environment variables, on every app that shares the cookie:

- `SHARED_SESSION_SECRET` — signs the identity cookie. The same value on every app; separate from each app's own `SECRET_KEY_BASE`, which stays private per app and signs that app's own session/CSRF only.
- `WORKER_SHARED_SECRET` — the header your edge router attaches on every request it forwards, and that `RequireWorkerOrigin` middleware checks for. Also shared across apps, but unrelated to `SHARED_SESSION_SECRET` — one proves identity to the browser, the other proves a request came through the router.

In development and test, both fall back to a fixed, insecure value automatically — there's no router in front of `bin/rails server`, and tests need something deterministic to encode/decode against. In every other environment, the app refuses to boot if either is missing, rather than silently running with no way to verify anything.

Configure the claims your cookie carries — this is application-specific, so the gem doesn't guess:

```ruby
# config/initializers/subpath_identity.rb
SubpathIdentity.configure do |config|
  config.allowed_claims = %i[user_id cache_key dark_mode locale]
  config.claim_defaults = {user_id: nil, cache_key: nil, dark_mode: false, locale: "en"}
end
```

`allowed_claims` is a closed list on purpose. `SharedIdentity.encode` raises on anything not in it; `.decode` silently drops anything not in it, even a claim a newer version of some other app in the cluster wrote. Keep it to small values that are genuinely the same everywhere — identity, theme, locale. Anything bigger (a cart, per-app state) doesn't belong in a cookie; use a shared datastore with a reference token in the cookie instead.

If your app is a relying party that only ever *reads* the shared identity another app owns — never mints a `user_id` of its own — tell `RequireWorkerOrigin` to let that app's internal profile API through even though it's called server-to-server and never goes through the router:

```ruby
SubpathIdentity.configure do |config|
  config.worker_origin_exempt_paths = ["/internal/me"]
end
```

Every app not exposing an endpoint like that can skip this — the default is `[]`.

## What you get

`ApplicationController`:

```ruby
class ApplicationController < ActionController::Base
  include SubpathIdentity::ControllerHelpers
end
```

gives you:

- `current_shared_identity` — a Hash with exactly your configured `allowed_claims` keys, defaults filled in for anything the cookie didn't have. Never `nil`.
- `signed_in?` — `current_shared_identity[:user_id].present?`.
- `write_shared_identity(**claims)` — merges the given claims over the current identity and re-signs the cookie, so writing one claim (toggling a theme, say) doesn't clobber the others (like signing someone out).

Every app in the cluster automatically runs `RequireWorkerOrigin` — no wiring needed beyond the Gemfile entry, it's registered via a Railtie. A request missing or mismatching the `X-Worker-Secret` header gets a `403`, before it reaches any controller, any other middleware your app installs, or an authentication gem's own routing (this matters specifically because some auth gems — Rodauth is one — answer their own routes from middleware and never reach a Rails controller at all, so a `before_action` can't protect them; this has to run ahead of everything).

## Trust model

Read this before adopting the gem — it's the security property you're buying into, not a footnote.

The shared cookie is **symmetric**: it's authenticated encryption keyed on `SHARED_SESSION_SECRET`, and every app that holds the secret can both *read* and *mint* it. That coupling is inherent to symmetric cryptography — the read key is the write key — so any app you let read the identity can also forge one. There is no configuration that separates "verify" from "mint" here, because HMAC/symmetric schemes fundamentally can't.

**This gem therefore assumes every app sharing the secret is mutually trusted** — a cluster one operator owns and deploys, not subpaths rented to third parties. If one of those apps is compromised, it can mint a cookie asserting any `user_id` (impersonating a *display* identity anywhere the cookie is read) and read that account's data from an identity owner's internal API. Gating every real mutation behind your actual auth session rather than `signed_in?` (see below) keeps the damage to display/PII rather than data changes — but it does not remove it. That's the accepted cost of a shared secret.

**If you need relying parties you don't fully trust** — another team's app, a tenant, anything third-party — this mechanism is not enough, by design. Make the identity owner the sole *issuer*: either root-signed tokens (owner holds a private key; relying parties get a verify-only public key) or opaque provider-issued tokens resolved by introspection, and move client-writable preferences (a theme toggle, say) to a separate cookie so relying parties never need mint capability at all. Both are real design changes, not flags. Note the honest limit of even those: a compromised relying party still sees the identity and PII of its *own* visitors, who hand it the credential just by loading a page — the asymmetric upgrade stops the *escalation* (forging identities for users who never visited it), not that.

## What this gem doesn't do

- Doesn't run authentication. `SubpathIdentity::ControllerHelpers#write_shared_identity` is the primitive; deciding when to call it (after a real login, not just because a request has a plausible-looking cookie) is the calling app's job. See `subpath_identity-provider` for a Rodauth-oriented pattern.
- Doesn't stop another app in the cluster from writing the cookie — that's the symmetric trust model above, not a bug. The cookie is a *display* credential, not an authorization one: gate anything that mutates real data behind your actual auth session (Rodauth's, Devise's, whatever it is), not `signed_in?`.
- Doesn't handle the "two apps mint two different `user_id`s for the same person" problem. Have one identity-owning app, and have every other app treat its `user_id` as the only one that exists.

## Development

`bin/setup`, then `bundle exec rake test`. `bundle exec standardrb` for style.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/raghubetina/subpath_identity.

## License

MIT.
