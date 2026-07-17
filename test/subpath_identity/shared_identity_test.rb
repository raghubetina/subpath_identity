# frozen_string_literal: true

require "test_helper"

class SharedIdentityTest < Minitest::Test
  SECRET = "test-secret-value"

  def setup
    SubpathIdentity.configure do |c|
      c.allowed_claims = %i[user_id cache_key dark_mode locale]
      c.claim_defaults = {user_id: nil, cache_key: nil, dark_mode: false, locale: "en"}
    end
  end

  def teardown
    SubpathIdentity.reset_config!
  end

  def test_round_trips_allowed_claims
    token = SubpathIdentity::SharedIdentity.encode(SECRET, user_id: 1, cache_key: "accounts/1-v1", dark_mode: true, locale: "fr")
    decoded = SubpathIdentity::SharedIdentity.decode(SECRET, token)

    assert_equal 1, decoded[:user_id]
    assert_equal "accounts/1-v1", decoded[:cache_key]
    assert_equal true, decoded[:dark_mode]
    assert_equal "fr", decoded[:locale]
  end

  def test_decode_fills_in_defaults_for_claims_not_present
    token = SubpathIdentity::SharedIdentity.encode(SECRET, user_id: 1)
    decoded = SubpathIdentity::SharedIdentity.decode(SECRET, token)

    assert_equal false, decoded[:dark_mode]
    assert_equal "en", decoded[:locale]
    assert_nil decoded[:cache_key]
  end

  def test_encode_raises_on_a_claim_outside_the_allowlist
    assert_raises(ArgumentError) do
      SubpathIdentity::SharedIdentity.encode(SECRET, user_id: 1, password: "nope")
    end
  end

  def test_decode_returns_nil_for_a_blank_cookie_value
    assert_nil SubpathIdentity::SharedIdentity.decode(SECRET, nil)
    assert_nil SubpathIdentity::SharedIdentity.decode(SECRET, "")
  end

  def test_decode_returns_nil_for_a_value_signed_with_a_different_secret
    token = SubpathIdentity::SharedIdentity.encode(SECRET, user_id: 1)

    assert_nil SubpathIdentity::SharedIdentity.decode("a-completely-different-secret", token)
  end

  def test_decode_returns_nil_for_a_corrupted_or_unrecognized_value
    assert_nil SubpathIdentity::SharedIdentity.decode(SECRET, "not-a-real-token")
  end

  def test_decode_returns_nil_once_the_token_is_past_its_ttl
    SubpathIdentity.config.cookie_ttl = 0
    token = SubpathIdentity::SharedIdentity.encode(SECRET, user_id: 1)
    sleep 0.01

    assert_nil SubpathIdentity::SharedIdentity.decode(SECRET, token)
  end

  def test_decode_silently_drops_claims_outside_the_allowlist_even_if_present_in_the_payload
    key = Digest::SHA256.digest(SECRET)
    encryptor = ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
    payload = {user_id: 1, admin: true, v: SubpathIdentity::SharedIdentity::FORMAT_VERSION}.to_json
    token = encryptor.encrypt_and_sign(payload, expires_in: SubpathIdentity.config.cookie_ttl)

    decoded = SubpathIdentity::SharedIdentity.decode(SECRET, token)

    assert_equal 1, decoded[:user_id]
    refute decoded.key?(:admin)
  end

  def test_configuration_is_isolated_per_app_not_hardcoded
    with_config do |c|
      c.allowed_claims = %i[account_id]
      c.claim_defaults = {account_id: nil}

      token = SubpathIdentity::SharedIdentity.encode(SECRET, account_id: 42)
      decoded = SubpathIdentity::SharedIdentity.decode(SECRET, token)

      assert_equal 42, decoded[:account_id]
      refute decoded.key?(:user_id)
    end
  end
end
