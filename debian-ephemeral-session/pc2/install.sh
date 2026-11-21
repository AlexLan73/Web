#!/bin/bash
# install.sh — установка схемы на ПК2 (Debian 13 trixie, AMD, ROCm 7.4.2).
# Запуск от root из этого каталога.
set -euo pipefail

SESSION_USER="${SESSION_USER:-sess}"
HERE="$(cd "$(dirname "$0")" && pwd)"

log() { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
[ "$(id -u)" -eq 0 ] || { echo "нужен root" >&2; exit 1; }

# --- 0. система -----------------------------------------------------------
log "ядро: $(uname -r)"
log "дистрибутив: $(. /etc/os-release && echo "$PRETTY_NAME")"
if ! command -v bwrap >/dev/null 2>&1; then
  log "ставлю bubblewrap"
  apt-get update -qq && apt-get install -y bubblewrap
fi

# --- 1. пользователь агента (без домашнего каталога!) ---------------------
if id "$SESSION_USER" >/dev/null 2>&1; then
  log "пользователь $SESSION_USER уже есть"
else
  log "создаю $SESSION_USER (без home — A3)"
  useradd --no-create-home --home-dir /nonexistent --shell /bin/bash "$SESSION_USER"
fi
rm -rf "/home/$SESSION_USER"
for g in render video; do
  if getent group "$g" >/dev/null; then
    usermod -aG "$g" "$SESSION_USER"
  else
    log "нет группы $g (пропускаю)"
  fi
done
log "группы $SESSION_USER: $(id -nG "$SESSION_USER")"

# --- 2. скрипты -----------------------------------------------------------
log "ставлю скрипты в /usr/local/sbin"
for f in session-up session-enter session-deliver session-down; do
  install -m 0755 "$HERE/$f" "/usr/local/sbin/$f"
done
install -m 0755 "$HERE/verify.sh"       /usr/local/sbin/session-verify
install -m 0755 "$HERE/uninstall.sh"    /usr/local/sbin/uninstall-session-scheme

# --- 3. ROCm в PATH (иначе /etc/profile перетрёт --setenv PATH) ----------
log "profile.d: ROCm в PATH"
install -m 0644 /dev/stdin /etc/profile.d/00-rocm-session.sh <<'EOF'
# ROCm в PATH: /etc/profile в Debian перезаписывает PATH, поэтому только так
case ":$PATH:" in *":/opt/rocm/bin:"*) ;; *) PATH="/opt/rocm/bin:$PATH";; esac
export PATH
export ROCM_PATH=/opt/rocm
export HIP_PATH=/opt/rocm
EOF

# --- 4. журнал в RAM ------------------------------------------------------
log "journald → volatile"
install -d -m 0755 /etc/systemd/journald.conf.d
install -m 0644 "$HERE/journald-volatile.conf" /etc/systemd/journald.conf.d/99-volatile.conf
rm -rf /var/log/journal
systemctl restart systemd-journald

# --- 5. запрет гибернации (иначе вся RAM, включая tmpfs, уйдёт на диск) ---
log "маскирую гибернацию"
systemctl mask hibernate.target hybrid-sleep.target suspend-then-hibernate.target || true

# --- 6. фиксация версий ROCm ---------------------------------------------
# apt-mark не понимает глобы — берём фактические имена пакетов.
log "фиксирую версии ROCm/HIP/amdgpu"
mapfile -t PKGS < <(dpkg-query -W -f='${Package}\n' 'rocm*' 'hip*' 'hsa*' 'amdgpu*' 2>/dev/null || true)
if [ "${#PKGS[@]}" -gt 0 ]; then
  apt-mark hold "${PKGS[@]}" >/dev/null
  log "зафиксировано пакетов: $(apt-mark showhold | wc -l)"
else
  log "ПРЕДУПРЕЖДЕНИЕ: пакеты ROCm не найдены — версии не зафиксированы"
fi

# --- 7. тёплый кеш (каталог; наполняется вручную после сеанса) ------------
mkdir -p /var/cache/rocm-warm
chmod 0755 /var/cache/rocm-warm

# --- 8. отчёт по GPU ------------------------------------------------------
log "проверка GPU"
command -v rocminfo >/dev/null && rocminfo 2>/dev/null | grep -m2 gfx || log "rocminfo не установлен"
for d in /dev/kfd /dev/dri/renderD128; do
  if [ -e "$d" ]; then log "есть $d ($(stat -c '%A %U:%G' "$d"))"; else log "НЕТ $d"; fi
done
command -v python3 >/dev/null && python3 - <<'PY' 2>/dev/null || true
try:
    import torch
    print(f"torch {torch.__version__}  hip={torch.version.hip}  cuda={torch.cuda.is_available()}")
except Exception as e:
    print(f"torch не проверен: {e}")
PY

cat <<EOF

---
Дальше:
 1) Проект — где угодно (можно /home/alex/...). На время сеанса session-up
    делает ro-bind самого каталога проекта; раздел целиком не трогается.
    ИИ-слой берётся с ПК1: PC1_MOUNT (по умолчанию /mnt/PC1).

 2) Цикл:
      PROJECT_SRC=/home/alex/DSP-GPU session-up
      session-enter            # смоук: session-enter --probe
      exit
      session-deliver
      session-down --poweroff

 3) Метка для проверки: session-verify --mark

 4) Откат целиком:      uninstall-session-scheme
EOF
