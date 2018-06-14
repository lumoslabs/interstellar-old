require 'rest-client'
require 'json'
require 'date'
require 'csv'
require 'yaml'
require 'enumerator'
require 'google/cloud/storage'
require 'open-uri'


CONFIG = YAML.load_file('./secrets/secrets.yml')
datefile = CONFIG['date_file'] || './lastdate'
default_days_back = CONFIG['days_back'] || 7

class Slack
  def self.notify(message)
    RestClient.post CONFIG['slack_url'], {
      payload: message.to_json
    },
    content_type: :json,
    accept: :json
  rescue => e
    puts e.response
  end
end

class Review
  @@ratings = Array.new(5, 0)

  def self.collection
    @collection ||= []
  end

  def self.send_reviews_from_date(date, datefile)
    messages = collection.select { |r| r.submitted_at && r.submitted_at > date && (@@ratings[r.rate - 1] += 1) && (r.title || r.text) && r.lang == 'en' }.sort_by(&:submitted_at).map(&:build_message)

    ratings_sum = @@ratings.reduce(:+)
    if ratings_sum > 0
      # first message
      Slack.notify({
        text: [
          "#{ratings_sum} new Play Store #{ratings_sum == 1 ? 'rating' : 'ratings'}!",
          @@ratings.map.with_index{ |x, i| '★' * (i + 1) + '☆' * (4 - i) + " #{x}" }.reverse,
          "#{(@@ratings.map.with_index{ |x, i| x * (i + 1) }.reduce(:+).to_f / ratings_sum).round(3)} average rating\n",
          "#{messages.length} new Play Store #{messages.length == 1 ? 'review' : 'reviews'}!"
        ].join("\n")
      })

      # all the actual reviews
      messages.each_slice(100) do |messages_chunk|
        Slack.notify({
          text: "",
          attachments: messages_chunk
        })
      end

      IO.write(datefile, collection.max_by(&:submitted_at).submitted_at.to_time.to_i)
    else
      print "No new reviews\n"
    end
  end

  attr_accessor :text, :title, :submitted_at, :original_submitted_at, :rate, :device, :url, :version, :lang

  def initialize data = {}
    @text = data[:text]
    @title = data[:title]

    begin
      @submitted_at = DateTime.parse(data[:submitted_at])
    rescue ArgumentError
    end
    begin
      @original_submitted_at = DateTime.parse(data[:original_submitted_at])
    rescue ArgumentError
    end
    @rate = data[:rate].to_i
    @device = data[:device]
    @url = data[:url]
    @version = data[:version] ? "v#{data[:version]}" : nil
    @lang = data[:lang]
  end

  def build_message
    date = (original_submitted_at - submitted_at > 1 ? "#{original_submitted_at.strftime('%Y.%m.%d at %H:%M')}, edited on " : '') + submitted_at.strftime('%Y.%m.%d at %H:%M')
    stars = '★' * rate + '☆' * (5 - rate)
    footer = (version ? "for #{version} " : '') +"using #{device} on #{date}"

    {
      fallback: [stars, title, text, footer, url].join("\n"),
      color: ['#D36259', '#EF7E14', '#FFC105', '#BFD047', '#0E9D58'][rate - 1],
      author_name: stars,
      title: title,
      title_link: url,
      text: "#{text}\n_#{footer}_ · <#{url}|Permalink>",
      mrkdwn_in: ['text']
    }
  end
end

def download_file(file_name, remote_path, local_path)
  remote = "#{remote_path}/#{file_name}"
  local = "#{local_path}/#{file_name}"
  system "#{gsutil} cp #{remote} #{local}" if !File.exist?(local) || File.stat(local).size != `#{gsutil} du #{remote}`.to_i
end

def download_recent_files
   storage = Google::Cloud::Storage.new(project_id: 'app-store-review-reader')
   bucket = storage.bucket('pubsite_prod_rev_00633631127834465669')
   year_month = Date.today.strftime('%Y%m')
   csv_file_name = "reviews_#{CONFIG["package_name"]}_#{year_month}.csv"
   review_files = bucket.files prefix: "reviews/#{csv_file_name}"
   review_files.each do |rf|
     rf.download rf.name
   end
   review_files.map(&:name)
end

device = Hash.new

csv_text = open('http://storage.googleapis.com/play_public/supported_devices.csv')
CSV.foreach(csv_text, :encoding => 'bom|utf-16le:utf-8', :headers => true, :header_converters => :symbol) do |row|
  begin
    name = row[:marketing_name] || row[:model] || row[:device]
    if device[row[:device]]
      device[row[:device]] = "#{device[row[:device]]}/#{name}" if device[row[:device]].index(name).nil?
    else
      device[row[:device]] = !row[:retail_branding].nil? && name.downcase.tr('^a-z0-9', '').index(row[:retail_branding].downcase.tr('^a-z0-9', '')).nil? ? "#{row[:retail_branding]} #{name}" : name
    end
    device[row[:device]] = device[row[:device]].gsub('\t', '').gsub("\\'", "'").gsub('\\\\', '/').gsub(/(\\x[\da-f]{2}+)/) { [$1.tr('^0-9a-f','')].pack('H*').force_encoding('utf-8') }
  rescue => e
    puts "error while parsing: #{e}"
  end
end

csv_file_names = download_recent_files
csv_file_names.each do |csv_file_name|
  # ruby 2.5 can't parse with this file type
  # https://github.com/ruby/csv/issues/23
  CSV.foreach(csv_file_name, :encoding => 'bom|utf-16le:utf-8', :headers => true, :header_converters => :symbol) do |row|
    # If there is no reply - push this review
    if row[:developer_reply_date_and_time].nil?
      Review.collection << Review.new({
        text: row[:review_text],
        title: row[:review_title],
        submitted_at: row[:review_last_update_date_and_time],
        original_submitted_at: row[:review_submit_date_and_time],
        rate: row[:star_rating],
        device: device[row[:device]] ? device[row[:device]].downcase.tr('^a-z0-9', '').index(row[:device].downcase.tr('^a-z0-9', '')).nil? ? "#{device[row[:device]]} (#{row[:device]})" : device[row[:device]] : row[:device],
        url: row[:review_link],
        version: row[:app_version_name] || row[:app_version_code],
        lang: row[:reviewer_language]
      })
    end
  end
end

start_date = [Time.at(File.exist?(datefile) ? IO.read(datefile).to_i : 0).to_datetime, Date.today.to_datetime - default_days_back + Rational(4, 24)].max
Review.send_reviews_from_date(start_date, datefile)
