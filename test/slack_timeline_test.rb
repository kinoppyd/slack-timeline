require 'test_helper'

class SlackTimelineTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::SlackTimeline::VERSION
  end

  def test_set_configure_slack_token
    test_token = 'test token'
    SlackTimeline.token = test_token

    assert_equal(test_token, SlackTimeline.token)

    SlackTimeline.token = nil
  end
end
