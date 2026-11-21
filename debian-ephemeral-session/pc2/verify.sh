#!/bin/bash
# verify.sh — проверка «остались ли следы». Запускать на ПК2.
#   verify.sh --mark     поставить метку времени ПЕРЕД сеансом
#   verify.sh            проверить ПОСЛЕ сеанса, в обычной загрузке
# Эталон — этот файл (листинг в PLAN.md §8.7 устарел); протокол — §10
set -uo pipefail

STAMP="${STAMP:-/var/lib/session-stamp}"
PROJ="${PROJ:-${PROJECT_SRC:-/data/proj}}"
SU="${SESSION_USER:-sess}"

if [ "${1:-}" = "--mark" ]; then
  [ "$(id -u)" -eq 0 ] || { echo "нужен root" >&2; exit 1; }
  sync
  : > "$STAMP"
  echo "метка: $STAMP  $(date -Is)"
  command -v systemd-time-wait-sync >/dev/null && echo "проверь синхронизацию часов: timedatectl"
  exit 0
fi

[ -e "$STAMP" ] || { echo "нет метки, сначала: verify.sh --mark" >&2; exit 1; }
hr() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

echo "отчёт сформирован: $(date -Is)"
echo "метка:             $(date -r "$STAMP" -Is)"

hr "1. корень: файлы новее метки (whitelist системного шума)"
find / -xdev -newer "$STAMP" \
  -not -path '/proc/*' -not -path '/sys/*' -not -path '/run/*' \
  -not -path '/var/lib/sudo/*' -not -path '/var/lib/systemd/*' \
  -not -path '/var/log/wtmp' -not -path '/var/log/lastlog' \
  -not -path '/var/log/btmp' -not -path '/var/cache/*' \
  -not -path '/var/lib/apt/*' -not -path "$PROJ/*" 2>/dev/null | head -60

hr "2. проект $PROJ: файлы новее метки (без .git)"
find "$PROJ" -path '*/.git' -prune -o -newer "$STAMP" -print 2>/dev/null | head -40

hr "3. журнал systemd"
journalctl --list-boots 2>/dev/null | tail -5
[ -d /var/log/journal ] && echo "!!! /var/log/journal существует" \
                        || echo "ok: persistent journal отсутствует"

hr "4. домашний каталог агента"
if [ -d "/home/$SU" ]; then
  n=$(find "/home/$SU" -mindepth 1 2>/dev/null | head -5)
  if [ -n "$n" ]; then echo "!!! непустой /home/$SU:"; echo "$n"; else echo "ok: пуст"; fi
else
  echo "ok: /home/$SU отсутствует"
fi

hr "5. конфиги агентов в проекте"
f=$(find "$PROJ" \( -name '.git' -o -name 'node_modules' \) -prune -o \
     \( -name '.claude*' -o -name '.codex*' -o -name '.cursor*' -o -name '.aider*' \
        -o -name '.opencode*' -o -name '.continue*' \
        -o -name 'AGENTS.md' -o -name 'CLAUDE.md' -o -name '.mcp.json' \
        -o -name '*.log' \) -print 2>/dev/null)
[ -z "$f" ] && echo "ok: ничего не найдено" || { echo "!!!"; echo "$f"; }

hr "6. авторство коммитов"
git -c "safe.directory=$PROJ" -C "$PROJ" log -5 --format='%h  %an <%ae>  %s' 2>/dev/null \
  || echo "не git-репозиторий"

hr "7. swap / гибернация / пакеты"
swapon --show || echo "ok: swap выключен"
systemctl is-enabled hibernate.target 2>/dev/null
if [ -e /var/log/dpkg.log ]; then
  awk -v d="$(date -r "$STAMP" +%Y-%m-%d)" '$1 >= d && / install /' /var/log/dpkg.log | head -10
else
  echo "ok: /var/log/dpkg.log отсутствует"
fi

hr "8. невыгруженные патчи"
ls -la /var/tmp/session-*.patch 2>/dev/null || echo "ok: нет"

hr "9. ИИ-слой на диске ПК2 (должен жить только в RAM)"
# -xdev: не заходить в сетевые маунты ПК1, если они смонтированы внутри /home
a=$(find /root /home -xdev -maxdepth 3 \( -name '.claude' -o -name '.claude.json' \
      -o -name '.cursor' -o -name '.aider*' -o -name '.codex' -o -name '.continue' \
      -o -path '*/.config/opencode' \) -not -path "$PROJ/*" 2>/dev/null)
[ -z "$a" ] && echo "ok: не найден" || { echo "!!!"; echo "$a"; }

printf '\n'
