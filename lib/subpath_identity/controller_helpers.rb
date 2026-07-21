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

    # The current identity's absolute deadline (a Time), or nil when
    # there's no valid identity. Kept separate from
    # current_shared_identity so that Hash keeps its exact-allowed-claims
    # contract (and can round-trip into write_shared_identity).
    def shared_identity_expires_at
      @shared_identity_expires_at
    end

    # Merges new claims over the current identity and re-signs the
    # cookie — so writing one claim (e.g. toggling a preference) doesn't
    # clobber others (e.g. sign the visitor out).
    #
    # The identity's ABSOLUTE deadline is preserved across ordinary
    # writes: while a signed-in identity exists, its original deadline
    # (shared_identity_expires_at) is carried into the new cookie, so a
    # preference toggle never extends the identity's life — without
    # this, the TTL is an idle timeout that any cookie holder (a
    # replayed copy, a browser whose account was since closed) could
    # renew forever.
    #
    # renew_lifetime: true mints a fresh now + cookie_ttl window. Pass
    # it ONLY from an action backed by the identity owner's real
    # authentication — a login or signup hook (see
    # subpath_identity-provider's README) — never from a relying party
    # or an unauthenticated preference write. When there's no signed-in
    # identity to preserve (an anonymous preferences-only cookie, or a
    # first sign-in), a fresh window is minted regardless.
    def write_shared_identity(renew_lifetime: false, **claims)
      config = SubpathIdentity.config
      deadline =
        unless renew_lifetime
          shared_identity_expires_at if current_shared_identity[:user_id].present?
        end
      deadline ||= Time.now + config.cookie_ttl
      merged = current_shared_identity.merge(claims).slice(*config.allowed_claims)
      cookies[config.cookie_name] = {
        value: SharedIdentity.encode(config.shared_session_secret, expires_at: deadline, **merged),
        path: "/",
        # Same guard as RequireWorkerOrigin#allowed?: a partially-loaded
        # Rails (the bare module without a booted application) defines
        # ::Rails but not .env.
        secure: defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env.production?,
        httponly: true,
        same_site: :lax
      }
      # Update the in-request memo to what was just written — exactly as
      # clear_shared_identity already did. Without this, two writes in
      # one request (say a relying party's cache-key reissue in a
      # before_action, then the action's own preference toggle) each
      # merge over the identity that ARRIVED on the request, and the
      # second write's cookie silently discards the first's claims.
      @current_shared_identity = merged
      @shared_identity_expires_at = deadline
    end

    # Deletes the shared identity cookie and drops the in-request memo
    # back to the anonymous defaults, so signed_in? / current_shared_identity
    # read as signed-out for the rest of this request too, not just the
    # next one. The counterpart to write_shared_identity: for when
    # something downstream determines the identity this cookie asserts is
    # no longer valid (e.g. a relying party learns from the provider that
    # the account was closed — see subpath_identity-client's
    # SyncLocalProfile). Because the cookie is Path=/, this signs the
    # account out across every app in the cluster on its next request.
    def clear_shared_identity
      cookies.delete(SubpathIdentity.config.cookie_name, path: "/")
      @current_shared_identity = SubpathIdentity.config.claim_defaults
      @shared_identity_expires_at = nil
    end

    private

    def load_shared_identity
      config = SubpathIdentity.config
      claims, expires_at = SharedIdentity.decode_with_expiry(
        config.shared_session_secret, cookies[config.cookie_name]
      )
      @current_shared_identity = claims || config.claim_defaults
      @shared_identity_expires_at = expires_at
    end
  end
end
