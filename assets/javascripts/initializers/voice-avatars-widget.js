import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "discord-voice-avatars",
  initialize() {
    withPluginApi("1.8.0", (api) => {
      api.renderInOutlet("header-icons", `
        {{#if site.discord_voice_avatars}}
          <div class="discord-voice-avatars">
            {{#each site.discord_voice_avatars as |user|}}
              <a href="#" title="{{user.username}} aktywny na Discordzie (głos)">
                <img src="{{user.avatar_url}}" class="avatar" width="32" height="32">
              </a>
            {{/each}}
          </div>
        {{/if}}
      `);
    });
  }
};
