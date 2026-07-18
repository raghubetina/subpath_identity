# frozen_string_literal: true

require "rails/railtie"

module SubpathIdentity
  class Railtie < ::Rails::Railtie
    # In development and test only, the ENV vars this gem needs are given
    # a known, insecure default rather than failing — there's no router
    # in front of a local `bin/rails server`, and tests need a fixed,
    # predictable secret to encode/decode against.
    #
    # Note what is deliberately NOT here: SECRET_KEY_BASE_DUMMY. That's
    # Rails' build-only signal for `assets:precompile`, meant for a single
    # Docker RUN, and an earlier version of this gem treated it as "skip
    # the secret guard" too. But a build flag that leaks into a *serving*
    # process (set on the image or the runtime env instead of one RUN)
    # would then boot production with these public defaults — a forgeable
    # worker header and forgeable identity cookies. So the guard now stays
    # active for every non-development/test boot, asset compilation
    # included; the build step must supply its own throwaway
    # SHARED_SESSION_SECRET / WORKER_SHARED_SECRET (see the demo's
    # Dockerfile) rather than rely on the gem to fall open.
    #
    # development? || test?, not Rails.env.local? — local? only means
    # "development or test" as of Rails 7.1. On 7.0 (which this gem's
    # railties >= 7.0 floor still allows) StringInquirer reads it as
    # "is the env literally named 'local'?", which is false in a normal
    # dev/test boot. Spelling it out works on every supported version.
    initializer "subpath_identity.local_secret_defaults", before: "subpath_identity.require_secrets" do
      if ::Rails.env.development? || ::Rails.env.test?
        config = SubpathIdentity.config
        ENV[config.shared_session_secret_env_var] ||= "dev-only-insecure-shared-session-secret"
        ENV[config.worker_shared_secret_env_var] ||= "dev-only-insecure-worker-secret"
      end
    end

    # Fails at boot, before serving a single request, if either secret is
    # missing or too short outside development/test — the alternative is
    # silently trusting whatever ENV.fetch's caller does with a missing
    # value, which for a cross-app identity cookie or an origin-
    # verification header means every request accepting forgeable input.
    initializer "subpath_identity.require_secrets" do
      SubpathIdentity.require_secrets! unless ::Rails.env.development? || ::Rails.env.test?
    end

    # Unshifted, not inserted relative to another middleware — unshift
    # always lands at position 0 of whatever the stack looks like when
    # this operation is actually replayed (Rails records middleware
    # operations from every Railtie and replays them in registration
    # order during the finisher), so this ends up first regardless of
    # what order Railties initialize in.
    initializer "subpath_identity.middleware" do |app|
      app.middleware.unshift SubpathIdentity::RequireWorkerOrigin
    end
  end
end
