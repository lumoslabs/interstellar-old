require 'rest-client'
require 'json'
require 'date'
require 'csv'
require 'yaml'

CONFIG = YAML.load_file('./secrets/secrets.yml')
datefile = "./lastdate"

date = [Time.at(File.exists?(datefile) ? IO.read(datefile).to_i : 0).to_datetime, Date.today.to_datetime - 7 + Rational(4, 24)].max

file_date = date.strftime("%Y%m")
csv_file_name = "reviews_#{CONFIG["package_name"]}_#{file_date}.csv"

system "BOTO_PATH=./secrets/.boto gsutil/gsutil cp -r gs://#{CONFIG["app_repo"]}/reviews/#{csv_file_name} ."


class Slack
  def self.notify(message)
    RestClient.post CONFIG["slack_url"], {
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
      r.submitted_at > date && (@@ratings[r.rate - 1] += 1) && (r.title || r.text) && r.lang == "en"
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
          @@ratings.map.with_index{ |x, i| "★" * (i + 1) + "☆" * (4 - i) + " #{x}" }.reverse,
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
    @text = data[:text] ? data[:text].to_s.encode("utf-8") : nil
    @title = data[:title] ? data[:title].to_s.encode("utf-8") : nil

    @submitted_at = DateTime.parse(data[:submitted_at].encode("utf-8"))
    @original_submitted_at = DateTime.parse(data[:original_submitted_at].encode("utf-8"))

    @rate = data[:rate].encode("utf-8").to_i
    @device = data[:device] ? data[:device].to_s.encode("utf-8") : nil
    @url = data[:url].to_s.encode("utf-8")
    @version = data[:version] ? "v#{data[:version].to_s.encode("utf-8")}" : nil
    @edited = data[:edited]
    @lang = data[:lang].to_s.encode("utf-8")
  end

  def build_message
    colors = ['danger', '#D4542C', 'warning', '#8BA24B', 'good']
    date = if edited
             "#{original_submitted_at.strftime("%Y.%m.%d at %H:%M")}, edited on #{submitted_at.strftime("%Y.%m.%d at %H:%M")}"
           else
             "#{submitted_at.strftime("%Y.%m.%d at %H:%M")}"
           end

    stars = "★" * rate + "☆" * (5 - rate)
    for_version = version ? "for #{version} " : ""

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
      mrkdwn_in: ["text"]
    }
  end
end

CSV.foreach(csv_file_name, encoding: 'bom|utf-16le', headers: true) do |row|
  # If there is no reply - push this review
  if row[11].nil?
    Review.collection << Review.new({
      text: row[10],
      title: row[9],
      submitted_at: row[6],
      edited: (row[4] != row[6]),
      original_submitted_at: row[4],
      rate: row[8],
      device: row[3],
      url: row[14],
      version: row[1],
      lang: row[2]
    })
  end
end

Review.send_reviews_from_date(date, datefile)
