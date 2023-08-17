require "logger"

module Minitest
  module Dispatch
    class Logger < ::Logger
      LOG_LEVELS = %i[error warn info debug].freeze

      class << self
        def instance
          return @logger unless @instance.nil?

          @logger = Logger.new($stdout)
          # @logger.level = Logger::INFO
          @logger.level = ENV["LOG_LEVEL"] || Logger::INFO
          @logger.formatter = proc do |severity, datetime, _progname, msg|
            "#{severity}: [#{datetime.utc}] #{msg}\n"
          end
          @logger
        end

        LOG_LEVELS.each do |level|
          define_method(level.to_sym) do |msg|
            begin
              instance.send(level.to_sym, msg)
            rescue
              puts "#{level.upcase}: [#{Time.now.utc}] #{msg}"
            end
          end
        end
      end
    end
  end
end
