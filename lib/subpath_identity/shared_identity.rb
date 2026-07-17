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
    FORMAT_VERSION = 1

    class << self
      # secret: the raw shared_session_secret value (any length string).
      # claims: must be a subset of SubpathIdentity.config.allowed_claims.
      def encode(secret, **claims)
        allowed = SubpathIdentity.config.allowed_claims
        unknown = claims.keys - allowed
        if unknown.any?
          raise ArgumentError, "SharedIdentity: #{unknown.inspect} not in allowed_claims (#{allowed.inspect})"
        end

        payload = SubpathIdentity.config.claim_defaults.merge(claims).merge(v: FORMAT_VERSION, iat: Time.now.to_i)
        encryptor(secret).encrypt_and_sign(payload.to_json, expires_in: SubpathIdentity.config.cookie_ttl)
      end

      # Returns a Hash with exactly the allowed_claims keys (defaults
      # filled in for anything missing), or nil if there's no valid
      # identity. Never raises.
      def decode(secret, cookie_value)
        return nil if cookie_value.blank?

        raw = JSON.parse(encryptor(secret).decrypt_and_verify(cookie_value), symbolize_names: true)
        # A message from a different FORMAT_VERSION isn't necessarily
        # shaped like this one — a legacy cookie encoded before this
        # field even existed has no `v` at all (nil, never equal to
        # FORMAT_VERSION), and a cookie from a newer version might carry
        # claims this version doesn't know how to interpret safely.
        # Reject rather than guess.
        return nil unless raw[:v] == FORMAT_VERSION

        SubpathIdentity.config.claim_defaults.merge(raw.slice(*SubpathIdentity.config.allowed_claims))
      rescue ActiveSupport::MessageEncryptor::InvalidMessage, JSON::ParserError, TypeError
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
