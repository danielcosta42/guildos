----------------------------------------------------------------------
-- Guild OS - this release's notes, written by the release workflow (tools/release_notes_lua.py).
-- What's new opens with them at the first login with this version (Modules/Onboarding.lua).
----------------------------------------------------------------------
GuildOS.RELEASE_NOTES = {
    version = "2.2.1",
    lines = {
        "Fixed lag spikes for guilds whose officers publish to guildos.me: the alliance directory the Companion brings is read a few milliseconds at a time after login and never in combat, and the roster is no longer re-read on every addon message (opening the Hall went from about 470 ms to 20 ms)."
    },
}
