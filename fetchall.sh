#!/usr/bin/env bash
# Fetch all git repositories under the current directory

set -e

# Find all directories containing a .git folder
find . -maxdepth 3 -name .git -type d -prune | while read -r gitdir; do
    repo_dir=$(dirname "$gitdir")
    echo "--- Fetching in $repo_dir ---"
    (cd "$repo_dir" && git fetch --all --prune)
done
