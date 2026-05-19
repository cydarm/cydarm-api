#!/usr/bin/env bash

set -Euo pipefail

RELEASE_VERSION="${RELEASE_VERSION}"
FAST=${FAST:-0}

export PATH="/root/go/bin:/usr/local/go/bin:$PATH"
source "$HOME/.nvm/nvm.sh"

mkdir -p /build

function get_manifest() {
    local version=$1
    local git="git -C /repos/cydarm-installer"
    echo >&2 "Looking for version $version in cydarm-installer repository"

    local found=0
    local reftype=""
    if $git tag --list $version | grep -q $version; then
        found=1
        reftype="tag"
    elif $git branch --all --format='%(refname:lstrip=3)' --list "origin/$version" | grep -q $version; then
        found=1
        reftype="branch"
    fi
    if [[ $found -eq 0 ]]; then
        echo >&2 "Version $version not found as a tag or branch in cydarm-installer"
        exit 1
    fi
    case $reftype in
        tag)
            $git show "$version:manifest/cydarm-manifest.json" | base64 -w0
            ;;
        branch)
            $git show "origin/$version:manifest/cydarm-manifest.json" | base64 -w0
            ;;
        *)
            echo >&2 "Internal error: unknown reftype $reftype"
            exit 1
            ;;
    esac
}

function ensure_repo() {
    local repo_url="$1"
    local repo_dir="$2"

    if [ "$FAST" -eq 1 ]; then
        echo >&2 "FAST mode enabled, skipping repository setup for ${repo_url} at ${repo_dir}"
        return
    fi

    mkdir -p "$repo_dir"

    if [ ! -d "${repo_dir}/.git" ]; then
        echo >&2 "${repo_dir} is not a git repository, initializing and adding remote"
        git init "$repo_dir"
        git -C "$repo_dir" remote add origin "$repo_url"
    else
        echo >&2 "${repo_dir} is already a git repository, ensuring remote is set to ${repo_url} and cleaning repository"
        git -C "$repo_dir" remote set-url origin "$repo_url"
        git -C "$repo_dir" clean -ffxdq
    fi
    git -C "$repo_dir" fetch --prune --tags origin
}

function checkout_ref() {
    local repo_dir="$1"
    local expected_ref="$2"

    local current_ref; current_ref="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || true)"
    local remote_ref
    if [ "$FAST" -eq 1 ]; then
        remote_ref=""
    else
        remote_ref="$(git -C "$repo_dir" ls-remote origin ${expected_ref} | awk '{print $1}')"
    fi

    # if current checkedout ref doesn't match the expected ref, fetch and checkout the expected ref
    if [ "$current_ref" != "$remote_ref" ]; then
        echo >&2 "Current ref $current_ref does not match expected ref $remote_ref, fetching and checking out expected ref"
        if [ "$FAST" -eq 1 ]; then
            echo >&2 "FAST mode enabled, skipping fetch of expected ref ${expected_ref} in ${repo_dir}"
            FETCH_HEAD=$expected_ref
        else
            git -C "$repo_dir" fetch --prune origin ${expected_ref}
            FETCH_HEAD=FETCH_HEAD
        fi
        git -C "$repo_dir" checkout -f $FETCH_HEAD
        git -C "$repo_dir" clean -ffxdq
    fi
}

function go_deps() {
    (
        cd /repos/case-management
        go mod download -x
        go mod tidy
    )
}

# get case management version from manifest and checkout the expected ref in the case-management repo.
ensure_repo "git@github.com:cydarm/cydarm-installer.git" "/repos/cydarm-installer"

manifest_b64=$(get_manifest $RELEASE_VERSION)

function manifest_jq() {
    echo $manifest_b64 | base64 -d | jq -r "$@"
}

export CASE_MANAGEMENT_VERSION=$(manifest_jq '.cydarm.repos."case-management"')

ensure_repo "git@github.com:cydarm/case-management.git" "/repos/case-management"
checkout_ref "/repos/case-management" "${CASE_MANAGEMENT_VERSION}"

go_deps

export GIT_DESCRIBE=$(git -C /repos/case-management describe --tags --always --dirty)

exec "$@"
