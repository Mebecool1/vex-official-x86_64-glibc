#!/usr/bin/env bash
# usage (run inside the repo dir): NAME=vex-official-core-x86_64-glibc ./deploy.sh
# checks tar sizes, rebuilds checksums, checks pkgs.list, then deploys .
set -euo pipefail

NAME="${NAME:-}"
if [ -z "$NAME" ]; then
    echo "usage: NAME=vex-official-core-x86_64-glibc ./deploy.sh" >&2
    exit 1
fi
PROJECT=$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' | tr '_' '-')

LIMIT=26214400   # 25 MiB, pages rejects anything bigger
shopt -s nullglob
tars=(*.tar.zst *.tar)

# 1. size check on every file that will be uploaded
big=$(find . -path ./.git -prune -o -type f -size +"${LIMIT}"c -print)
if [ -n "$big" ]; then
    echo "error: files over 25 MiB, pages will reject these:" >&2
    echo "$big" >&2
    exit 1
fi

# 2. warn about .git leaking into tars
for f in "${tars[@]}"; do
    listing=$(tar -tf "$f" 2>/dev/null || true)
    if grep -qE '(^|/)\.git/' <<< "$listing"; then
        echo "warning: $f contains a .git folder"
    fi
done

# 3. rebuild checksums
mkdir -p checksums
names=()
for f in "${tars[@]}"; do
    name="${f%.tar.zst}"
    [ "$name" = "$f" ] && name="${f%.tar}"
    names+=("$name")
    sha256sum "$f" | awk '{print $1}' > "checksums/$name.sha256"
done
echo "checksums rebuilt for ${#names[@]} packages"
names_str=$(printf '%s\n' "${names[@]}")

for c in checksums/*.sha256; do
    base=$(basename "$c" .sha256)
    if ! grep -qx "$base" <<< "$names_str"; then
        echo "warning: $c has no matching tar"
    fi
done

# 4. pkgs.list must match the tars
[ -f pkgs.list ] || : > pkgs.list
listed=$(awk 'NF {print $1}' pkgs.list)
bad=0
for n in "${names[@]}"; do
    if ! grep -qx "$n" <<< "$listed"; then
        echo "error: $n has a tar but no line in pkgs.list" >&2
        bad=1
    fi
done
while IFS= read -r n; do
    [ -z "$n" ] && continue
    if ! grep -qx "$n" <<< "$names_str"; then
        echo "error: pkgs.list lists $n but there is no tar for it" >&2
        bad=1
    fi
done <<< "$listed"
[ "$bad" -eq 0 ] || exit 1

# 5. real 404 so vex falls back to /pkgs.list
[ -f 404.html ] || printf '404\n' > 404.html

# 6. deploy
echo "deploying . to $PROJECT"
npx wrangler pages deploy . \
    --project-name "$PROJECT" \
    --branch main \
    --commit-dirty=true

echo "done: https://$PROJECT.pages.dev/"
