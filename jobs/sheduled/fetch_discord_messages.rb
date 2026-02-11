module Jobs
  class FetchDiscordMessages < ::Jobs::Scheduled
    every 10.minutes

    def execute(args)
      DiscordIntegration::DiscordSync.sync_messages!
    end
  end
end