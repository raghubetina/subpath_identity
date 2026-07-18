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
  end

  def teardown
    SubpathIdentity.reset_config!
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
end
