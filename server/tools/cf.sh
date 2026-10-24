#!/usr/bin/env bash
# Runs wrangler with this project's own Cloudflare login (hrdev.main account), kept in server/.wrangler/home
# (git-ignored), so the Mac's global wrangler login for other projects is never touched.
#   tools/cf.sh whoami | tools/cf.sh deploy | tools/cf.sh tail
# First time / expired: tools/cf.sh login
set -euo pipefail
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME="$PWD/.wrangler/home"
export CLOUDFLARE_ACCOUNT_ID="cd708edb210d36f6f898127f0373d124"
exec npx wrangler "$@"
