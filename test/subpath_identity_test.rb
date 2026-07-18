# frozen_string_literal: true

require "test_helper"

class SubpathIdentityTest < Minitest::Test
  # Long enough to clear MINIMUM_SECRET_LENGTH — the point under test in
  # most of these is the OTHER variable, so this one has to pass.
  VALID_SECRET = "0123456789abcdef0123456789abcdef0123"

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
    ENV["WORKER_SHARED_SECRET"] = VALID_SECRET

    error = assert_raises(RuntimeError) { SubpathIdentity.require_secrets! }
    assert_match(/SHARED_SESSION_SECRET is not set/, error.message)
  end

  def test_require_secrets_raises_when_a_secret_is_present_but_blank
    ENV["SHARED_SESSION_SECRET"] = ""
    ENV["WORKER_SHARED_SECRET"] = VALID_SECRET

    error = assert_raises(RuntimeError) { SubpathIdentity.require_secrets! }
    assert_match(/SHARED_SESSION_SECRET is not set/, error.message)
  end

  def test_require_secrets_raises_when_a_secret_is_whitespace_only
    ENV["SHARED_SESSION_SECRET"] = VALID_SECRET
    ENV["WORKER_SHARED_SECRET"] = " \t "

    error = assert_raises(RuntimeError) { SubpathIdentity.require_secrets! }
    assert_match(/WORKER_SHARED_SECRET is not set/, error.message)
  end

  def test_require_secrets_raises_on_a_one_character_secret
    ENV["SHARED_SESSION_SECRET"] = "x"
    ENV["WORKER_SHARED_SECRET"] = VALID_SECRET

    error = assert_raises(RuntimeError) { SubpathIdentity.require_secrets! }
    assert_match(/SHARED_SESSION_SECRET is only 1 characters/, error.message)
  end

  def test_require_secrets_raises_on_a_short_dictionary_like_secret
    ENV["SHARED_SESSION_SECRET"] = VALID_SECRET
    ENV["WORKER_SHARED_SECRET"] = "changeme"

    error = assert_raises(RuntimeError) { SubpathIdentity.require_secrets! }
    assert_match(/WORKER_SHARED_SECRET is only 8 characters/, error.message)
  end

  def test_require_secrets_raises_just_below_the_minimum_length
    ENV["SHARED_SESSION_SECRET"] = "a" * (SubpathIdentity::MINIMUM_SECRET_LENGTH - 1)
    ENV["WORKER_SHARED_SECRET"] = VALID_SECRET

    assert_raises(RuntimeError) { SubpathIdentity.require_secrets! }
  end

  def test_require_secrets_passes_at_exactly_the_minimum_length
    ENV["SHARED_SESSION_SECRET"] = "a" * SubpathIdentity::MINIMUM_SECRET_LENGTH
    ENV["WORKER_SHARED_SECRET"] = "b" * SubpathIdentity::MINIMUM_SECRET_LENGTH

    SubpathIdentity.require_secrets!
  end

  def test_require_secrets_passes_when_both_secrets_are_present_and_long_enough
    ENV["SHARED_SESSION_SECRET"] = VALID_SECRET
    ENV["WORKER_SHARED_SECRET"] = VALID_SECRET.reverse

    SubpathIdentity.require_secrets!
  end
end
