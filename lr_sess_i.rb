#!/usr/bin/env ruby
# coding: utf-8

# LOAD_PATH for htmlentitiesライブラリ
# htmlentities see: http://d.hatena.ne.jp/japanrock_pg/20100316/1268732145
$LOAD_PATH.unshift(File.dirname(__FILE__) + '/htmlentities-4.2.0/lib/')

require 'rubygems'
require 'oauth'
require 'json'
require 'hpricot'
require 'open-uri'
require 'yaml'
require 'parsedate'
require "kconv"
require 'htmlentities'
require File.dirname(__FILE__) + '/twitter_oauth'

# Usage:
#  1. このファイルやディレクトリを同じディレクトリに配置します。
#   * twitter_oauth.rb
#   * http://github.com/japanrock/TwitterTools/blob/master/twitter_oauth.rb
#   * sercret_key.yml
#   * http://github.com/japanrock/TwitterTools/blob/master/secret_keys.yml.example
#   * htmlentities-4.2.0/ ディレクトリ
#   * http://github.com/japanrock/TwitterLR_ImpressionOfCompanyIntroduction/tree/master/htmlentities-4.2.0/
#  2. このファイルを実行します。
#   ruby twitter_bot.rb

# フィードを扱う基本クラス
class Feed
  attr_reader :publisheds
  attr_reader :titles
  attr_reader :summaries
  attr_reader :links
  attr_reader :entry_ids
  
  def initialize
    @publisheds = []
    @titles     = []
    @summaries  = []
    @links      = []
    @entry_ids  = []
  end

  def header
    ''
  end

  private
  # フィードをHpricotのオブジェクトにします。
  def open_feed(feed_name = '')
    Hpricot(open(base_url + feed_name))
  end

  def make_elems(feed)
   self
  end
end

# ライブレボリューションの会社説明会の感想のフィードを扱うクラス
class LrSessI < Feed
  def base_url
    "http://rec.live-revolution.co.jp"
  end

  def feed
    make_elems(open_feed("/xml/each_feed.xml"))
  end

  # Hpricotのオブジェクトから各インスタンス変数に配列としてセットします。
  # @all_publishdesには時間
  # @all_titlesにはタイトル
  # @all_linksにはリンクURL
  def make_elems(feed)
    if feed.class == Hpricot::Doc
      (feed/'entry'/'published').each do |published|
        @publisheds << published.inner_html
      end

      (feed/'entry'/'title').each do |title|
        title = HTMLEntities.new.decode(title.inner_html) 
        title = condition_max_num(title, 'title')
        @titles << title
      end

      (feed/'entry'/'summary').each do |summary|
        summary = HTMLEntities.new.decode(summary.inner_html)
        summary = cut_html_tag(summary)
        summary = cut_line_break(summary)
        summary = condition_max_num(summary, 'summary')
        @summaries << summary
      end

      (feed/'entry'/'link').each do |link|
        @links << link.attributes['href']
      end   

      (feed/'entry'/'id').each do |entry_id|
        @entry_ids << entry_id.inner_html
      end

      # 古いものからTwieetするため
      @publisheds.reverse!
      @titles.reverse!
      @summaries.reverse!
      @links.reverse!
      @entry_ids.reverse!
    end

    self
  end

  # 一度につぶやく最大数
  def tweet_count
    2
  end

  private

  # 改行カット
  def cut_line_break(str)
    str.gsub(/\r\n|\r|\n/, '')
  end

  # HTMLタグをカット
  def cut_html_tag(str)
    str.gsub(/<\/?[^>]*>/, '')
  end

  # str文字数がxxxx_max_numを越えていたら、
  # 末尾にmore_markを付与してxxxx_max_num以内に収める
  def condition_max_num(str, kind = 'summary')
   case kind
    when 'summary'
      if utf8_string_count(str) > summary_max_num
        str = str.split(//u)[0..summary_max_num - more_mark.size - 1].join + more_mark
      end
    when 'title'
      str = str.scan(/（.*.）/).join # （）内のみ取り出す
      str = str.gsub(/（|）/ , '') #（）を削除する

      if utf8_string_count(str) > title_max_num 
        str =  str.split(//u)[0..title_max_num - more_mark.size - 1].join + more_mark
      end
    end

   str
  end

  def utf8_string_count(str)
    str.split(//u).length
  end

  def summary_max_num
    80
  end

  def title_max_num
    30
  end

  def more_mark
    "..."
  end
end

class TweetHistory
  def initialize
    @tweet_histories = []

    File.open(File.dirname(__FILE__) + '/tweet_history') do |file|
      while line = file.gets
       @tweet_histories << line.chomp
      end
    end
  end

  # tweet_historyファイルにエントリーIDを書き込む
  def write(entry_id)
    tweet_history = File.open(File.dirname(__FILE__) + '/tweet_history', 'a+')
    tweet_history.puts entry_id
    tweet_history.close
  end

  # 過去にポストしたエントリーIDかを確認する
  def past_in_the_tweet?(entry_id)
    @tweet_histories.each do |tweet_history|
       return true if tweet_history == entry_id
    end

    false
  end

  def maintenance
    tweet_histories = []

    File.open(File.dirname(__FILE__) + '/tweet_history') do |file|
      while line = file.gets
       tweet_histories << line.chomp
      end
    end
    
    if tweet_histories.size > stay_history_count
      # 保持する履歴のみを配列に取得
      stay_tweet_histories = []
      stay_number = stay_history_count

      tweet_histories.reverse!.each_with_index do |history, index|
        if index <= stay_history_count
          stay_number = stay_number - 1
          stay_tweet_histories << history
        end
      end

      # File Reset
      tweet_history = File.open(File.dirname(__FILE__) + '/tweet_history', 'w')
      tweet_history.print ''
      tweet_history.close
      
      # stay_history_count行のみ保存
      tweet_history = File.open(File.dirname(__FILE__) + '/tweet_history', 'a+')

      stay_tweet_histories.reverse!.each do |history|
        tweet_history.puts history
      end

      tweet_history.close
    end
  end

  private

  def stay_history_count
    2000
  end
end


twitter_oauth = TwitterOauth.new
tweet_history = TweetHistory.new

# LrSessI Feed Post
lr_sess_i = LrSessI.new
lr_sess_i.feed

tweet_count = 0
lr_sess_i.titles.each_with_index do |title, index|
  entry_id = lr_sess_i.entry_ids[index]

  # tweet(136文字前後) => summary(80文字以内) + " - "(3文字) + title(30文字以内) + " - "(3文字) + link(20文字前後) 
  tweet = lr_sess_i.summaries[index] + " - " + lr_sess_i.titles[index] + " - " + lr_sess_i.links[index]

  unless tweet_history.past_in_the_tweet?(entry_id)
    twitter_oauth.post(tweet)

    if twitter_oauth.response_success?
      tweet_history.write(entry_id)
      tweet_count = tweet_count + 1
    end
  end

  break if tweet_count == lr_sess_i.tweet_count
end

# tweet_historyファイルの肥大化防止
tweet_history = TweetHistory.new
tweet_history.maintenance
