# frozen_string_literal: true

require "active_support/concern"

module SubpathIdentity
  # Include in ApplicationController. Loads the shared identity on every
  # request, and gives controllers current_shared_identity, signed_in?,
  # and write_shared_identity — the read/write primitives every app
  # sharing this cookie needs, regardless of what else it does.
  #
  # Deliberately minimal: convenience readers for specific claims (e.g. a
  # dark_mode? or locale helper) are an app's own opinion about its own
  # configured claims, not something this gem should decide for you —
  # define them locally against current_shared_identity[:whatever].
  module ControllerHelpers
    extend ActiveSupport::Concern

    included do
      before_action :load_shared_identity
      helper_method :current_shared_identity, :signed_in? if respond_to?(:helper_method)
    end

    def current_shared_identity
      @current_shared_identity
    end

    def signed_in?
      current_shared_identity[:user_id].present?
    end

    # Merges new claims over the current identity and re-signs the
    # cookie — so writing one claim (e.g. toggling a preference) doesn't
    # clobber others (e.g. sign the visitor out).
    def write_shared_identity(**claims)
      config = SubpathIdentity.config
      merged = current_shared_identity.merge(claims).slice(*config.allowed_claims)
      cookies[config.cookie_name] = {
        value: SharedIdentity.encode(config.shared_session_secret, **merged),
        path: "/",
        secure: Rails.env.production?,
        httponly: true,
        same_site: :lax
      }
    end

    private

    def load_shared_identity
      config = SubpathIdentity.config
      @current_shared_identity =
        SharedIdentity.decode(config.shared_session_secret, cookies[config.cookie_name]) || config.claim_defaults
    end
  end
end
