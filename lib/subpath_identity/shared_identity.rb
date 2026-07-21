# frozen_string_literal: true

require "active_support/message_encryptor"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/time/calculations"
require "active_support/core_ext/numeric/time"
require "digest"
require "json"

module SubpathIdentity
  # Encodes a small, explicitly allowlisted set of claims (see
  # SubpathIdentity.config.allowed_claims) into a single cookie that every
  # app sharing SHARED_SESSION_SECRET can read and write, independent of
  # each app's own session-signing secret (which stays private per
  # service). A decode failure — wrong secret, corrupted value, expired,
  # unknown format — always resolves to nil, never an exception, so a
  # problem with the shared cookie degrades one visitor's session instead
  # of taking an app down.
  module SharedIdentity
    # Bump this whenever a format change should invalidate already-issued
    # cookies. decode rejects anything whose v doesn't match, so bumping
    # is how you force every outstanding cookie to re-mint — no
    # SHARED_SESSION_SECRET rotation required. Version 1 was the original
    # format; 2 made a 24h expiry mandatory (the earliest v1 cookies had
    # no cryptographic expiry and would otherwise have stayed valid
    # forever under an unchanged secret); 3 made that expiry ABSOLUTE by
    # carrying it as an exp claim inside the payload — v2's expiry was
    # re-stamped on every re-encode, so any ordinary claim write (a
    # dark-mode toggle) silently renewed the whole identity's lifetime,
    # turning the TTL into an idle timeout any cookie holder could
    # extend forever.
    FORMAT_VERSION = 3

    class << self
      # secret: the raw shared_session_secret value (any length string).
      # claims: must be a subset of SubpathIdentity.config.allowed_claims.
      #
      # expires_at: the ABSOLUTE moment this identity dies, defaulting to
      # now + cookie_ttl. Callers re-encoding an existing identity (a
      # preference write) pass the deadline the current cookie already
      # carries — see ControllerHelpers#write_shared_identity — so that
      # rewriting a claim never extends the identity's life. Without
      # this, the TTL is an idle timeout: any holder of a valid cookie
      # (including a replayed copy, or a browser whose account was
      # closed) could keep it alive forever with an ordinary claim write.
      def encode(secret, expires_at: nil, **claims)
        allowed = SubpathIdentity.config.allowed_claims
        unknown = claims.keys - allowed
        if unknown.any?
          raise ArgumentError, "SharedIdentity: #{unknown.inspect} not in allowed_claims (#{allowed.inspect})"
        end

        deadline = expires_at || (Time.now + SubpathIdentity.config.cookie_ttl)
        payload = SubpathIdentity.config.claim_defaults.merge(claims)
          .merge(v: FORMAT_VERSION, iat: Time.now.to_i, exp: deadline.to_i)
        # expires_at on the encryptor AND exp in the payload: the
        # encryptor's own metadata enforces the deadline on decrypt, and
        # the payload copy is what lets decode hand the deadline back so
        # a re-encode can preserve it (encryptor metadata isn't exposed
        # to callers on decrypt).
        encryptor(secret).encrypt_and_sign(payload.to_json, expires_at: deadline)
      end

      # Returns a Hash with exactly the allowed_claims keys (defaults
      # filled in for anything missing), or nil if there's no valid
      # identity. Never raises.
      def decode(secret, cookie_value)
        return nil if cookie_value.blank?

        # decrypt_and_verify raises InvalidMessage on a wrong-secret or
        # corrupted cookie, but returns nil on an *expired* one (this
        # ActiveSupport version), so guard the nil explicitly rather than
        # feed it to JSON.parse.
        decrypted = encryptor(secret).decrypt_and_verify(cookie_value)
        return nil if decrypted.nil?

        raw = JSON.parse(decrypted, symbolize_names: true)
        # decrypt_and_verify only proves the payload was encrypted with
        # this key, not that it's the object shape we expect. JSON.parse
        # happily returns nil/true/false/a number/a string/an array for a
        # validly-encrypted-but-malformed cookie — which a buggy or
        # compromised writer that shares the key can produce — and raw[:v]
        # on a non-Hash would raise (NoMethodError for nil/true/false)
        # instead of degrading to "no identity." Check the shape first.
        return nil unless raw.is_a?(Hash)

        # A message from a different FORMAT_VERSION isn't necessarily
        # shaped like this one — a legacy cookie encoded before this
        # field even existed has no `v` at all (nil, never equal to
        # FORMAT_VERSION), and a cookie from a newer version might carry
        # claims this version doesn't know how to interpret safely.
        # Reject rather than guess.
        return nil unless raw[:v] == FORMAT_VERSION
        # Defense in depth alongside the encryptor's own expires_at
        # enforcement, and the source of the :_expires_at value below.
        return nil unless raw[:exp].is_a?(Integer) && Time.at(raw[:exp]) > Time.now

        # :_expires_at rides along (outside allowed_claims, stripped by
        # any re-encode's slice) so ControllerHelpers can preserve the
        # original absolute deadline when it rewrites a claim.
        SubpathIdentity.config.claim_defaults
          .merge(raw.slice(*SubpathIdentity.config.allowed_claims))
          .merge(_expires_at: Time.at(raw[:exp]))
      rescue ActiveSupport::MessageEncryptor::InvalidMessage, JSON::ParserError
        nil
      end

      private

      def encryptor(secret)
        # AES-256-GCM needs a 32-byte key; derive one from whatever length
        # secret we're given rather than requiring callers to size it exactly.
        key = Digest::SHA256.digest(secret)
        ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
      end
    end
  end
end
