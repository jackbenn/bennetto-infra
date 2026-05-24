#!/usr/bin/env bash
set -euo pipefail

SSH_HOST="website"
REMOTE_DIR="~/bennetto-infra"

# --- Step 1: Bail on merge conflicts ---
dirty=""
while IFS= read -r line; do
    status="${line:0:1}"
    name=$(echo "${line:1}" | awk '{print $2}')
    if [[ "$status" == "U" ]]; then
        dirty="$dirty $name"
    fi
done < <(git submodule status)

if [[ -n "$dirty" ]]; then
    echo "Error: submodule(s) have merge conflicts:$dirty"
    echo "Resolve conflicts before deploying."
    exit 1
fi

# --- Step 2: Warn about uncommitted working-tree changes ---
while IFS= read -r line; do
    status="${line:0:1}"
    name=$(echo "${line:1}" | awk '{print $2}')
    if [[ "$status" == "+" || "$status" == " " ]]; then
        if [[ -n "$(git -C "$name" status --porcelain 2>/dev/null)" ]]; then
            echo "Warning: $name has uncommitted changes that will not be deployed."
        fi
    fi
done < <(git submodule status)

# --- Step 3: Fetch all submodule remotes ---
echo "-> Fetching submodule remotes..."
git submodule foreach --quiet 'git fetch origin 2>/dev/null || true'

# --- Step 4: Sync each submodule ---
updated_modules=""
while IFS= read -r line; do
    status="${line:0:1}"
    name=$(echo "${line:1}" | awk '{print $2}')

    ahead=$(git -C "$name" rev-list @{u}..HEAD --count 2>/dev/null || echo 0)
    behind=$(git -C "$name" rev-list HEAD..@{u} --count 2>/dev/null || echo 0)

    if [[ "$ahead" -gt 0 && "$behind" -gt 0 ]]; then
        echo "Error: $name has diverged from origin ($ahead ahead, $behind behind). Resolve manually."
        exit 1
    elif [[ "$ahead" -gt 0 ]]; then
        echo "-> Pushing $name ($ahead commit(s) ahead of origin)..."
        git -C "$name" push
        git add "$name"
        updated_modules="$updated_modules $name"
    elif [[ "$behind" -gt 0 ]]; then
        echo "-> Pulling $name ($behind commit(s) behind origin)..."
        git -C "$name" pull --ff-only
        git add "$name"
        updated_modules="$updated_modules $name"
    fi
done < <(git submodule status)

# --- Step 5: Commit pointer updates if any ---
if [[ -n "$updated_modules" ]]; then
    echo "-> Committing pointer updates for:$updated_modules"
    git commit -m "update submodule pointers:$updated_modules"
fi

# --- Step 6: Push bennetto-infra ---
echo "-> Pushing bennetto-infra..."
git push

# --- Step 7: Deploy on EC2 ---
echo "-> Deploying to $SSH_HOST..."
ssh "$SSH_HOST" "
    set -euo pipefail
    cd $REMOTE_DIR
    echo '  -> Pulling latest...'
    git pull --recurse-submodules
    echo '  -> Restarting services...'
    docker compose up -d --build
    echo '  -> Done.'
"

echo "Deploy complete."
