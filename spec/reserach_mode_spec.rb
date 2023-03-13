# frozen_string_literal: true

num_retry = 3

RSpec.describe "Translate" do
  replacements = {
    "mode" => :replace,
    "{{TARGET_LANG}}" => "English"
  }

  translate = Translate.new(COMPLETION, replacements: replacements, research_mode: true, stream: true)
  translate.fulfill_placeholders
  turns_initial = translate.objectify["turns"].to_i

  input1 = "面白く読みやすい(readable)文章を書くことはとても難しい。"
  translate.wait.bind_research_mode(input1, num_retry: num_retry)
  input2 = "それでも鍛錬(practice)を続けるよりほかはない。"
  translate.wait.bind_research_mode(input2, num_retry: num_retry)
  input3 = "いつか熟練した(proficient)書き手になる日を夢見て。"
  translate.wait.bind_research_mode(input3, num_retry: num_retry)
  input4 = "読みやすく、面白い文章をたくさん読んで勉強するんだ。"
  translate.wait.bind_research_mode(input4, num_retry: num_retry)

  it "gives responses in json having certain properties" do
    expect(translate.wait.objectify.keys).to include "mode", "turns", "prompt", "response", "target_lang", "tokens"
  end

  it "gives as many responses as the number of prompts given" do
    expect(translate.wait.objectify["turns"].to_i).to eq turns_initial + 4
  end
end

RSpec.describe "Chat" do
  chat = Chat.new(COMPLETION, research_mode: true, stream: true)
  turns_initial = chat.objectify["turns"].to_i

  input1 = "What is the best place to visit in Texas?"
  chat.bind_research_mode(input1, num_retry: num_retry)
  input2 = "What do people say about the place?"
  chat.wait.bind_research_mode(input2, num_retry: num_retry)
  input3 = "How can I go there from Kansai, Japan?"
  chat.wait.bind_research_mode(input3, num_retry: num_retry)
  input4 = "By the way, are there any cities in Japan that have a sister city relationship with Texas cities?"
  chat.wait.bind_research_mode(input4, num_retry: num_retry)

  it "gives responses in json having certain properties" do
    expect(chat.wait.objectify.keys).to include "mode", "turns", "response", "language", "topics", "tokens"
  end

  it "gives as many responses as the number of prompts given" do
    expect(chat.wait.objectify["turns"].to_i).to eq turns_initial + 4
  end
end

RSpec.describe "MonadicChat:Novel" do
  novel = Novel.new(COMPLETION, research_mode: true, stream: true)
  turns_initial = novel.objectify["turns"].to_i

  input1 = "Tom woke up to the sound of pouring rain."
  novel.bind_research_mode(input1, num_retry: num_retry)
  input2 = "he decided to call his old friend first time in many years."
  novel.wait.bind_research_mode(input2, num_retry: num_retry)
  input3 = "the voice of the person the other end was an unfamilier one."
  novel.wait.bind_research_mode(input3, num_retry: num_retry)
  input4 = "it turned out that the person was my friend's son"
  novel.wait.bind_research_mode(input4, num_retry: num_retry)

  it "gives responses in json having certain properties" do
    expect(novel.wait.objectify.keys).to include "mode", "turns", "response", "tokens"
  end

  it "gives as many responses as the number of prompts given" do
    expect(novel.wait.objectify["turns"].to_i).to eq turns_initial + 4
  end
end

RSpec.describe "Code" do
  code = Code.new(COMPLETION, research_mode: true, stream: true)
  turns_initial = code.objectify["turns"].to_i

  input1 = "Write a command line app that shows the current global IP in Ruby."
  code.bind_research_mode(input1, num_retry: num_retry)
  input2 = "Make the code capable of showing the approximate geographical locatioin."
  code.wait.bind_research_mode(input2, num_retry: num_retry)
  input3 = "Add a usage example and a sample output to this code."
  code.wait.bind_research_mode(input3, num_retry: num_retry)
  input4 = "Write the same program using Python."
  code.wait.bind_research_mode(input4, num_retry: num_retry)

  it "gives responses in json having certain properties" do
    expect(code.wait.objectify.keys).to include "mode", "turns", "prompt", "response", "tokens"
  end

  it "gives as many responses as the number of prompts given" do
    expect(code.wait.objectify["turns"].to_i).to eq turns_initial + 4
  end
end
