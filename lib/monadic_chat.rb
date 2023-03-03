# frozen_string_literal: true

require_relative "monadic_chat/helper"

Thread.abort_on_exception = true

module MonadicChat
  class App
    attr_reader :template

    def initialize(params, template, placeholders, prop_accumulated, prop_newdata, update_proc)
      @responses = Thread::Queue.new
      @threads = Thread::Queue.new
      @cursor = TTY::Cursor
      @placeholders = placeholders
      @prop_accumulated = prop_accumulated
      @prop_newdata = prop_newdata
      @completion = nil
      @update_proc = update_proc
      @show_html = false
      @params_original = params
      @params = @params_original.dup
      @template_original = File.read(template)
      @method = OpenAI.model_to_method @params["model"]
      case @method
      when "completions"
        @template = @template_original.dup
      when "chat/completions"
        @template = JSON.parse @template_original
      end
    end

    def wait
      MonadicChat::TIMEOUT_SEC.times do |i|
        raise "Error: something went wrong" if i + 1 == MonadicChat::TIMEOUT_SEC
        break if @threads.empty?

        sleep 1
      end
      self
    end

    def reset
      @show_html = false
      @params = @params_original.dup

      case @method
      when "completions"
        @template = @template_original.dup
      when "chat/completions"
        @template = JSON.parse @template_2
      end

      @template = @template_original.dup
      if @placeholders.empty?
        print MonadicChat.prompt_system
        print " Context and parameters has been reset.\n"
      else
        fulfill_placeholders
      end
    end

    def objectify
      case @method
      when "completions"
        m = /\n\n```json\s*(\{.+\})\s*```\n\n/m.match(@template)
        json = m[1].gsub(/(?!\\\\\\)\\\\"/) { '\\\"' }
        JSON.parse(json)
      when "chat/completions"
        @template
      end
    end

    def format_data
      accumulated = +"## #{@prop_accumulated.split("_").map(&:capitalize).join(" ")}\n"
      contextual = +"## Contextual Data\n"

      newdata = ""
      objectify.each do |key, val|
        next if %w[prompt response].include? key

        if (@method == "completions" && key == @prop_accumulated) ||
           (@method == "chat/completions" && key == "messages")
          val = val.map do |v|
            if v.instance_of?(String)
              v.sub(/\s+###\s*$/m, "")
            else
              v.map { |role, text| "#{role}: #{text.sub(/\s+###\s*$/m, "")}" }
            end
          end
          accumulated << val.join("\n\n")
        elsif key == @prop_newdata
          newdata = "- **#{key.capitalize}**: #{val}\n"
        else
          contextual << "- **#{key.capitalize}**: #{val}\n"
        end
      end
      contextual << newdata

      h1 = self.class.name
      "# #{h1}\n\n#{contextual}\n#{accumulated}"
    end

    def show_data
      res = format_data
      print MonadicChat.prompt_system, "\n"
      print "\n#{TTY::Markdown.parse(res, indent: 0).strip}\n"
    end

    def set_html
      print MonadicChat.prompt_system
      print " HTML rendering is enabled\n"
      @show_html = true
      show_html
    end

    def show_html
      res = format_data.sub(/::(.+)?\b/) { " <span class='monadic_gray'>::</span> <span class='monadic_app'>#{Regexp.last_match(1)}</span>" }
                       .gsub("```") { "~~~" }
                       .gsub("User:") { "<span class='monadic_user'> User </span><br />" }
                       .gsub("GPT:") { "<span class='monadic_chat'> GPT </span><br />" }
      MonadicChat.add_to_html(res, TEMP_HTML)
    end

    def prepare_params(input)
      params = @params.dup
      case @method
      when "completions"
        template = @template.dup.sub("{{PROMPT}}", input).sub("{{MAX_TOKENS}}", (@params["max_tokens"] / 2).to_s)
        params["prompt"] = template
      when "chat/completions"
        @template["messages"] << { "role" => "user", "content" => input }
        params["messages"] = @template["messages"]
      end
      params
    end

    def update_template(res)
      updated = @update_proc.call(res)
      case @method
      when "completions"
        json = updated.to_json.strip
        @template.sub!(/\n\n```json.+```\n\n/m, "\n\n```json\n#{json}\n```\n\n")
      when "chat/completions"
        @template["messages"] << { "role" => "assistant", "content" => updated }
      end
    end

    def ask_retrial(input, message = nil)
      print MonadicChat.prompt_system
      print " Error: #{message.capitalize}\n" if message
      retrial = PROMPT_USER.select(" Do you want to try again?") do |menu|
        menu.choice "Yes", "yes"
        menu.choice "No", "no"
        menu.choice "Show current contextual data", "show"
      end
      case retrial
      when "yes"
        input
      when "no"
        textbox
      when "show"
        show_data
        ask_retrial(input)
      end
    end

    def save_data
      input = PROMPT_SYSTEM.ask(" Enter the path and file name of the saved data:\n")
      return if input.to_s == ""

      filepath = File.expand_path(input)
      dirname = File.dirname(filepath)

      unless Dir.exist? dirname
        print "Directory does not exist\n"
        save_data
      end

      if File.exist? filepath
        overwrite = PROMPT_SYSTEM.select(" #{filepath} already exists.\nOverwrite?") do |menu|
          menu.choice "Yes", "yes"
          menu.choice "No", "no"
        end
        return if overwrite == "no"
      end

      FileUtils.touch(filepath)
      unless File.exist? filepath
        print "File cannot be created\n"
        save_data
      end
      File.open(filepath, "w") do |f|
        m = /\n\n```json\s*(\{.+\})\s*```\n\n/m.match(@template)
        f.write JSON.pretty_generate(JSON.parse(m[1]))
        print "Data has been saved successfully\n"
      end
    end

    def load_data
      input = PROMPT_USER.ask(" Enter the path and file name of the saved data:\n")
      return false if input.to_s == ""

      filepath = File.expand_path(input)
      unless File.exist? filepath
        print "File does not exit\n"
        load_data
      end

      begin
        json = File.read(filepath)
        data = JSON.parse(json)
        raise if data["mode"] != self.class.name.downcase.split("::")[-1]
      rescue StandardError
        print "The data structure is not valid for this app\n"
        return false
      end

      new_template = @template.sub(/\n\n```json\s*\{.+\}\s*```\n\n/m, "\n\n```json\n#{JSON.pretty_generate(data).strip}\n```\n\n")
      print "Data has been loaded successfully\n"
      @template = new_template
      true
    end

    def change_parameter
      parameter = PROMPT_SYSTEM.select(" Select the parmeter to be set:",
                                       per_page: 7,
                                       cycle: true,
                                       show_help: :always,
                                       filter: true,
                                       default: 1) do |menu|
        menu.choice "#{BULLET} Cancel", "cancel"
        # menu.choice "#{BULLET} model: #{@params["model"]}", "model"
        menu.choice "#{BULLET} max_tokens: #{@params["max_tokens"]}", "max_tokens"
        menu.choice "#{BULLET} temperature: #{@params["temperature"]}", "temperature"
        menu.choice "#{BULLET} top_p: #{@params["top_p"]}", "top_p"
        menu.choice "#{BULLET} frequency_penalty: #{@params["frequency_penalty"]}", "frequency_penalty"
        menu.choice "#{BULLET} presence_penalty: #{@params["presence_penalty"]}", "presence_penalty"
      end
      return if parameter == "cancel"

      case parameter
      # when "model"
      #   value = change_model
      #   @method = OpenAI.model_to_method @params["value"]
      #   case @method
      #   when "completions"
      #     @template = @template_original.dup
      #   when "chat/completions"
      #     @template = JSON.parse @template_original
      #   end
      when "max_tokens"
        value = change_max_tokens
      when "temperature"
        value = change_temperature
      when "top_p"
        value = change_top_p
      when "frequency_penalty"
        value = change_frequency_penalty
      when "presence_penalty"
        value = change_presence_penalty
      end
      @params[parameter] = value if value
      puts "Parameter #{parameter} has been set to #{PASTEL.green(value)}" if value
    end

    def change_max_tokens
      PROMPT_SYSTEM.ask(" Set value of max tokens [1000 to 8000]", convert: :int) do |q|
        q.in "1000-8000"
        q.messages[:range?] = "Value out of expected range [1000 to 2048]"
      end
    end

    def change_temperature
      PROMPT_SYSTEM.ask(" Set value of temperature [0.0 to 1.0]", convert: :float) do |q|
        q.in "0.0-1.0"
        q.messages[:range?] = "Value out of expected range [0.0 to 1.0]"
      end
    end

    def change_top_p
      PROMPT_SYSTEM.ask(" Set value of top_p [0.0 to 1.0]", convert: :float) do |q|
        q.in "0.0-1.0"
        q.messages[:range?] = "Value out of expected range [0.0 to 1.0]"
      end
    end

    def change_frequency_penalty
      PROMPT_SYSTEM.ask(" Set value of frequency penalty [-2.0 to 2.0]", convert: :float) do |q|
        q.in "-2.0-2.0"
        q.messages[:range?] = "Value out of expected range [-2.0 to 2.0]"
      end
    end

    def change_presence_penalty
      PROMPT_SYSTEM.ask(" Set value of presence penalty [-2.0 to 2.0]", convert: :float) do |q|
        q.in "-2.0-2.0"
        q.messages[:range?] = "Value out of expected range [-2.0 to 2.0]"
      end
    end

    def change_model
      model = PROMPT_SYSTEM.select(" Select a model:",
                                   per_page: 10,
                                   cycle: false,
                                   show_help: :always,
                                   filter: true,
                                   default: 1) do |menu|
        menu.choice "#{BULLET} Cancel", "cancel"
        @completion.models.sort_by { |m| -m["created"] }.each do |m|
          menu.choice "#{BULLET} #{m["id"]}", m["id"]
        end
      end
      if model == "cancel"
        nil
      else
        model
      end
    end

    def show_params
      params_md = "# Current Parameter Values\n\n"
      @params.each do |key, val|
        next if /\A(?:prompt|stream|logprobs|echo|stop)\z/ =~ key

        params_md += "- #{key}: #{val}\n"
      end
      print MonadicChat.prompt_system, "\n"
      puts "#{TTY::Markdown.parse(params_md, indent: 0).strip}\n\n"
    end

    def show_help
      help_md = <<~HELP
        # List of Commands
        - **help**, **menu**, **commands**: show this help
        - **params**, **settings**, **config**: show and change values of parameters
        - **data**, **context**: show current contextual info
        - **html** : view contextual info on the default web browser
        - **reset**: reset context to original state
        - **save**: save current contextual info to file
        - **load**: load contextual info from file
        - **clear**, **clean**: clear screen
        - **bye**, **exit**, **quit**: go back to main menu
      HELP
      print MonadicChat.prompt_system
      print "\n#{TTY::Markdown.parse(help_md, indent: 0).strip}\n"
    end

    def count_lines_below
      screen_height = TTY::Screen.height
      vpos = Cursor.pos[:row]
      screen_height - vpos
    end

    def bind_and_unwrap2(input, num_retry: 0)
      print "\n"
      print MonadicChat.prompt_gpt, " "
      print @cursor.save
      unless @threads.empty?
        print @cursor.save
        message = PASTEL.red "Processing contextual data ... "
        print message
        MonadicChat::TIMEOUT_SEC.times do |i|
          raise "Error: something went wrong" if i + 1 == MonadicChat::TIMEOUT_SEC

          break if @threads.empty?

          sleep 1
        end
        print @cursor.restore
        print @cursor.clear_char(message.size)
      end

      params = prepare_params(input)
      print @cursor.save

      escaping = +""
      last_chunk = +""
      response = +""
      spinning = false
      res = @completion.run(params, num_retry: num_retry) do |chunk|
        if escaping
          chunk = escaping + chunk
          escaping = ""
        end

        if /(?:\\\z)/ =~ chunk
          escaping += chunk
          next
        else
          chunk = chunk.gsub('\\n', "\n")
          response << chunk
        end

        if count_lines_below > 3
          print MonadicChat::PASTEL.magenta(last_chunk)
        elsif !spinning
          print PASTEL.red " ... "
          spinning = true
        end

        # print MonadicChat::PASTEL.magenta(last_chunk)
        last_chunk = chunk
      end

      print @cursor.restore
      print @cursor.clear_screen_down
      print "#{TTY::Markdown.parse(response).strip}\n"

      update_template(res)
      show_html if @show_html
    end

    def bind_and_unwrap1(input, num_retry: 0)
      print "\n"
      print MonadicChat.prompt_gpt, " "
      unless @threads.empty?
        print @cursor.save
        message = PASTEL.red "Processing contextual data ... "
        print message
        MonadicChat::TIMEOUT_SEC.times do |i|
          raise "Error: something went wrong" if i + 1 == MonadicChat::TIMEOUT_SEC

          break if @threads.empty?

          sleep 1
        end
        print @cursor.restore
        print @cursor.clear_char(message.size)
      end

      params = prepare_params(input)
      print @cursor.save
      Thread.new do
        response_all_shown = false
        key_start = /"#{@prop_newdata}":\s*"/
        key_finish = /\s+###\s*"/m
        started = false
        escaping = +""
        last_chunk = +""
        finished = false
        @threads << true
        response = +""
        spinning = false
        res = @completion.run(params, num_retry: num_retry) do |chunk|
          if finished && !response_all_shown
            response_all_shown = true
            @responses << response.sub(/\s+###\s*".*/m, "")
            if spinning
              @cursor.backword(" ▹▹▹▹▹ ".size)
              @cursor.clear_char(" ▹▹▹▹▹ ".size)
            end
          end

          unless finished
            if escaping
              chunk = escaping + chunk
              escaping = ""
            end

            if /(?:\\\z)/ =~ chunk
              escaping += chunk
              next
            else
              chunk = chunk.gsub('\\n', "\n")
              response << chunk
            end

            if started && !finished
              if key_finish =~ response
                finished = true
              else
                if count_lines_below > 3
                  print MonadicChat::PASTEL.magenta(last_chunk)
                elsif !spinning
                  print PASTEL.red " ... "
                  spinning = true
                end
                last_chunk = chunk
              end
            elsif !started && !finished && key_start =~ response
              started = true
              response = +""
            end
          end
        end

        unless response_all_shown
          if spinning
            @cursor.backword(" ... ".size)
            @cursor.clear_char(" ... ".size)
          end
          @responses << response.sub(/\s+###\s*".*/m, "")
        end

        update_template(res)
        @threads.clear
        show_html if @show_html
      rescue StandardError => e
        @threads.clear
        @responses << "Error: something went wrong in a thread"
        pp e
      end

      loop do
        if @responses.empty?
          sleep 1
        else
          print @cursor.restore
          print @cursor.clear_screen_down
          text = @responses.pop
          text = text.gsub(/(?!\\\\)\\/) { "" }
          print "#{TTY::Markdown.parse(text).strip}\n"
          break
        end
      end
    end

    def confirm_query(input)
      if input.size < MIN_LENGTH
        print MonadicChat.prompt_system
        PROMPT_SYSTEM.yes?(" Would you like to proceed with this (very short) prompt?")
      else
        true
      end
    end

    def textbox(text = nil)
      print "\n"
      if text
        PROMPT_USER.ask(etxt)
      else
        PROMPT_USER.ask
      end
    end

    def parse(input = nil)
      return unless input

      loop do
        case input
        when /\A\s*(?:help|menu|commands?|\?|h)\s*\z/i
          show_help
        when /\A\s*(?:bye|exit|quit)\s*\z/i
          break
        when /\A\s*(?:reset)\s*\z/i
          reset
        when /\A\s*(?:data|context)\s*\z/i
          show_data
        when /\A\s*(?:html)\s*\z/i
          set_html
        when /\A\s*(?:save)\s*\z/i
          save_data
        when /\A\s*(?:load)\s*\z/i
          load_data
        when /\A\s*(?:clear|clean)\s*\z/i
          MonadicChat.clear_screen
        when /\A\s*(?:params?|parameters?|config|configuration)\s*\z/i
          change_parameter
        else
          if input && confirm_query(input)
            begin
              case @method
              when "completions"
                bind_and_unwrap1(input, num_retry: NUM_RETRY)
              when "chat/completions"
                bind_and_unwrap2(input, num_retry: NUM_RETRY)
              end
            rescue StandardError => e
              # SPINNER1.stop("")
              input = ask_retrial(input, e.message)
              next
            end
          end
        end
        input = textbox
      end
    end

    def fulfill_placeholders
      input = nil
      replacements = []
      mode = :replace

      @placeholders.each do |key, val|
        if key == "mode"
          mode = val
          next
        end

        input = if mode == :replace
                  val
                else
                  textbox(" #{val}:")
                end

        unless input
          replacements.clear
          break
        end
        replacements << [key, input]
      end
      if replacements.empty?
        false
      else
        replacements.each do |key, value|
          @template.gsub!(key, value)
        end
        true
      end
    end

    def run
      MonadicChat.banner(self.class.name, self.class::DESC, "cyan", "blue")
      show_help
      if @placeholders.empty?
        parse(textbox)
      else
        print MonadicChat.prompt_system
        loadfile = PROMPT_SYSTEM.select(" Load saved file?", default: 2) do |menu|
          menu.choice "Yes", "yes"
          menu.choice "No", "no"
        end
        parse(textbox) if loadfile == "yes" && load_data || fulfill_placeholders
      end
    end
  end
end
