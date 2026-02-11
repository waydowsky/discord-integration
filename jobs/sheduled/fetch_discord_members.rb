module Jobs
  class FetchDiscordMembers < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      DiscordIntegration::DiscordSync.sync_members!
    end
  end
end