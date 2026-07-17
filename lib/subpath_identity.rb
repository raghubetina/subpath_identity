# frozen_string_literal: true

require_relative "subpath_identity/version"
require_relative "subpath_identity/configuration"
require_relative "subpath_identity/shared_identity"
require_relative "subpath_identity/origin_secret"
require_relative "subpath_identity/require_worker_origin"
require_relative "subpath_identity/controller_helpers"
require_relative "subpath_identity/railtie" if defined?(Rails::Railtie)

# Path-based multi-app deployments (mydomain.com/app1, mydomain.com/app2,
# each an independently deployed service behind one edge router) need a
# way to share a little bit of identity across apps that don't share a
# database, a session store, or a deploy — this is that mechanism: a
# small, explicitly allowlisted, encrypted cookie every app can read and
# write, plus a way for each app's origin to verify a request actually
# came through the shared edge router rather than being sent directly to
# a public origin URL.
#
# See SubpathIdentity.configure for the required setup.
module SubpathIdentity
  class Error < StandardError; end

  class << self
    def configure
      yield config
    end

    def config
      @config ||= Configuration.new
    end

    # Mostly useful for tests — resets configuration between examples so
    # one test's SubpathIdentity.configure block can't leak into another.
    def reset_config!
      @config = Configuration.new
    end

    # Called from the Railtie's boot-time initializer. Split out so it's
    # testable without booting a full Rails::Application. A present-but-
    # blank value is rejected, not just a missing one — ENV.fetch alone
    # would accept "", and an empty shared session secret derives a
    # publicly-known SHA256 key (Digest::SHA256.digest("")), making every
    # identity cookie forgeable by anyone.
    def require_secrets!
      [config.shared_session_secret_env_var, config.worker_shared_secret_env_var].each do |var|
        if ENV[var].to_s.empty?
          raise "#{var} is not set. Refusing to boot without it."
        end
      end
    end
  end
end
