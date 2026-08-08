#!/bin/sh
# Status line installation.
#
# A plugin cannot ship the main statusLine: plugin settings.json only supports
# the agent and subagentStatusLine keys. So selecta has to edit the user's
# global settings, which means it asks first, backs up first, and never
# clobbers an existing status line.
#
# The installed script is a copy at ~/.claude/selecta/statusline.sh rather than
# a path into the plugin, because plugins install under a versioned directory
# and any reference into it would break on the next update.

SELECTA_SETTINGS=${SELECTA_SETTINGS:-$HOME/.claude/settings.json}
SELECTA_SL_SCRIPT=$SELECTA_HOME/statusline.sh
SELECTA_SL_REFRESH_DEFAULT=2

# The built-in statusline-setup agent resolves symlinks and edits the target;
# writing through the link would replace the user's symlink with a plain file.
selecta_sl_settings_path() {
	_sp=$SELECTA_SETTINGS
	_sp_guard=0
	while [ -L "$_sp" ] && [ "$_sp_guard" -lt 10 ]; do
		_sp_guard=$((_sp_guard + 1))
		_sp_link=$(readlink -- "$_sp")
		case $_sp_link in
		/*) _sp=$_sp_link ;;
		*) _sp=$(dirname -- "$_sp")/$_sp_link ;;
		esac
	done
	printf '%s' "$_sp"
}

# missing | empty | absent | ours | ours-elsewhere | foreign | jsonc |
# unparseable | readonly | nojq
selecta_sl_detect() {
	_sd=$(selecta_sl_settings_path)

	[ -e "$_sd" ] || {
		printf 'missing'
		return 0
	}
	[ -s "$_sd" ] || {
		printf 'empty'
		return 0
	}
	if [ ! -w "$_sd" ]; then
		printf 'readonly'
		return 0
	fi
	# Merging settings needs jq. Without it we refuse and print the block
	# rather than rewriting someone's global config with sed.
	if ! selecta_have jq; then
		printf 'nojq'
		return 0
	fi
	if ! jq -e . "$_sd" >/dev/null 2>&1; then
		# The host parses JSONC. jq does not, so a comment-bearing file is
		# valid to the user and unreadable to us. Rewriting it with jq would
		# silently delete their comments, so we refuse instead.
		if grep -qE '(^|[[:space:]])//|/\*' "$_sd" 2>/dev/null; then
			printf 'jsonc'
		else
			printf 'unparseable'
		fi
		return 0
	fi
	_sd_cmd=$(jq -r '.statusLine.command // empty' "$_sd" 2>/dev/null)
	# Compared against the resolved script path rather than a hardcoded
	# substring: with SELECTA_HOME overridden, a substring test would fail to
	# recognise our own entry and we would end up wrapping ourselves.
	#
	# Any selecta launcher counts as ours, not just this SELECTA_HOME's. A
	# scratch or demo home installs a launcher at a different path, and
	# treating that as a stranger's status line wraps selecta around selecta,
	# which recurses until the status line produces nothing.
	if [ -z "$_sd_cmd" ]; then
		printf 'absent'
	elif [ "$_sd_cmd" = "$SELECTA_SL_SCRIPT" ]; then
		printf 'ours'
	else
		case $_sd_cmd in
		*statusline.sh*)
			if [ -f "${_sd_cmd%% *}" ] && grep -q 'selecta status line' "${_sd_cmd%% *}" 2>/dev/null; then
				printf 'ours-elsewhere'
				return 0
			fi
			;;
		esac
		printf 'foreign'
	fi
}

selecta_sl_block() {
	jq -n --arg cmd "$SELECTA_SL_SCRIPT" \
		--argjson refresh "$(selecta_cfg_get '.statusline.refresh' "$SELECTA_SL_REFRESH_DEFAULT")" \
		'{type: "command", command: $cmd, refreshInterval: $refresh, padding: 0}'
}

# Exactly what will be added, for the consent prompt. The user should never be
# asked to approve an edit they cannot see.
selecta_sl_preview() {
	printf '  "statusLine": %s\n' "$(selecta_sl_block | jq -c .)"
}

selecta_sl_backup_path() {
	printf '%s.selecta.bak.%s' "$(selecta_sl_settings_path)" "$(date -u +%Y%m%dT%H%M%SZ)"
}

# Installs the copy of the launcher. Kept separate from the settings edit so a
# failed settings write never leaves a half-installed script behind.
selecta_sl_install_script() {
	mkdir -p "$SELECTA_HOME" 2>/dev/null || return "$EX_UNWRITABLE"
	cp "$SELECTA_ROOT/statusline/launcher.sh" "$SELECTA_SL_SCRIPT" 2>/dev/null ||
		return "$EX_UNWRITABLE"
	chmod 755 "$SELECTA_SL_SCRIPT" 2>/dev/null || true
	return 0
}

# No backup means no write. Losing someone's settings.json is not recoverable
# and is far worse than declining to install a status line.
selecta_sl_write() {
	_sw_file=$(selecta_sl_settings_path)
	_sw_block=$1
	_sw_backup=''

	if [ -s "$_sw_file" ]; then
		_sw_backup=$(selecta_sl_backup_path)
		cp -p "$_sw_file" "$_sw_backup" 2>/dev/null || return "$EX_UNWRITABLE"
	else
		mkdir -p "$(dirname -- "$_sw_file")" 2>/dev/null || return "$EX_UNWRITABLE"
		printf '{}\n' >"$_sw_file" 2>/dev/null || return "$EX_UNWRITABLE"
	fi

	_sw_tmp=$(dirname -- "$_sw_file")/.selecta.$$.json
	if ! jq --argjson sl "$_sw_block" '.statusLine = $sl' "$_sw_file" >"$_sw_tmp" 2>/dev/null; then
		rm -f "$_sw_tmp"
		return "$EX_UNWRITABLE"
	fi
	chmod 600 "$_sw_tmp" 2>/dev/null || true
	mv -f "$_sw_tmp" "$_sw_file" 2>/dev/null || {
		rm -f "$_sw_tmp"
		return "$EX_UNWRITABLE"
	}

	printf '%s' "$_sw_backup"
	return 0
}

selecta_sl_install() {
	_si_state=$(selecta_sl_detect)
	case $_si_state in
	jsonc | unparseable | readonly | nojq) return 1 ;;
	esac

	selecta_sl_install_script || return "$EX_UNWRITABLE"

	_si_mode=own
	# ours-elsewhere is replaced outright rather than wrapped: wrapping one
	# selecta launcher in another is the recursion described above.
	if [ "$_si_state" = ours-elsewhere ]; then
		rm -f "$SELECTA_RUN/wrapped_command" 2>/dev/null
		selecta_cfg_set '.statusline.wrapped' 'null'
	fi
	if [ "$_si_state" = foreign ]; then
		# Preserve their command verbatim so the launcher can run it first and
		# `statusline off` can put it back exactly as it was.
		_si_their=$(jq -r '.statusLine.command' "$(selecta_sl_settings_path)")
		_si_theirobj=$(jq -c '.statusLine' "$(selecta_sl_settings_path)")
		printf '%s\n' "$_si_their" | selecta_atomic_write "$SELECTA_RUN/wrapped_command"
		selecta_cfg_set '.statusline.wrapped' "$_si_theirobj"
		_si_mode=wrap
	fi

	_si_backup=$(selecta_sl_write "$(selecta_sl_block)") || return "$EX_UNWRITABLE"

	selecta_cfg_set '.statusline.installed' true
	selecta_cfg_set '.statusline.mode' "\"$_si_mode\""
	selecta_cfg_set '.statusline.installed_at' "\"$(selecta_now_iso)\""
	[ -n "$_si_backup" ] && selecta_cfg_set '.statusline.backup' "\"$_si_backup\""
	printf '%s' "$_si_mode"
	return 0
}

# Ours and unwrapped: remove the key entirely so the host's footer hints come
# back. Wrapped: restore their original object byte for byte.
selecta_sl_uninstall() {
	_su_file=$(selecta_sl_settings_path)
	[ -f "$_su_file" ] || return 0
	jq -e . "$_su_file" >/dev/null 2>&1 || return 1

	cp -p "$_su_file" "$(selecta_sl_backup_path)" 2>/dev/null || return "$EX_UNWRITABLE"
	_su_wrapped=$(selecta_cfg_get '.statusline.wrapped' 'null')
	_su_tmp=$(dirname -- "$_su_file")/.selecta.$$.json

	if [ "$_su_wrapped" != null ] && [ -n "$_su_wrapped" ]; then
		jq --argjson sl "$_su_wrapped" '.statusLine = $sl' "$_su_file" >"$_su_tmp" 2>/dev/null
	else
		jq 'del(.statusLine)' "$_su_file" >"$_su_tmp" 2>/dev/null
	fi || {
		rm -f "$_su_tmp"
		return "$EX_UNWRITABLE"
	}
	mv -f "$_su_tmp" "$_su_file" 2>/dev/null || {
		rm -f "$_su_tmp"
		return "$EX_UNWRITABLE"
	}

	rm -f "$SELECTA_SL_SCRIPT" "$SELECTA_RUN/wrapped_command" 2>/dev/null
	selecta_cfg_set '.statusline.installed' false
	selecta_cfg_set '.statusline.mode' '"own"'
	selecta_cfg_set '.statusline.wrapped' 'null'
	return 0
}
