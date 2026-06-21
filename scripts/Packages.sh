#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

set -euo pipefail

# =========================
# 安装和更新软件包
# =========================
UPDATE_PACKAGE() {
	local PKG_NAME="$1"
	local PKG_REPO="$2"
	local PKG_BRANCH="$3"
	local PKG_SPECIAL="${4:-}"
	local REPO_NAME="${PKG_REPO#*/}"

	# 处理第5参数（列表）
	local PKG_LIST
	local EXTRA_LIST=()
	if [ -n "${5:-}" ]; then
		read -r -a EXTRA_LIST <<< "$5"
	fi
	PKG_LIST=("$PKG_NAME" "${EXTRA_LIST[@]}")

	echo " "

	# 删除旧包
	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"

		local FOUND_DIRS
		FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ \
			-maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null || true)

		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				[ -n "$DIR" ] && rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	# 克隆仓库
	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" \
		"https://github.com/$PKG_REPO.git" || {
		echo "Clone failed: $PKG_REPO"
		return 1
	}

	# 特殊处理
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find "./$REPO_NAME"/*/ -maxdepth 3 -type d \
			-iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf "./$REPO_NAME/"
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f "$REPO_NAME" "$PKG_NAME"
	fi
}

# =========================
# 调用（包管理）
# =========================

UPDATE_PACKAGE "homeproxy" "VIKINGYFY/homeproxy" "main"
UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"

UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"

UPDATE_PACKAGE "diskman" "lisaac/luci-app-diskman" "master"

# =========================
# 更新软件包版本
# =========================
UPDATE_VERSION() {
	local PKG_NAME="$1"
	local PKG_MARK="${2:-false}"

	local PKG_FILES
	PKG_FILES=$(find ./ ../feeds/packages/ \
		-maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile" || true)

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo -e "\n$PKG_NAME version update has started!"

	while read -r PKG_FILE; do

		local PKG_REPO
		PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" "$PKG_FILE")

		local PKG_TAG
		PKG_TAG=$(curl -fsSL "https://api.github.com/repos/$PKG_REPO/releases" \
			| jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name" || echo "")

		local OLD_VER OLD_URL OLD_FILE OLD_HASH
		OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL
		PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

		local NEW_VER
		NEW_VER=$(sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g' <<< "$PKG_TAG")

		local NEW_URL
		NEW_URL=$(sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g" <<< "$PKG_URL")

		local NEW_HASH
		NEW_HASH=$(curl -fsSL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi

	done <<< "$PKG_FILES"
}

# =========================
# 调用版本更新
# =========================
UPDATE_VERSION "sing-box"
# UPDATE_VERSION "tailscale"
