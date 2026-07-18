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

  # Boot-guard floor for SHARED_SESSION_SECRET / WORKER_SHARED_SECRET.
  # Not real entropy enforcement (a 32-character "aaaa..." would pass) —
  # a smoke detector for the realistic accident: a hand-typed "changeme",
  # a truncated paste, or a dev default leaking to production. These are
  # secrets this gem invents and is the sole reader of, and that the
  # operator must create by hand (unlike Rails' own generated
  # SECRET_KEY_BASE), so nothing else would ever catch a weak one. Every
  # standard generator clears this floor (openssl rand -hex 32 -> 64
  # chars, SecureRandom.hex(16) -> 32, base64(32) -> 44), so it has no
  # false positives against a real secret. See require_secrets!.
  MINIMUM_SECRET_LENGTH = 32

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
    # testable without booting a full Rails::Application.
    #
    # Rejects both a missing/blank value and one shorter than
    # MINIMUM_SECRET_LENGTH. ENV.fetch alone would accept "" (and
    # a whitespace-only string, which .strip reduces to empty); an empty
    # shared session secret derives a publicly-known SHA256 key
    # (Digest::SHA256.digest("")), and a one-character one is
    # brute-forceable offline from a single captured cookie, since
    # AES-GCM authentication reveals when a guessed key is right. Either
    # way, forgeable by anyone.
    def require_secrets!
      [config.shared_session_secret_env_var, config.worker_shared_secret_env_var].each do |var|
        value = ENV[var].to_s.strip
        if value.empty?
          raise "#{var} is not set. Refusing to boot without it."
        elsif value.length < MINIMUM_SECRET_LENGTH
          raise "#{var} is only #{value.length} characters. Refusing to boot with a secret " \
            "shorter than #{MINIMUM_SECRET_LENGTH} — it derives an AES key, and a single captured " \
            "cookie makes a short one brute-forceable offline. Generate one with `openssl rand -hex 32`."
        end
      end
    end
  end
end
