# frozen_string_literal: true

module SubpathIdentity
  # One shared config object for every piece of this gem. There's exactly
  # one shared identity scheme per cluster of path-mounted apps, so a
  # global singleton (SubpathIdentity.config) is simpler than threading
  # config through every call site — the same reasoning Rails itself uses
  # for things like Rails.application.config.
  class Configuration
    # The complete set of claims that may ever appear in the shared
    # cookie. Adding one is a deliberate edit to this config, not
    # something any single app can do by just passing a new keyword —
    # SharedIdentity.encode raises on anything not listed here, and
    # .decode silently drops anything not listed here, even if some
    # other version (or a compromised relying party) wrote it.
    attr_accessor :allowed_claims

    # Default values merged in for any claim not present in a given
    # cookie — every claim in allowed_claims should have one, so decode
    # can always return a complete, predictable hash.
    attr_accessor :claim_defaults

    # How long a shared identity cookie stays valid, regardless of
    # SHARED_SESSION_SECRET rotation. Bounds how long a captured or
    # replayed cookie keeps working. Anything that re-signs the cookie
    # (login, logout, a profile edit) slides this forward in practice.
    attr_accessor :cookie_ttl

    # Env var names, not the secrets themselves — kept as names so the
    # Railtie can check presence at boot without the values ever passing
    # through this object.
    attr_accessor :shared_session_secret_env_var
    attr_accessor :worker_shared_secret_env_var

    # Paths RequireWorkerOrigin allows through without the Worker's
    # secret header, beyond its own built-in health-check exemption.
    # Needed by an identity provider's internal profile API, which is
    # called server-to-server and never goes through the Worker at all.
    attr_accessor :worker_origin_exempt_paths

    # The cookie's name. Rarely needs to change, but every place that
    # reads or writes it goes through this rather than a hardcoded
    # string, so changing it is a one-line edit.
    attr_accessor :cookie_name

    def initialize
      @allowed_claims = []
      @claim_defaults = {}
      @cookie_ttl = 24 * 60 * 60
      @shared_session_secret_env_var = "SHARED_SESSION_SECRET"
      @worker_shared_secret_env_var = "WORKER_SHARED_SECRET"
      @worker_origin_exempt_paths = []
      @cookie_name = :_shared_identity
    end

    def shared_session_secret
      ENV.fetch(shared_session_secret_env_var)
    end

    def worker_shared_secret
      ENV.fetch(worker_shared_secret_env_var)
    end
  end
end
