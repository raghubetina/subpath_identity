# frozen_string_literal: true

require "rails/railtie"

module SubpathIdentity
  class Railtie < ::Rails::Railtie
    # In development and test, ENV vars this gem needs are given a
    # known, insecure default rather than failing — there's no Worker in
    # front of a local `bin/rails server`, and tests need a fixed,
    # predictable secret to encode/decode against.
    #
    # SECRET_KEY_BASE_DUMMY: many Dockerfiles boot this same production
    # environment during `assets:precompile`, before any real runtime env
    # vars exist yet. Rails' own secret_key_base resolution already
    # treats that var as "this boot doesn't need real secrets" for
    # exactly that reason (see
    # Rails::Application::Configuration#secret_key_base) — this follows
    # the same signal.
    initializer "subpath_identity.local_secret_defaults", before: "subpath_identity.require_secrets" do
      if ::Rails.env.local? || ENV["SECRET_KEY_BASE_DUMMY"]
        config = SubpathIdentity.config
        ENV[config.shared_session_secret_env_var] ||= "dev-only-insecure-shared-session-secret"
        ENV[config.worker_shared_secret_env_var] ||= "dev-only-insecure-worker-secret"
      end
    end

    # Fails at boot, before serving a single request, if either secret is
    # missing outside development/test — the alternative is silently
    # trusting whatever ENV.fetch's caller does with a missing value,
    # which for a cross-app identity cookie or an origin-verification
    # header means every request accepting forgeable input.
    initializer "subpath_identity.require_secrets" do
      unless ::Rails.env.local? || ENV["SECRET_KEY_BASE_DUMMY"]
        config = SubpathIdentity.config
        [config.shared_session_secret_env_var, config.worker_shared_secret_env_var].each do |var|
          ENV.fetch(var) do
            raise "#{var} is not set. Refusing to boot #{::Rails.env} without it."
          end
        end
      end
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
