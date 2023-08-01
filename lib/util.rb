module Logging
	module_function

	require 'logger'

  @loggers = {}

  def logger

    classname = self.class.name
    methodname = caller[0][/`([^']*)'/, 1]
    @logger ||= Logging.logger_for(classname, methodname)
    @logger.progname = "#{classname}\##{methodname}"
    @logger

  end

  class << self

    def get_log_level

      test = Logger::DEBUG
      test

    end

    def logger_for(classname, methodname)

      @loggers[classname] ||= configure_logger_for(classname, methodname)

    end

    def configure_logger_for(classname, methodname)

      current_date = Time.now.strftime('%Y-%m-%d')
      log_file = File.join(LOG_DIR, "monadic_chat_cli-#{current_date}.log")
      logger = Logger.new(log_file, LOG_MAX_FILES, LOG_MAX_SIZE)
      logger.level = get_log_level
      logger

    end

  end

end


LOG_DIR = File.join(File.expand_path("../../", __FILE__), "logs")
LOG_LEVEL = Logger::DEBUG
LOG_MAX_SIZE = 6145728
LOG_MAX_FILES = 10
