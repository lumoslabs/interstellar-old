require 'rest-client'
require 'json'
require 'date'
require 'csv'
require 'yaml'

CONFIG = YAML.load_file('./secrets/secrets.yml')
datefile = './lastdate'
default_days_back = 7

class Slack
  def self.notify(message)
    RestClient.post CONFIG['slack_url'], {
      payload: message.to_json
    },
    content_type: :json,
    accept: :json
  end
end

class Review
  @@ratings = Array.new(5, 0)

  def self.collection
    @collection ||= []
  end

  def self.send_reviews_from_date(date, datefile)
    messages = collection.select do |r|
      r.submitted_at && r.submitted_at > date && (@@ratings[r.rate - 1] += 1) && (r.title || r.text) && r.lang == 'en'
    end.sort_by do |r|
      r.submitted_at
    end.map do |r|
      r.build_message
    end

    ratings_sum = @@ratings.reduce(:+)
    if ratings_sum > 0
      Slack.notify({
        text: [
          "#{ratings_sum} new Play Store #{ratings_sum == 1 ? 'rating' : 'ratings'}!",
          @@ratings.map.with_index{ |x, i| '★' * (i + 1) + '☆' * (4 - i) + " #{x}" }.reverse,
          "#{(@@ratings.map.with_index{ |x, i| x * (i + 1) }.reduce(:+).to_f / ratings_sum).round(3)} average rating\n",
          "#{messages.length} new Play Store #{messages.length == 1 ? 'review' : 'reviews'}!"
        ].join("\n"),
        attachments: messages
      })
      IO.write(datefile, collection.max_by(&:submitted_at).submitted_at.to_time.to_i)
    else
      print "No new reviews\n"
    end
  end

  attr_accessor :text, :title, :submitted_at, :original_submitted_at, :rate, :device, :url, :version, :edited, :lang

  def initialize data = {}
    @text = data[:text] ? data[:text] : nil
    @title = data[:title] ? data[:title] : nil

    begin
      @submitted_at = DateTime.parse(data[:submitted_at])
    rescue ArgumentError
    end
    begin
      @original_submitted_at = DateTime.parse(data[:original_submitted_at])
    rescue ArgumentError
    end
    @rate = data[:rate].to_i
    @device = data[:device] ? data[:device] : nil
    @url = data[:url]
    @version = data[:version] ? "v#{data[:version]}" : nil
    @edited = data[:edited]
    @lang = data[:lang]
  end

  def build_message
    colors = ['danger', '#D4542C', 'warning', '#8BA24B', 'good']
    date = if edited
             "#{original_submitted_at.strftime('%Y.%m.%d at %H:%M')}, edited on #{submitted_at.strftime('%Y.%m.%d at %H:%M')}"
           else
             "#{submitted_at.strftime('%Y.%m.%d at %H:%M')}"
           end

    stars = '★' * rate + '☆' * (5 - rate)
    for_version = version ? "for #{version} " : ''

    {
      fallback: [
        stars,
        title,
        text,
        "#{for_version}using #{device} on #{date}",
        url
      ].join("\n"),
      color: colors[rate - 1],
      author_name: stars,
      title: title,
      title_link: url,
      text: [
        text,
        "_#{for_version}using #{device} on #{date}_ · <#{url}|Permalink>"
      ].join("\n"),
      mrkdwn_in: ['text']
    }
  end
end

start_date = [Time.at(File.exists?(datefile) ? IO.read(datefile).to_i : 0).to_datetime, Date.today.to_datetime - default_days_back + Rational(4, 24)].max

system 'gsutil/gsutil update'
system 'BOTO_PATH=./secrets/.boto gsutil/gsutil cp gs://play_public/supported_devices.csv .'

csv_file_names = []
date = start_date
while date <= Date.today
  file_date = date.strftime('%Y%m')
  csv_file_name = "reviews_#{CONFIG["package_name"]}_#{file_date}.csv"
  if system "BOTO_PATH=./secrets/.boto gsutil/gsutil cp -r gs://#{CONFIG["app_repo"]}/reviews/#{csv_file_name} ."
    csv_file_names.push(csv_file_name)
  end
  date = date - date.day + 1 >> 1
end

device = Hash.new
CSV.foreach('supported_devices.csv', encoding: 'bom|utf-16le:utf-8', headers: true) do |row|
  device[row['Device']] = row['Model'] || row['Device'] if row['Device']
end

csv_file_names.each do |csv_file_name|
  CSV.foreach(csv_file_name, encoding: 'bom|utf-16le:utf-8', headers: true) do |row|
    # If there is no reply - push this review
    if row['Developer Reply Date and Time'].nil?
      Review.collection << Review.new({
        text: row['Review Text'],
        title: row['Review Title'],
        submitted_at: row['Review Last Update Date and Time'],
        edited: (row['Review Submit Date and Time'] != row['Review Last Update Date and Time']),
        original_submitted_at: row['Review Submit Date and Time'],
        rate: row['Star Rating'],
        device: device[row['Device']],
        url: row['Review Link'],
        version: row['App Version Code'],
        lang: row['Reviewer Language']
      })
    end
  end
end

Review.send_reviews_from_date(start_date, datefile)
