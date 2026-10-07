----------------------------------------------------------------------
-- Guild OS - Configuration
-- Single source of truth for all addon-wide constants.
-- This file is loaded first (before Core.lua) so every module can
-- safely reference GuildOS.* constants from the start.
----------------------------------------------------------------------

-- Create the primary namespace. Using "or {}" is idempotent — safe to
-- call even if a future loader has already created the table.
--
_G.GuildOS = _G.GuildOS or {}

-- ── Product identity ─────────────────────────────────────────────
GuildOS.ADDON_NAME        = "Guild OS"
GuildOS.NAMESPACE         = "GuildOS"

-- ── Version ───────────────────────────────────────────────────────
GuildOS.VERSION           = "0.70.0"  -- kept in sync with GuildOS.toc by the release workflow
GuildOS.COMM_VERSION      = 1

-- ── SavedVariables ────────────────────────────────────────────────
GuildOS.DB_GLOBAL         = "GuildOSDB"

-- ── Communication prefixes ────────────────────────────────────────
GuildOS.PREFIX            = "GUILDOS"

-- ── Slash commands ────────────────────────────────────────────────
GuildOS.SLASH_PRIMARY     = "/guildos"
