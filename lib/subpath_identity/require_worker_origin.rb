# frozen_string_literal: true

require "rack/request"

module SubpathIdentity
  # Rack middleware, not a controller before_action — it has to run ahead
  # of anything else that might handle a request before it reaches a
  # controller. An identity provider running Rodauth (or Devise, or
  # anything else that installs its own middleware) is a real example:
  # those gems' own login/logout routes are answered by their middleware
  # directly and never reach a Rails controller at all, so a
  # before_action can't protect them. This is registered by
  # SubpathIdentity::Railtie unshifted onto the middleware stack ahead of
  # everything, in every app that requires this gem.
  #
  # exempt_paths (SubpathIdentity.config.worker_origin_exempt_paths) is
  # read fresh on every request rather than captured once at
  # initialization — Rails initializer ordering between this gem's
  # Railtie and an app's own config/initializers/*.rb (where an app would
  # set worker_origin_exempt_paths) isn't something this middleware
  # should have to depend on getting right.
  class RequireWorkerOrigin
    HEALTH_CHECK_PATH = "/up"

    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) if allowed?(env)

      [403, {"Content-Type" => "text/plain; charset=utf-8"}, ["Forbidden\n"]]
    end

    private

    def allowed?(env)
      return true if defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env.development?

      request = Rack::Request.new(env)
      exempt_paths = [HEALTH_CHECK_PATH, *SubpathIdentity.config.worker_origin_exempt_paths]
      return true if exempt_paths.include?(request.path_info)

      OriginSecret.valid?(SubpathIdentity.config.worker_shared_secret, request.get_header("HTTP_#{header_env_key}"))
    end

    def header_env_key
      OriginSecret::HEADER.upcase.tr("-", "_")
    end
  end
end
