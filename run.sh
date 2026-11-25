#!/bin/zsh
# Usage: ./run.sh [minutes=480] [maxCrafts=2000]   Stop: hold Esc, or Ctrl+C here.
cd "${0:A:h}" || exit 1
mkdir -p build logs
[ build/bot -nt bot/bot.swift ] || swiftc -parse-as-library -O bot/bot.swift -o build/bot || exit 1
caffeinate -di ./build/bot "${1:-480}" "${2:-2000}"
osascript -e 'display notification "Bot durdu, loga bak." with title "Shop Titans bot" sound name "Glass"'
say -v Yelda "Shop Titans botu durdu" 2>/dev/null || say "Shop Titans bot stopped"
