# frozen_string_literal: true

require "test_helper"

class SubpathIdentityTest < Minitest::Test
  def setup
    @previous_shared = ENV["SHARED_SESSION_SECRET"]
    @previous_worker = ENV["WORKER_SHARED_SECRET"]
  end

  def teardown
    ENV["SHARED_SESSION_SECRET"] = @previous_shared
    ENV["WORKER_SHARED_SECRET"] = @previous_worker
  end

  def test_require_secrets_raises_when_a_secret_is_missing_entirely
    ENV.delete("SHARED_SESSION_SECRET")
    ENV["WORKER_SHARED_SECRET"] = "present"

    error = assert_raises(RuntimeError) { SubpathIdentity.require_secrets! }
    assert_match(/SHARED_SESSION_SECRET/, error.message)
  end

  def test_require_secrets_raises_when_a_secret_is_present_but_blank
    ENV["SHARED_SESSION_SECRET"] = ""
    ENV["WORKER_SHARED_SECRET"] = "present"

    error = assert_raises(RuntimeError) { SubpathIdentity.require_secrets! }
    assert_match(/SHARED_SESSION_SECRET/, error.message)
  end

  def test_require_secrets_raises_when_a_secret_is_whitespace_only
    ENV["SHARED_SESSION_SECRET"] = "present"
    ENV["WORKER_SHARED_SECRET"] = " \t "

    error = assert_raises(RuntimeError) { SubpathIdentity.require_secrets! }
    assert_match(/WORKER_SHARED_SECRET/, error.message)
  end

  def test_require_secrets_passes_when_both_secrets_are_present_and_nonblank
    ENV["SHARED_SESSION_SECRET"] = "a-real-secret"
    ENV["WORKER_SHARED_SECRET"] = "another-real-secret"

    SubpathIdentity.require_secrets!
  end
end
