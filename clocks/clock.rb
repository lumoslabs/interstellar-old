require 'clockwork'

STDOUT.sync = true

module Clockwork
  configure do |config|
    config[:thread] = true
    config[:tz] = 'UTC' # this will be the default in kubernetes pods anyways.
  end

  # catch errors that bubble up and send to rollbar
  error_handler do |error|
    Rollbar.error(error)
  end

  # comments for Pacific time clarity assume it is winter in California (PST)
  # 7:30am in PST
  # 86400 is 1 day in seconds
  every(86400, 'send_reviews', at: '17:10', thread: true) do
    system("ruby sender.rb")
  end
end
