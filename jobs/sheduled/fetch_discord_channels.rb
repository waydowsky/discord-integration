module Jobs
  class FetchDiscordChannels < ::Jobs::Scheduled
    every 30.minutes

    def execute(args)
      DiscordIntegration::DiscordSync.sync_channels!
    end
  end
end
