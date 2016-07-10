require 'slack'
require "slack_timeline/version"

module SlackTimeline
  class << self
    attr_accessor :token
  end

  class JobQueue
    def initialize(jobs, thread_size = 3)
      @job_queue = Queue.new
      @jobs = jobs
      @thread_size = thread_size
    end

    def run(&block)
      enum = @jobs.each_slice((@jobs.size/@thread_size) + 1)
      enum.each do |sliced_jobs|
        Thread.start do
          begin
            sliced_jobs.each { |job| block.call(job) if block }
          rescue => e
            puts e.message
            puts e.backtrace
          ensure
            @job_queue << true
          end
        end
      end

      enum.size.times { @job_queue.pop  }
    end
  end

  class Bot

    attr_reader :thread_count

    def initialize(channel_to_post, thread_count = 4)
      @channel_to_post = channel_to_post
      @thread_count = thread_count
      @job_queue = []
      @message_queue = Queue.new
      @oldest_timestamps = {}
    end 

    def client
      @client ||= init_client
    end

    def run
      main_loop
    end

    private

    def main_loop
      loop do
        JobQueue.new(init_job_queue, 3).run do |channel|
          enqueue_histories(channel)
        end
        resolve_messages
      end
    end

    def init_job_queue
      channels.select { |c| times_channel_filter(c) }[0..2]
    end

    def times_channel_filter(channel)
      channel.name.start_with?('times_')
    end

    def enqueue_histories(channel)
      histories = client.channels_history( channel: channel.id, oldest: oldest_timestamp(channel) || 0).messages
      histories.select { |h| h.type == 'message' }.each do |message|
        @message_queue << message
      end
      oldest_timestamp(channel, histories.first.ts)
    end

    def oldest_timestamp(channel, ts = nil)
      if ts
        @oldest_timestamps[channel.id] = ts
      else
        @oldest_timestamps[channel.id]
      end
    end

    def resolve_messages
      messages = []
      while !@message_queue.empty?
        msg = @message_queue.pop
        messages << msg
      end

      messages.sort { |m| m.ts.to_f }.each do |m|
        user = users.find { |u| u.id == m.user }
        attachment = m.attachments ? JSON.generate(m.attachments) : nil
        client.chat_postMessage(
          channel: channel_id_to_post,
          text: m.text,
          username: user.name,
          icon_url: user.profile.image_72,
          attachments: attachment
        )
      end
    end

    def users
      @users ||= client.users_list.members
    end

    def channels
      client.channels_list.channels.reject(&:is_archived)
    end

    def channel_id_to_post
      @channel_id_to_post ||= channels.find { |c| c.name == @channel_to_post }.id
    end

    def init_client
      token = ENV['SLACK_TOKEN'] || ::SlackTimeline.token || raise
      Slack.configure do |config|
        config.token = token
      end

      Slack::Web::Client.new
    end
  end
end
