----------------------------------------------------------------------
-- Guild OS - Configuration
-- Single source of truth for all addon-wide constants.
-- This file is loaded first (before Core.lua) so every module can
-- safely reference GuildOS.* constants from the start.
----------------------------------------------------------------------

-- Create the primary namespace. Using "or {}" is idempotent — safe to
-- call even if a future loader has already created the table.
--
-- @deprecated  BRutus  Legacy alias kept for backward-compatibility.
--              All new code must use GuildOS.*
--              This alias will be removed in a future major version.
_G.GuildOS = _G.GuildOS or {}
_G.BRutus  = _G.GuildOS  -- legacy alias → same table

-- ── Product identity ─────────────────────────────────────────────
GuildOS.ADDON_NAME        = "Guild OS"
GuildOS.NAMESPACE         = "GuildOS"
GuildOS.LEGACY_NAMESPACE  = "BRutus"     -- @deprecated

-- ── Version ───────────────────────────────────────────────────────
GuildOS.VERSION           = "0.30.0"  -- kept in sync with GuildOS.toc by the release workflow
GuildOS.COMM_VERSION      = 1

-- ── SavedVariables ────────────────────────────────────────────────
GuildOS.DB_GLOBAL         = "GuildOSDB"
GuildOS.LEGACY_DB_GLOBAL  = "BRutusDB"   -- @deprecated; preserved for migration only

-- ── Communication prefixes ────────────────────────────────────────
GuildOS.PREFIX            = "GUILDOS"
GuildOS.LEGACY_PREFIX     = "BRutus"     -- @deprecated; still accepted for cross-version compat

-- ── Slash commands ────────────────────────────────────────────────
GuildOS.SLASH_PRIMARY     = "/guildos"
GuildOS.SLASH_LEGACY      = "/brutus"    -- @deprecated
