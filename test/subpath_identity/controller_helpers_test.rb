# frozen_string_literal: true

require "test_helper"

class ControllerHelpersTest < Minitest::Test
  class FakeController < ActionController::Base
    include SubpathIdentity::ControllerHelpers

    def index
      head :ok
    end
  end

  def setup
    SubpathIdentity.configure do |c|
      c.allowed_claims = %i[user_id dark_mode]
      c.claim_defaults = {user_id: nil, dark_mode: false}
      c.cookie_name = :_shared_identity
    end
    @previous_secret = ENV["SHARED_SESSION_SECRET"]
    ENV["SHARED_SESSION_SECRET"] = "a-test-secret-long-enough-to-pass-the-floor"
  end

  def teardown
    SubpathIdentity.reset_config!
    ENV["SHARED_SESSION_SECRET"] = @previous_secret
  end

  def build_controller
    controller = FakeController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.response = ActionDispatch::TestResponse.new
    controller
  end

  def test_clear_shared_identity_deletes_the_cookie_and_resets_the_in_request_identity
    controller = build_controller
    # cookies is private on ActionController::Base — reach it with send.
    controller.send(:cookies)[:_shared_identity] = "some-encoded-token"
    # Stand in for what load_shared_identity would have memoized on a
    # real request — a signed-in identity.
    controller.instance_variable_set(:@current_shared_identity, {user_id: 42, dark_mode: true})
    assert controller.signed_in?

    controller.clear_shared_identity

    refute controller.signed_in?, "should read as signed out for the rest of this request"
    assert_equal SubpathIdentity.config.claim_defaults, controller.current_shared_identity
    assert_nil controller.send(:cookies)[:_shared_identity], "the cookie should be deleted"
  end

  # Regression for the renewable-lease bug: an ordinary claim write (a
  # dark-mode toggle) must carry the identity's ORIGINAL absolute
  # deadline into the new cookie, not stamp a fresh now + cookie_ttl —
  # otherwise any cookie holder can keep a replayed or closed-account
  # identity alive forever by toggling a preference before expiry.
  def test_an_ordinary_write_preserves_the_identitys_absolute_deadline
    original_deadline = Time.now + 300
    controller = build_controller
    controller.instance_variable_set(
      :@current_shared_identity,
      {user_id: 42, dark_mode: false, _expires_at: original_deadline}
    )

    controller.write_shared_identity(dark_mode: true)

    decoded = SubpathIdentity::SharedIdentity.decode(
      ENV["SHARED_SESSION_SECRET"], controller.send(:cookies)[:_shared_identity]
    )
    assert_equal 42, decoded[:user_id]
    assert_equal true, decoded[:dark_mode]
    assert_equal original_deadline.to_i, decoded[:_expires_at].to_i,
      "the rewrite must not extend the identity's life"
  end

  def test_renew_lifetime_true_mints_a_fresh_absolute_deadline
    stale_deadline = Time.now + 300
    controller = build_controller
    controller.instance_variable_set(
      :@current_shared_identity,
      {user_id: 42, dark_mode: false, _expires_at: stale_deadline}
    )

    controller.write_shared_identity(renew_lifetime: true, user_id: 42)

    decoded = SubpathIdentity::SharedIdentity.decode(
      ENV["SHARED_SESSION_SECRET"], controller.send(:cookies)[:_shared_identity]
    )
    assert_in_delta (Time.now + SubpathIdentity.config.cookie_ttl).to_i, decoded[:_expires_at].to_i, 5
    assert decoded[:_expires_at] > stale_deadline, "a real auth event mints a new window"
  end

  def test_a_write_with_no_signed_in_identity_mints_a_fresh_deadline
    controller = build_controller
    controller.instance_variable_set(
      :@current_shared_identity,
      SubpathIdentity.config.claim_defaults
    )

    controller.write_shared_identity(dark_mode: true)

    decoded = SubpathIdentity::SharedIdentity.decode(
      ENV["SHARED_SESSION_SECRET"], controller.send(:cookies)[:_shared_identity]
    )
    assert_in_delta (Time.now + SubpathIdentity.config.cookie_ttl).to_i, decoded[:_expires_at].to_i, 5
  end
end
