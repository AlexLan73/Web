#!/bin/bash
# uninstall.sh — полный откат схемы на ПК2.
#   uninstall.sh           снять скрипты и настройки (пользователя оставить)
#   uninstall.sh --purge   плюс удалить пользователя sess и тёплый кеш
set -euo pipefail

SESSION_USER="${SESSION_USER:-sess}"
SRC_STATE="${SRC_STATE:-/run/session.src}"
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

log() { printf '\033[1;33m[uninstall]\033[0m %s\n' "$*"; }
[ "$(id -u)" -eq 0 ] || { echo "нужен root" >&2; exit 1; }

read -r -p "Откатить схему на этом ПК2? [y/N] " a
[ "$a" = "y" ] || exit 1

# 1. Активный сеанс не должен быть смонтирован
if mountpoint -q /run/session; then
  log "сначала заверши сеанс: session-deliver && session-down"
  exit 1
fi

# 2. Снять ro-bind проекта (на случай аварийного завершения)
if [ -f "$SRC_STATE" ]; then
  P="$(head -1 "$SRC_STATE")"; N0="$(sed -n 2p "$SRC_STATE")"
  while [ "$({ findmnt -rn -M "$P" -o TARGET 2>/dev/null || true; } | wc -l)" -gt "$N0" ]; do
    umount -l "$P" || break
  done
  rm -f "$SRC_STATE"
  log "$P → rw"
fi

# 3. Скрипты
for f in session-up session-enter session-deliver session-down session-verify \
         uninstall-session-scheme; do
  [ -e "/usr/local/sbin/$f" ] && rm -f "/usr/local/sbin/$f" && log "удалён $f"
done

# 4. journald обратно в persistent
if [ -e /etc/systemd/journald.conf.d/99-volatile.conf ]; then
  rm -f /etc/systemd/journald.conf.d/99-volatile.conf
  systemctl restart systemd-journald
  log "journald → снова по умолчанию (persistent)"
fi

# 5. profile.d
[ -e /etc/profile.d/00-rocm-session.sh ] && rm -f /etc/profile.d/00-rocm-session.sh \
  && log "удалён profile.d/00-rocm-session.sh"

# 6. Гибернация обратно
systemctl unmask hibernate.target hybrid-sleep.target suspend-then-hibernate.target 2>/dev/null || true
log "гибернация размаскирована"

# 7. Снять hold с ROCm (только то, что ставил install.sh, чужие hold не трогаем)
mapfile -t H < <(apt-mark showhold 2>/dev/null | grep -E '^(rocm|hip|hsa|amdgpu)' || true)
if [ "${#H[@]}" -gt 0 ]; then
  apt-mark unhold "${H[@]}" >/dev/null 2>&1 || true
  log "снят hold с ${#H[@]} пакетов"
fi

# 8. Опционально: пользователь и кеш
if [ "$PURGE" -eq 1 ]; then
  id "$SESSION_USER" >/dev/null 2>&1 && userdel "$SESSION_USER" && log "пользователь удалён"
  rm -rf "/home/$SESSION_USER" /var/cache/rocm-warm
  log "тёплый кеш и домашний каталог удалены"
fi

# 9. Метка проверки
rm -f /var/lib/session-stamp

log "готово. Что осталось руками:"
echo "  - дисковый swap: включится после перезагрузки (или swapon -a)"
echo "  - пакет bubblewrap, если он больше не нужен"
