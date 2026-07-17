# frozen_string_literal: true

require "active_support/security_utils"
require "active_support/core_ext/object/blank"

module SubpathIdentity
  # The Worker is supposed to be the only thing talking to these apps'
  # origins directly — but a Render/Fly/etc. origin is typically still a
  # public URL, and anyone who knows the hostname can send a request
  # straight to it, skipping the Worker entirely, with X-Forwarded-Host
  # set to whatever they want. The Worker attaches a shared secret header
  # (HEADER) on every request it forwards; RequireWorkerOrigin rejects
  # anything else before the app does anything with the request.
  module OriginSecret
    HEADER = "X-Worker-Secret"

    class << self
      # expected: the raw worker_shared_secret value.
      # provided: whatever arrived in the X-Worker-Secret header, or nil.
      def valid?(expected, provided)
        return false if provided.blank?

        ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      end
    end
  end
end
