# NeoMutt for Linux kernel mail

Start the lmail account with `lmail`. Press `F1` inside NeoMutt to reopen this page.

## Triage and navigation

| Key | Action |
| --- | --- |
| `Enter` | Open the selected message or thread |
| `j` / `k` | Next / previous item |
| `J` / `K` | Next / previous thread |
| `Space` / `-` | Page down / up while reading |
| `Tab` | Jump to the next new or unread message |
| `F5` | Check the IMAP server for new mail |
| `t` | Tag a message; `;` applies the next action to tagged messages |
| `N` | Mark unread |
| `d` | Mark deleted; `$` syncs changes to the server |
| `A` | Archive the selected message |
| `/` | Search the mailbox (`~s text` searches subjects) |
| `l` | Limit the view, e.g. `~N` unread, `~f author`, `~s subject` |
| `Esc-l` | Show/clear the current limit |
| `,` / `.` / `'` | Previous / next sidebar mailbox; open it |
| `x` | Leave the current screen; `ZZ` quits NeoMutt |

## Kernel discussion and patches

| Key | Action |
| --- | --- |
| `L` | Reply to the mailing list (usually the right public reply) |
| `R` | Group reply to all recipients |
| `r` | Reply to the author only |
| `f` | Forward a message |
| `v` | View MIME parts and attachments |
| `s` | Save the message or patch to a file/folder |
| `\|` | Pipe the raw message to a command |
| `S` | Send the current message/digest to OpenRouter for a summary |
| `Ctrl-T` | Query an address while composing |

For kernel lists, keep replies plain-text and inline, trim quoted material, and
answer beneath the relevant quotation. Preserve recipients chosen by list/group
reply unless you intentionally want a private conversation. Before applying a
patch, inspect its version and thread; save it and use `git am` from the correct
kernel worktree rather than blindly piping mail into a repository.

`S` is opt-in. It transmits up to 250 KB of the selected raw message to the
configured OpenRouter model. Do not use it for confidential mail.

## Useful search patterns

| Pattern | Meaning |
| --- | --- |
| `~N` / `~U` | New / unread |
| `~F` | Flagged |
| `~d <1d` | Received within one day |
| `~f torvalds` | Sender contains `torvalds` |
| `~s "PATCH"` | Subject contains `PATCH` |
| `~b term` | Body contains `term` (may download IMAP bodies) |
| `~T` | Tagged messages |

Press `?` in any NeoMutt menu for its complete context-sensitive key list.
