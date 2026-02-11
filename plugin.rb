# name: discord_integration
# about: Integracja Discourse z Discordem – kanały → kategorie, wiadomości → wątki, aktywność głosowa
# version: 1.0
# authors: fremanhabel
# url: https://github.com/waydowsky/discord-integration

enabled_site_setting :discord_integration_enabled

register_asset "stylesheets/discord-voice-avatars.scss"

after_initialize do
  module ::DiscordIntegration
    PLUGIN_NAME = "discord_integration".freeze

    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscordIntegration
    end
  end

  # Ładowanie zależności
  require_dependency File.expand_path("../lib/discord_api.rb", __FILE__)
  require_dependency File.expand_path("../services/discord_sync.rb", __FILE__)

  # Jobs
  Dir[File.expand_path("../jobs/scheduled/*.rb", __FILE__)].each { |f| require_dependency f }

  # Widget w nagłówku (plugin outlet)
  add_to_serializer(:site, :discord_voice_avatars) do
    return [] unless SiteSetting.discord_integration_enabled && SiteSetting.discord_voice_widget_enabled

    # Pobieramy dane o aktywnych głosowo z PluginStore
    store = PluginStore.new("discord_integration")
    store.get("voice_avatars") || []
  end

  add_to_serializer(:site, :include_discord_voice_avatars?) do
    SiteSetting.discord_integration_enabled && SiteSetting.discord_voice_widget_enabled
  end

end
