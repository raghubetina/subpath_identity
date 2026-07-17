# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "subpath_identity"
require "action_controller"

require "minitest/autorun"

module TestConfig
  # Configures SubpathIdentity for the duration of a block, restoring
  # whatever was configured before once it's done — keeps tests that need
  # different allowed_claims/secrets from leaking into each other.
  def with_config
    previous = SubpathIdentity.config
    SubpathIdentity.reset_config!
    yield SubpathIdentity.config
  ensure
    SubpathIdentity.instance_variable_set(:@config, previous)
  end
end

Minitest::Test.include(TestConfig)
