# SubpathIdentity

Share a little bit of identity across independently deployed Rails apps that all live under one domain by path (`mydomain.com/app1`, `mydomain.com/app2`), routed by an edge router (Cloudflare Worker, nginx, etc.) rather than subdomains.

These apps don't share a database, a session store, or a deploy. What they can share is a small, encrypted, explicitly allowlisted cookie — this gem is that cookie, plus a way for each app's origin to verify a request actually came through the shared router instead of being sent directly to a public origin URL.

This gem is deliberately narrow: it's the mechanism, not a design. It doesn't decide who's allowed to write the cookie, doesn't run your auth, and doesn't pick which app owns which claims. See [`subpath_identity-provider`](https://github.com/raghubetina/subpath_identity-provider) if one app in your cluster is the identity owner (running Rodauth, Devise, etc.), and [`subpath_identity-client`](https://github.com/raghubetina/subpath_identity-client) for the apps that read from it.

## Installation

```bash
bundle add subpath_identity
```

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

## What this gem doesn't do

- Doesn't run authentication. `SubpathIdentity::ControllerHelpers#write_shared_identity` is the primitive; deciding when to call it (after a real login, not just because a request has a plausible-looking cookie) is the calling app's job. See `subpath_identity-provider` for a Rodauth-oriented pattern.
- Doesn't stop another app in the cluster from writing the cookie. Every app that has `SHARED_SESSION_SECRET` can call `SharedIdentity.encode` — that's necessary for something as simple as a shared dark-mode toggle, but it means the cookie is a *display* credential, not an authorization one. Gate anything that mutates real data behind your actual auth session (Rodauth's, Devise's, whatever it is), not `signed_in?`.
- Doesn't handle the "two apps mint two different `user_id`s for the same person" problem. Have one identity-owning app, and have every other app treat its `user_id` as the only one that exists.

## Development

`bin/setup`, then `bundle exec rake test`. `bundle exec standardrb` for style.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/raghubetina/subpath_identity.

## License

MIT.
