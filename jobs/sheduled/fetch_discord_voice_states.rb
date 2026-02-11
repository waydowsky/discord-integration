module Jobs
  class FetchDiscordVoiceStates < ::Jobs::Scheduled
    every 2.minutes

    def execute(args)
      DiscordIntegration::DiscordSync.sync_voice_avatars!
    end
  end
end