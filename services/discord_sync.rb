module DiscordIntegration
  class DiscordSync
    def self.sync_channels!
      return unless SiteSetting.discord_integration_enabled && SiteSetting.discord_sync_channels
      return if SiteSetting.discord_bot_token.blank? || SiteSetting.discord_guild_id.blank?

      api = DiscordAPI.new(SiteSetting.discord_bot_token, SiteSetting.discord_guild_id)
      channels = api.fetch_public_text_channels

      store = PluginStore.new("discord_integration")
      mapped = store.get("channel_category_map") || {}

      channels.each do |ch|
        category = find_or_create_category(ch["name"], ch["id"])
        mapped[ch["id"]] = category.id
      end

      store.set("channel_category_map", mapped)
    end

    def self.sync_members!
      return unless SiteSetting.discord_integration_enabled && SiteSetting.discord_sync_members
      return if SiteSetting.discord_bot_token.blank? || SiteSetting.discord_guild_id.blank?

      api = DiscordAPI.new(SiteSetting.discord_bot_token, SiteSetting.discord_guild_id)
      members = []
      after = nil
      loop do
        batch = api.fetch_members(limit: 1000, after: after)
        break if batch.blank? || batch.empty?
        members.concat(batch)
        after = batch.last["user"]["id"]
        break if batch.size < 1000
      end

      store = PluginStore.new("discord_integration")
      user_map = store.get("discord_user_map") || {}

      members.each do |member|
        user_data = member["user"]
        discord_id = user_data["id"]
        username = user_data["username"]
        avatar_hash = user_data["avatar"]

        # Tworzymy lub aktualizujemy użytkownika Discourse
        user = find_or_create_user(discord_id, username, avatar_hash)
        user_map[discord_id] = user.id
      end

      store.set("discord_user_map", user_map)
    end

    def self.sync_messages!
      return unless SiteSetting.discord_integration_enabled && SiteSetting.discord_sync_messages
      return if SiteSetting.discord_bot_token.blank? || SiteSetting.discord_guild_id.blank?

      api = DiscordAPI.new(SiteSetting.discord_bot_token, SiteSetting.discord_guild_id)
      store = PluginStore.new("discord_integration")
      channel_map = store.get("channel_category_map") || {}
      user_map = store.get("discord_user_map") || {}
      last_message_map = store.get("last_synced_message") || {}

      channel_map.each do |discord_channel_id, category_id|
        before = last_message_map[discord_channel_id]
        messages = []
        loop do
          batch = api.fetch_channel_messages(discord_channel_id, limit: 100, before: before)
          break if batch.blank? || batch.empty?
          messages.concat(batch)
          before = batch.last["id"]
          break if batch.size < 100
        end

        # Wiadomości przychodzą od najnowszych, odwracamy aby tworzyć wątki chronologicznie
        messages.reverse_each do |msg|
          process_message(msg, category_id, user_map, store)
        end

        # Zapisujemy ID ostatniej zsynchronizowanej wiadomości
        last_message_map[discord_channel_id] = messages.first["id"] if messages.any?
      end

      store.set("last_synced_message", last_message_map)
    end

    def self.sync_voice_avatars!
      return unless SiteSetting.discord_integration_enabled && SiteSetting.discord_voice_widget_enabled
      return if SiteSetting.discord_bot_token.blank? || SiteSetting.discord_guild_id.blank?

      api = DiscordAPI.new(SiteSetting.discord_bot_token, SiteSetting.discord_guild_id)
      voice_states = api.fetch_voice_states

      # Wyciągamy unikalnych użytkowników
      users_in_voice = voice_states.map { |vs| vs["member"]["user"] }.uniq { |u| u["id"] }

      avatars = users_in_voice.map do |user|
        {
          username: user["username"],
          avatar_url: "https://cdn.discordapp.com/avatars/#{user["id"]}/#{user["avatar"]}.png"
        }
      end

      store = PluginStore.new("discord_integration")
      store.set("voice_avatars", avatars)
    end

    private

    def self.find_or_create_category(name, discord_channel_id)
      store = PluginStore.new("discord_integration")
      map = store.get("channel_category_map") || {}
      if category_id = map[discord_channel_id]
        cat = Category.find_by(id: category_id)
        return cat if cat
      end

      # Tworzymy kategorię w Discourse
      category = Category.new(
        name: name,
        user: Discourse.system_user,
        color: "25A56A", # zielony, może być konfigurowalny
        text_color: "FFFFFF"
      )
      category.save!
      category
    end

    def self.find_or_create_user(discord_id, username, avatar_hash)
      store = PluginStore.new("discord_integration")
      map = store.get("discord_user_map") || {}
      if user_id = map[discord_id]
        user = User.find_by(id: user_id)
        return user if user
      end

      # Tworzymy nowego użytkownika Discourse
      # Ważne: username musi być unikalny, dodajemy sufiks
      base_username = username.parameterize
      candidate = base_username
      suffix = 1
      while User.exists?(username: candidate)
        candidate = "#{base_username}#{suffix}"
        suffix += 1
      end

      user = User.new(
        username: candidate,
        email: "#{discord_id}@discord.import.local",
        name: username,
        active: true,
        approved: true
      )
      user.save!
      user.activate

      # Pobieramy awatar z Discorda
      if avatar_hash
        avatar_url = "https://cdn.discordapp.com/avatars/#{discord_id}/#{avatar_hash}.png"
        UserAvatar.import_url_for_user(avatar_url, user)
      end

      user
    end

    def self.process_message(msg, category_id, user_map, store)
      discord_id = msg["id"]
      channel_id = msg["channel_id"]
      author_id = msg["author"]["id"]
      content = msg["content"]
      timestamp = Time.parse(msg["timestamp"])
      referenced_msg_id = msg["message_reference"]&.dig("message_id")

      # Mapowanie na lokalne ID
      discourse_user_id = user_map[author_id] || Discourse.system_user.id

      # Sprawdzamy czy wiadomość już zaimportowana
      imported = store.get("imported_messages") || {}
      return if imported[discord_id]

      if referenced_msg_id.present?
        # To jest odpowiedź – szukamy wątku (topica) utworzonego z oryginalnej wiadomości
        topic_id = find_topic_for_discord_message(referenced_msg_id, store)
        if topic_id
          # Dodajemy post jako odpowiedź
          post = PostCreator.create!(
            User.find(discourse_user_id),
            topic_id: topic_id,
            raw: content,
            created_at: timestamp,
            skip_validations: true
          )
          imported[discord_id] = post.id
        else
          # Nie znaleziono oryginału – tworzymy nowy wątek
          topic = create_topic_from_message(msg, category_id, discourse_user_id, timestamp)
          imported[discord_id] = topic.id
        end
      else
        # Nowa wiadomość – tworzymy wątek
        topic = create_topic_from_message(msg, category_id, discourse_user_id, timestamp)
        imported[discord_id] = topic.id
      end

      store.set("imported_messages", imported)
    end

    def self.create_topic_from_message(msg, category_id, user_id, timestamp)
      topic = Topic.new(
        title: "Wiadomość od #{msg["author"]["username"]}",
        category_id: category_id,
        user_id: user_id,
        created_at: timestamp
      )
      topic.save!

      # Tworzymy pierwszy post
      PostCreator.create!(
        User.find(user_id),
        topic_id: topic.id,
        raw: msg["content"],
        created_at: timestamp,
        skip_validations: true
      )
      topic
    end

    def self.find_topic_for_discord_message(discord_message_id, store)
      imported = store.get("imported_messages") || {}
      post_id = imported[discord_message_id]
      return nil unless post_id
      post = Post.find_by(id: post_id)
      post&.topic_id
    end
  end
end
