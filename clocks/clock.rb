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
  every(1.day, 'send_reviews', at: '15:30', thread: true) do
    system("ruby sender.rb")
  end
end
