require 'net/http'
require 'json'

module DiscordIntegration
  class DiscordAPI
    BASE_URL = "https://discord.com/api/v10"

    def initialize(token, guild_id)
      @token = token
      @guild_id = guild_id
    end

    # Kanały tekstowe widoczne dla @everyone
    def fetch_public_text_channels
      channels = fetch_channels
      channels.select do |ch|
        ch["type"] == 0 && channel_visible_to_everyone?(ch)
      end
    end

    # Wszyscy członkowie gildii
    def fetch_members(limit: 1000, after: nil)
      uri = URI("#{BASE_URL}/guilds/#{@guild_id}/members?limit=#{limit}")
      uri.query += "&after=#{after}" if after
      request(uri)
    end

    # Wiadomości z kanału (paginate)
    def fetch_channel_messages(channel_id, limit: 100, before: nil)
      uri = URI("#{BASE_URL}/channels/#{channel_id}/messages?limit=#{limit}")
      uri.query += "&before=#{before}" if before
      request(uri)
    end

    # Stany głosowe
    def fetch_voice_states
      guild = request(URI("#{BASE_URL}/guilds/#{@guild_id}?with_counts=true"))
      return [] unless guild

      # Discord nie daje bezpośrednio listy stanów głosowych dla gildii,
      # musimy pobrać kanały głosowe i stany osobno
      channels = fetch_channels
      voice_channels = channels.select { |ch| ch["type"] == 2 } # GUILD_VOICE

      voice_states = []
      voice_channels.each do |vc|
        states = request(URI("#{BASE_URL}/channels/#{vc["id"]}/voice-states"))
        voice_states.concat(states) if states.is_a?(Array)
      end
      voice_states
    rescue
      []
    end

    private

    def fetch_channels
      request(URI("#{BASE_URL}/guilds/#{@guild_id}/channels"))
    end

    def channel_visible_to_everyone?(channel)
      everyone_id = @guild_id
      permission_overwrites = channel["permission_overwrites"] || []
      overwrite = permission_overwrites.find { |ow| ow["id"] == everyone_id && ow["type"] == 0 } # rola @everyone
      return true unless overwrite # brak nadpisań = domyślnie widoczny

      allow = overwrite["allow"].to_i
      deny = overwrite["deny"].to_i
      view_channel_permission = 1 << 10 # Discord permission bit 10 = VIEW_CHANNEL

      (deny & view_channel_permission) == 0
    end

    def request(uri)
      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bot #{@token}"
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      JSON.parse(res.body)
    rescue => e
      Rails.logger.error("Discord API error: #{e.message}")
      nil
    end
  end
end
