-- unread_summary.lua
-- Summarizes unread emails in the inbox using an LLM.
-- Press ctrl+u in the inbox to generate a summary of everything currently
-- unread. Tracks unread state itself from the email_received/email_viewed
-- events, since the plugin API has no "list all emails" call.
--
-- Configuration: uses OpenRouter's OpenAI-compatible chat completions API.
-- API_KEY below is substituted at deploy time from the sops-managed
-- openrouter_api_key secret (see modules/sops.nix) -- do not hardcode a
-- real key here, this file is checked into git.

local matcha = require("matcha")

-- Configuration
local API_URL = "https://openrouter.ai/api/v1/chat/completions"
local API_KEY = "@OPENROUTER_API_KEY@"
local MODEL   = "anthropic/claude-haiku-4.5" -- check https://openrouter.ai/models for the current slug
local FOLDER  = "INBOX"

local SYSTEM_PROMPT = [[You summarize a list of unread emails for someone triaging their inbox.
You will receive a list of unread emails, one per line, each with sender, subject, and date.
Write a short summary (4-8 sentences, or a compact bullet list) that:
- Groups related emails (same sender or topic) together.
- Calls out anything that looks urgent, time-sensitive, or action-required.
- Ignores obvious newsletters/promotions unless something stands out.
Output plain text only, no markdown headers.]]

local unread = {}

local function key_for(email)
    return email.account_id .. ":" .. email.folder .. ":" .. email.uid
end

matcha.on("email_received", function(email)
    if email.folder ~= FOLDER then
        return
    end
    if email.is_read then
        unread[key_for(email)] = nil
    else
        unread[key_for(email)] = {
            from = email.from,
            subject = email.subject,
            date = email.date,
        }
    end
end)

matcha.on("email_viewed", function(email)
    unread[key_for(email)] = nil
end)

matcha.on("folder_changed", function(folder)
    if folder ~= FOLDER then
        unread = {}
    end
end)

local function count_unread()
    local n = 0
    for _ in pairs(unread) do
        n = n + 1
    end
    return n
end

local function build_email_list()
    local lines = {}
    for _, e in pairs(unread) do
        lines[#lines + 1] = string.format("- From: %s | Subject: %s | Date: %s", e.from, e.subject, e.date)
    end
    return table.concat(lines, "\n")
end

local function json_escape(s)
    return (s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'))
end

matcha.bind_key("ctrl+u", "inbox", "Summarize unread", function()
    local n = count_unread()
    if n == 0 then
        matcha.notify("No unread emails to summarize", 3)
        return
    end

    if API_KEY == "" then
        matcha.notify("unread_summary: API_KEY is not set", 4)
        return
    end

    matcha.notify("Summarizing " .. n .. " unread emails...", 10)

    local user_msg = "Unread emails:\n" .. build_email_list()

    local payload = string.format(
        '{"model":"%s","messages":[{"role":"system","content":"%s"},{"role":"user","content":"%s"}]}',
        MODEL, json_escape(SYSTEM_PROMPT), json_escape(user_msg)
    )

    local res, err = matcha.http({
        url = API_URL,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. API_KEY,
        },
        body = payload,
    })

    if err then
        matcha.notify("Summary failed: " .. err, 4)
        return
    end

    if res.status ~= 200 then
        matcha.notify("Summary failed: HTTP " .. res.status, 4)
        matcha.log("unread_summary: HTTP " .. res.status .. ": " .. res.body)
        return
    end

    local content = res.body:match('"content"%s*:%s*"(.-)"')
    if not content then
        matcha.notify("Could not parse summary response", 4)
        matcha.log("unread_summary: unparsed body: " .. res.body)
        return
    end

    content = content:gsub('\\n', '\n'):gsub('\\"', '"'):gsub('\\\\', '\\')

    matcha.log("unread_summary:\n" .. content)
    matcha.store_set("last_summary", content)
    matcha.set_status("inbox", content:sub(1, 120):gsub("\n", " "))
    matcha.notify("Summary ready (full text in log, preview in title bar)", 6)
end)
