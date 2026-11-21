# Эфемерный GPU-сеанс на ПК2

**Версия:** 1.1 (второе ревью, §14.2: ro-bind каталога проекта, ИИ-слой с ПК1, песочница с allowlist-корнем, патч от снимка)
**Назначение:** реализация схемы «агент работает на ПК2, всё состояние — в RAM, на диске не остаётся следов работы агента»
**Целевая ОС:** Debian 13 (trixie), ext4, AMD RX 9070, ROCm 7.4.2, 64 ГБ RAM
**Статус:** к внедрению. Все блокеры ревью закрыты, изменения перечислены в §14.

---

## 1. Цель и критерий приёмки

**Цель.** ПК2 — вычислительный узел с GPU. Агент (LLM-инструмент) работает на нём внутри эфемерной среды: рабочая копия проекта, кеши, HOME, журналы живут в RAM и исчезают при выключении. На диск попадают только явно возвращённые правки проекта.

**Критерий приёмки:**

| # | Проверка | Ожидание |
|---|---|---|
| A1 | После сеанса и перезагрузки: файлы новее метки (корень + `/data`) | только whitelist-шум |
| A2 | `journalctl --list-boots` | сеанса нет; `/var/log/journal` пуст |
| A3 | `/home/sess` | отсутствует; `.bash_history`, `.cache` нет |
| A4 | `git log` в проекте | нет коммитов с автором-агентом |
| A5 | `.claude*`, `.codex*`, `AGENTS.md`, `.mcp.json`, `*.log` в проекте | ничего не найдено |
| A6 | После `session-deliver` | изменения на месте, `git apply --reverse --check` проходит |
| A7 | Правки не потерялись при `session-down` | копия патча в `/var/tmp` + подтверждение |
| A8 | `rocminfo`, `torch.cuda.is_available()` внутри песочницы | GPU доступен |

**Уровень требовательности:** «коллега/админ не заметит». Не форензика по секторам — см. §12.1.

---

## 2. Факты о железе и ПО (проверено)

| Компонент | Значение | Источник |
|---|---|---|
| Дистрибутив | Debian 13 trixie | согласовано |
| Ядро | 6.12.117 | `linux-image-amd64` в trixie |
| Mesa | 25.0.7 | `libgl1-mesa-dri` в trixie |
| GPU | RX 9070, RDNA4, **gfx1201** | нужно ядро ≥6.12, Mesa ≥25.0 |
| Драйвер | in-kernel `amdgpu` | **не dkms** — нет пересборки при смене ядра |
| ROCm | 7.4.2 (системный) | данные владельца |
| ROCm в Debian | только `rocminfo`, `rocm-smi` 6.1.2 | packages.debian.org |
| FS | ext4 | оставляем |
| RAM | 64 ГБ | данные владельца |

**Следствия:**

1. AMD выгоднее NVIDIA: драйвер в ядре ⇒ эфемерность не конфликтует с обновлениями.
2. Полный ROCm — из `repo.radeon.com/rocm/apt/debian`; версии 7.4.2 в версионных каталогах нет (максимум 7.2.4) ⇒ **репозиторий скользящий, фиксация версий обязательна** (см. §7).
3. `torch` — под ту же ветку ROCm. **Не смешивать** с pip-колёсами `+rocmX.Y` другой минорной версии и не выставлять `LD_LIBRARY_PATH=/opt/rocm/lib` рядом с колёсами (ABI-рассинхрон).
4. `HSA_OVERRIDE_GFX_VERSION` **не выставлять** — для gfx1201 не нужен, ломает.

---

## 3. Архитектура

```
ПК1 (Debian)                                  ПК2 (Debian 13, RX 9070, 64 ГБ)
├─ USB-тетеринг → интернет                    ├─ /                 ext4, обычная загрузка
├─ nft masquerade (LAN → WAN)                 ├─ /data             ext4 rw + noatime
├─ dnsmasq: DHCP + DNS                        │    └─ proj         проект (источник)
└─ логи трафика (аудит)          LAN          ├─ /run/session      tmpfs 20 ГБ
   ────────────────────────────►             │    ├─ work/proj    рабочая копия
                                             │    ├─ home         HOME агента
                                             │    └─ out.patch    результат
                                             ├─ /opt/rocm         ro, 7.4.2
                                             ├─ /opt/venvs/proj   ro, зависимости
                                             ├─ /var/cache/rocm-warm/<версия>/  тёплый кеш
                                             ├─ journald → volatile (RAM)
                                             ├─ swap → zram (RAM)
                                             └─ агент в bwrap, user sess
```

Роли: ПК1 — шлюз и аудит; ПК2 — вычисления. Интернет на ПК2 есть (NAT), поэтому агент живёт **на ПК2**.

**Важно:** `/data` в fstab монтируется `rw,noatime,nodiratime`. Режим `ro` ставит и снимает **только** `session-up`/`session-down`, симметрично, с проверкой. Иначе человек не сможет закоммитить правки после перезагрузки (см. §14, ревью M1).

**С версии 1.1 (§14.2):** проект может лежать где угодно (`PROJECT_SRC=/home/alex/DSP-GPU`), отдельный раздел не нужен — `ro` ставится bind-маунтом самого каталога, раздел не перемонтируется. ИИ-слой (`.claude`, `.claude.json`, `.cursor`, `.config/opencode`, `.aider`, `.codex`, `.continue`) копируется с ПК1 (`PC1_MOUNT`, по умолчанию `/mnt/PC1`) только в RAM-home; в песочнице `/home`, `/mnt`, `/media`, `/run` и точка монтирования ПК1 скрыты. `session-deliver` кладёт тот же патч в `PC1_PROJ` (по умолчанию `$PC1_MOUNT$PROJECT_SRC`).

---

## 4. Ключевые решения

| Решение | Почему | Альтернатива и почему хуже |
|---|---|---|
| Обычная загрузка + tmpfs, **не Debian Live** | драйверы, ROCm, библиотеки остаются на диске; в RAM только записи | Live+`toram`: пересборка образа на каждое обновление стека, весь образ в RAM |
| **zram** вместо дискового swap | своп в RAM ⇒ tmpfs не уходит на SSD | swap-файл: утечка всей рабочей копии на диск |
| Правки — **через diff** с исключениями | не протаскивает `.o`, `__pycache__`, `.claude/`, `*.log` | `rsync -a` протаскивает мусор — это и есть следы |
| Проект на диске **ro** во время сеанса | запись невозможна по конструкции | «агент не будет писать» — обещание, не гарантия |
| Агент = непривилегированный `sess` в bwrap | не может `apt install`, не пишет в систему | запуск от root: любая команда меняет систему |
| **Без коммита** после deliver | автор коммита в `.git/logs/HEAD` — явный след | авто-коммит «Claude <…>» виден в `git log` |
| `setpriv` вместо `runuser` | не дёргает PAM → нет записей в `wtmp`/`lastlog` | `runuser` пишет в журналы, A1 не достигается |
| `overlayroot` — в резерве | при 64 ГБ он ест тот же бюджет RAM | включать сразу: меньше запаса, сложнее отладка |

---

## 5. Бюджет памяти (64 ГБ)

| Потребитель | ГБ | Примечание |
|---|---|---|
| ОС, ядро, демоны | ~5 | |
| page cache | ~8 | ROCm-библиотеки читаются с диска ro |
| `/run/session` tmpfs | **20** | работа + HOME + кеши; не подлежит reclaim |
| `/tmp`, `/var/tmp`, `/dev/shm` в песочнице | 3×2=6 | **задаётся явно**, иначе bwrap даёт 50 % RAM |
| zram swap | 12 | заявляется, реально 2–4 сжатыми |
| запас | ~25 | |

**Правила:**
- `TMPFS_GB` ≤ RAM − 20. Для 64 ГБ потолок ~24, рабочий минимум 16.
- tmpfs **не** освобождается под давлением и **не** уходит в zram — при переполнении будет ENOSPC, а не OOM. Следить за `df /run/session`.
- 64 ГБ tmpfs сделать нельзя: гарантированный OOM.

---

## 6. Состав поставки

```
debian-ephemeral-session/
├── PLAN.md                       этот документ (самодостаточный)
├── README.md                     краткое описание
├── pc1/
│   ├── install.sh                шлюз: NAT + DHCP/DNS
│   ├── gateway.nft               правила nftables
│   └── dnsmasq-session.conf      DHCP/DNS для ПК2
└── pc2/
    ├── install.sh                установка схемы
    ├── uninstall.sh              полный откат
    ├── session-up                подготовка сеанса (root)
    ├── session-enter             вход в песочницу (root → sess)
    ├── session-deliver           возврат diff на диск (root)
    ├── session-down              снятие сеанса (root)
    ├── verify.sh                 проверка следов
    └── journald-volatile.conf    журнал в RAM
```

**Эталон — файлы в `pc1/` и `pc2/`.** Листинги в §8 — версия 1.0, оставлены для истории ревью и устарели (см. §14.2); копировать скрипты только из каталогов.

---

## 7. Реализация по фазам

### Фаза 0 — подготовка ПК2 (один раз)

```bash
# 1. (v1.1) Отдельный раздел не нужен: ro — bind-маунт каталога проекта.
#    Проект задаётся при запуске: sudo PROJECT_SRC=/home/alex/DSP-GPU session-up
#    ПК1 примонтирован в /mnt/PC1 (или PC1_MOUNT=...), без fsc/cachefilesd.

# 2. Установка схемы (создаст пользователя, journald, profile.d, uninstall)
sudo ./pc2/install.sh

# 3. Зафиксировать версии ROCm — иначе apt upgrade уводит на 7.5
apt-mark showhold | wc -l      # должно быть > 0

# 4. Смоук-тест песочницы ДО первого сеанса
sudo session-up && sudo session-enter --probe; sudo session-down

# 5. Метка времени «до»
sudo session-verify --mark
```

### Фаза 1 — шлюз на ПК1

```bash
ip -br link                       # узнать WAN и LAN
sudo WAN=usb0 LAN=enp3s0 ./pc1/install.sh
```

Проверка с ПК2: `ip route` (единственный шлюз = адрес ПК1), `curl -sI https://github.com | head -1`.

### Фаза 2 — первый сеанс

```bash
sudo session-up
sudo session-enter        # внутри проверить GPU, затем запустить агента
#   rocminfo | grep -m2 gfx  → gfx1201
#   python -c "import torch;print(torch.cuda.is_available())" → True
exit
sudo session-deliver
sudo session-down --poweroff
```

### Фаза 3 — приёмка

Перезагрузиться в обычном режиме, `sudo session-verify`, сверить с §1.

---

## 8. Скрипты (листинги версии 1.0 — УСТАРЕЛИ)

> **Заменено файлами `pc2/*`** (§14.2). Ниже — история; в частности, здесь ещё есть
> ошибки, исправленные в 1.1: `--keep-groups` (нет такой опции bwrap), `--bind … /work`
> на ro-корне (EROFS), `**/.claude*` без `/**`, remount раздела, патч от индекса.

### 8.1 `/usr/local/sbin/session-up`

```bash
#!/bin/bash
set -euo pipefail
SESSION_USER="${SESSION_USER:-sess}"
SESSION_ROOT="${SESSION_ROOT:-/run/session}"
LOCK="${LOCK:-/run/session.lock}"
TMPFS_GB="${TMPFS_GB:-20}"
ZRAM_GB="${ZRAM_GB:-12}"
PROJECT_SRC="${PROJECT_SRC:-/data/proj}"
WARM_CACHE="${WARM_CACHE:-/var/cache/rocm-warm}"

log() { printf '\033[1;34m[session-up]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[session-up]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "нужен root"
id "$SESSION_USER" >/dev/null 2>&1 || die "нет пользователя $SESSION_USER"
[ -d "$PROJECT_SRC" ] || die "не найден проект: $PROJECT_SRC"
command -v bwrap >/dev/null 2>&1 || die "нет bubblewrap"

# --- защита от повторного/параллельного запуска ---
exec 9>"$LOCK"
flock -n 9 || die "сеанс уже идёт (lock $LOCK)"
if mountpoint -q "$SESSION_ROOT"; then
  die "tmpfs уже смонтирован — сначала session-down"
fi
if fuser -m "$SESSION_ROOT" >/dev/null 2>&1; then
  die "в $SESSION_ROOT ещё есть процессы"
fi

# --- swap только в RAM ---
log "swap → zram"
swapoff -a || true
modprobe zram
swapoff /dev/zram0 2>/dev/null || true
echo 1 > /sys/block/zram0/reset
echo "${ZRAM_GB}G" > /sys/block/zram0/disksize
mkswap /dev/zram0 >/dev/null
swapon /dev/zram0

# --- tmpfs ---
log "tmpfs ${TMPFS_GB}G → $SESSION_ROOT"
mkdir -p "$SESSION_ROOT"
mount -t tmpfs -o "size=${TMPFS_GB}G,mode=0755,nosuid,nodev" tmpfs "$SESSION_ROOT"
mkdir -p "$SESSION_ROOT"/{work,home}
chmod 700 "$SESSION_ROOT/home"

# --- рабочая копия ---
log "копирую $PROJECT_SRC → $SESSION_ROOT/work/proj"
cp -a "$PROJECT_SRC" "$SESSION_ROOT/work/"

# --- тёплый кеш ROCm: привязка к версии ROCm и ядру ---
ROCM_VER="$(dpkg-query -W -f='${Version}' rocm-core 2>/dev/null || echo none)"
KEY="${ROCM_VER}_$(uname -r)"
if [ -d "$WARM_CACHE/$KEY" ]; then
  log "кеш ROCm: $KEY"
  mkdir -p "$SESSION_ROOT/home/.cache" "$SESSION_ROOT/home/.config"
  cp -a "$WARM_CACHE/$KEY/.cache/."  "$SESSION_ROOT/home/.cache/"  2>/dev/null || true
  cp -a "$WARM_CACHE/$KEY/.config/." "$SESSION_ROOT/home/.config/" 2>/dev/null || true
else
  log "кеша для $KEY нет — первый прогон будет медленным"
fi

chown -R "$SESSION_USER:$SESSION_USER" "$SESSION_ROOT"

# --- диск: ro, жёстко, с проверкой ---
TARGET="$(findmnt -n -o TARGET -T "$PROJECT_SRC")"
if [ "$TARGET" = "/" ]; then
  die "проект на корневой ФС — вынеси на отдельный раздел, иначе ro невозможен"
fi
trap 'mount -o remount,rw "$TARGET" 2>/dev/null || true' ERR
mount -o remount,ro "$TARGET" || die "не удалось перевести $TARGET в ro"
findmnt -no OPTIONS -T "$PROJECT_SRC" | grep -qw ro \
  || die "$TARGET не в режиме ro — сеанс не начинаю"
trap - ERR
log "$TARGET → ro"

log "готово: session-enter"
```

### 8.2 `/usr/local/sbin/session-enter`

```bash
#!/bin/bash
set -euo pipefail
SESSION_USER="${SESSION_USER:-sess}"
SESSION_ROOT="${SESSION_ROOT:-/run/session}"
PROJECT_DIR="${PROJECT_DIR:-proj}"
TMP_MB="${TMP_MB:-2048}"

[ "$(id -u)" -eq 0 ] || { echo "нужен root" >&2; exit 1; }
mountpoint -q "$SESSION_ROOT" || { echo "сначала session-up" >&2; exit 1; }

U="$(id -u "$SESSION_USER")"
G="$(id -g "$SESSION_USER")"

GPU=()
[ -e /dev/kfd ] && GPU+=(--dev-bind-try /dev/kfd /dev/kfd)
[ -e /dev/dri ] && GPU+=(--dev-bind-try /dev/dri /dev/dri)

BW=(
  --unshare-pid --unshare-ipc --unshare-uts --unshare-cgroup-try --keep-groups
  --die-with-parent --hostname box
  --ro-bind / /
  --proc /proc
  --dev /dev
  "${GPU[@]}"
  --ro-bind-try /run/systemd/resolve /run/systemd/resolve
  --bind "$SESSION_ROOT/work" /work
  --bind "$SESSION_ROOT/home" /home/sess
  --size $((TMP_MB*1024*1024)) --tmpfs /tmp
  --size $((TMP_MB*1024*1024)) --tmpfs /var/tmp
  --size $((TMP_MB*1024*1024)) --tmpfs /dev/shm
  --clearenv
  --setenv HOME /home/sess
  --setenv USER "$SESSION_USER"
  --setenv LOGNAME "$SESSION_USER"
  --setenv PATH /home/sess/.local/bin:/opt/rocm/bin:/usr/local/bin:/usr/bin:/bin
  --setenv TERM "${TERM:-xterm-256color}"
  --setenv ROCM_PATH /opt/rocm
  --setenv HIP_PATH /opt/rocm
  --setenv MIOPEN_USER_DB_PATH /home/sess/.config/miopen
  --setenv MIOPEN_CUSTOM_CACHE_DIR /home/sess/.cache/miopen
  --setenv HIP_VISIBLE_DEVICES 0
  --setenv PYTHONUSERBASE /home/sess/.local
  --setenv CCACHE_DIR /home/sess/.ccache
  --setenv TRITON_CACHE_DIR /home/sess/.triton
  --setenv PIP_NO_CACHE_DIR 1
  --setenv PIP_DISABLE_PIP_VERSION_CHECK 1
  --setenv PYTHONDONTWRITEBYTECODE 1
  --chdir "/work/$PROJECT_DIR"
)

if [ "${1:-}" = "--probe" ]; then
  exec setpriv --reuid="$U" --regid="$G" --init-groups -- \
    bwrap "${BW[@]}" /bin/bash -c '
      echo "id:        $(id)"
      echo "gid kfd:   $(test -r /dev/kfd && echo ok || echo DENIED)"
      echo "rocm:      $(command -v rocminfo || echo НЕТ)"
      echo "gfx:       $(rocminfo 2>/dev/null | grep -m1 gfx || echo n/a)"
      echo "dns:       $(getent hosts github.com >/dev/null && echo ok || echo FAIL)"
      echo "write home:$(touch /home/sess/.probe && echo ok || echo FAIL)"
      echo "git:       $(git -C /work/proj status --porcelain | wc -l) изменений"
      echo "data ro:   $(findmnt -no OPTIONS -T /data | grep -qw ro && echo ro || echo RW!)"
    '
fi

# PATH из --setenv перетрёт /etc/profile, поэтому ROCm добавлен через profile.d (install.sh)
exec setpriv --reuid="$U" --regid="$G" --init-groups -- bwrap "${BW[@]}" /bin/bash -l
```

### 8.3 `/usr/local/sbin/session-deliver`

```bash
#!/bin/bash
set -euo pipefail
SESSION_ROOT="${SESSION_ROOT:-/run/session}"
SRC_PROJ="${SRC_PROJ:-/data/proj}"
W="$SESSION_ROOT/work/proj"
PATCH="$SESSION_ROOT/out.patch"
SAFE=(-c "safe.directory=$SRC_PROJ" -c "safe.directory=$W")

[ "$(id -u)" -eq 0 ] || { echo "нужен root" >&2; exit 1; }
[ -d "$W/.git" ] || { echo "нет рабочей копии или это не git-репозиторий" >&2; exit 1; }

# Всё, что не относится к исходникам проекта, на диск не едет.
EX=(
  ':(exclude,glob)**/.claude*'  ':(exclude,glob)**/.codex*'
  ':(exclude,glob)**/.cursor*'  ':(exclude,glob)**/.aider*'
  ':(exclude,glob)**/.mcp.json' ':(exclude,glob)**/AGENTS.md'
  ':(exclude,glob)**/CLAUDE.md' ':(exclude,glob)**/*.log'
)

BASE="$(git "${SAFE[@]}" -C "$W" rev-parse HEAD)"
git "${SAFE[@]}" -C "$W" add -A -N -- . "${EX[@]}"
git "${SAFE[@]}" -C "$W" diff --binary -- . "${EX[@]}" > "$PATCH"

if [ ! -s "$PATCH" ]; then
  echo "изменений исходников нет — на диск ничего не пишем"
  exit 0
fi
echo "к применению:"; git "${SAFE[@]}" -C "$W" diff --stat -- . "${EX[@]}" | tail -20

TARGET_BASE="$(git "${SAFE[@]}" -C "$SRC_PROJ" rev-parse HEAD 2>/dev/null || echo none)"
if [ "$TARGET_BASE" != "$BASE" ]; then
  echo "ОШИБКА: база разошлась." >&2
  echo "  рабочая копия: $BASE" >&2
  echo "  диск:          $TARGET_BASE" >&2
  echo "  Патч сохранён: $PATCH — разбери вручную." >&2
  exit 1
fi

TARGET="$(findmnt -n -o TARGET -T "$SRC_PROJ")"
if [ "$TARGET" != "/" ]; then
  mount -o remount,rw "$TARGET" || { echo "не удалось rw $TARGET" >&2; exit 1; }
  trap 'mount -o remount,ro "$TARGET" 2>/dev/null || true' EXIT
fi

if ! git "${SAFE[@]}" -C "$SRC_PROJ" apply --index "$PATCH"; then
  git "${SAFE[@]}" -C "$SRC_PROJ" apply --3way "$PATCH" || {
    echo "ОШИБКА: патч не применился, сохранён в $PATCH" >&2; exit 1; }
fi

echo "применено:"; git "${SAFE[@]}" -C "$SRC_PROJ" diff --cached --stat | tail -20
echo
echo "Коммит не сделан намеренно: автор коммита — это след."
echo "Закоммить своим именем: git -C $SRC_PROJ commit -m '...'"
```

### 8.4 `/usr/local/sbin/session-down`

```bash
#!/bin/bash
set -euo pipefail
SESSION_ROOT="${SESSION_ROOT:-/run/session}"
SRC_PROJ="${SRC_PROJ:-/data/proj}"
PATCH="$SESSION_ROOT/out.patch"
[ "$(id -u)" -eq 0 ] || { echo "нужен root" >&2; exit 1; }

# 1. Спасти невыгруженный патч: единственная копия сейчас в tmpfs.
if [ -f "$PATCH" ]; then
  SAFE=(-c "safe.directory=$SRC_PROJ")
  if ! git "${SAFE[@]}" -C "$SRC_PROJ" apply --reverse --check "$PATCH" 2>/dev/null; then
    KEEP="/var/tmp/session-$(date +%Y%m%d-%H%M%S).patch"
    cp -a "$PATCH" "$KEEP" && sync
    echo "ВНИМАНИЕ: правки, похоже, НЕ на диске. Копия сохранена: $KEEP"
    read -r -p "Снять сеанс всё равно? [y/N] " a
    [ "$a" = "y" ] || exit 1
  fi
fi

# 2. Размонтировать сеанс
if mountpoint -q "$SESSION_ROOT"; then
  if fuser -m "$SESSION_ROOT" >/dev/null 2>&1; then
    echo "в сеансе ещё есть процессы:" >&2; fuser -vm "$SESSION_ROOT" >&2 || true
    exit 1
  fi
  umount "$SESSION_ROOT" || { echo "umount не удался — правки ещё в RAM!" >&2; exit 1; }
fi
rmdir "$SESSION_ROOT" 2>/dev/null || true

# 3. Вернуть swap и диск в штатное состояние
swapoff /dev/zram0 2>/dev/null || true
TARGET="$(findmnt -n -o TARGET -T "$SRC_PROJ" 2>/dev/null || echo '')"
if [ -n "$TARGET" ] && [ "$TARGET" != "/" ]; then
  mount -o remount,rw "$TARGET" 2>/dev/null || true
fi

echo "сеанс снят: tmpfs и zram освобождены, $SRC_PROJ снова rw"
[ "${1:-}" = "--poweroff" ] && systemctl poweroff
exit 0
```

### 8.5 `journald-volatile.conf`

```ini
[Journal]
Storage=volatile
SystemMaxUse=200M
RuntimeMaxUse=200M
ForwardToSyslog=no
```

### 8.6 `/etc/profile.d/00-rocm-session.sh` (ставит install.sh)

```sh
# ROCm в PATH: /etc/profile в Debian перезаписывает PATH, поэтому только так
case ":$PATH:" in *":/opt/rocm/bin:"*) ;; *) PATH="/opt/rocm/bin:$PATH";; esac
export PATH
export ROCM_PATH=/opt/rocm
export HIP_PATH=/opt/rocm
```

### 8.7 `verify.sh` — ключевые блоки

```bash
STAMP="${STAMP:-/var/lib/session-stamp}"
PROJ="${PROJ:-/data/proj}"
SU="${SESSION_USER:-sess}"

# 1. корень — с whitelist системного шума
find / -xdev -newer "$STAMP" \
  -not -path '/proc/*' -not -path '/sys/*' -not -path '/run/*' \
  -not -path '/var/lib/sudo/*' -not -path '/var/lib/systemd/*' \
  -not -path '/var/log/wtmp' -not -path '/var/log/lastlog' \
  -not -path '/var/log/btmp' -not -path '/var/cache/*' \
  -not -path '/var/lib/apt/*' 2>/dev/null | head -60

# 2. /data отдельно: -xdev её не покрывает
find "$PROJ" -newer "$STAMP" -path '*/.git' -prune -o \
  -newer "$STAMP" -print 2>/dev/null | head -40

# 3. конфиги агентов — без ограничения глубины
find "$PROJ" \( -name '.git' -o -name 'node_modules' \) -prune -o \
  \( -name '.claude*' -o -name '.codex*' -o -name '.cursor*' -o -name '.aider*' \
     -o -name 'AGENTS.md' -o -name 'CLAUDE.md' -o -name '.mcp.json' \
     -o -name '*.log' \) -print 2>/dev/null

# 4. домашний каталог: любой непустой = провал A3
[ -d "/home/$SU" ] && find "/home/$SU" -mindepth 1 | head
```

---

## 9. Рабочий цикл (шпаргалка)

```bash
sudo session-up          # tmpfs + zram + копия проекта + кеш, /data → ro
sudo session-enter       # песочница; здесь агент
exit
sudo session-deliver     # на диск едет только diff исходников
sudo session-down --poweroff
```

Обновление тёплого кеша (вручную, после удачного прогона):

```bash
KEY="$(dpkg-query -W -f='${Version}' rocm-core)_$(uname -r)"
sudo mkdir -p "/var/cache/rocm-warm/$KEY"/{.cache,.config}
sudo rsync -a /run/session/home/.cache/miopen /run/session/home/.cache/rocblas \
            "/var/cache/rocm-warm/$KEY/.cache/" 2>/dev/null
sudo rsync -a /run/session/home/.config/miopen "/var/cache/rocm-warm/$KEY/.config/" 2>/dev/null
```

---

## 10. Протокол проверки

```bash
sudo session-verify --mark    # до сеанса, в обычной загрузке
# ... сеанс ...
# перезагрузка
sudo session-verify           # после
```

Скрипт печатает `date -Is` (метка mtime бессмысленна при сбитых часах — нужен `systemd-time-wait-sync`), проверяет 7 блоков из §8.7 и авторство в git.

---

## 11. Чек-лист дня внедрения

- [ ] проект — git-репозиторий; `du -sh` проекта + ИИ-слоя + 6 ГБ ≤ RAM − 20 ГБ (проверяет `session-up`)
- [ ] `install.sh` прошёл, `apt-mark showhold | wc -l` > 0
- [ ] `bwrap --version` работает; `sysctl kernel.unprivileged_userns_clone` = 1 или отсутствует
- [ ] `journald` → volatile, `/var/log/journal` удалён
- [ ] `hibernate.target`, `hybrid-sleep.target` замаскированы
- [ ] `/etc/profile.d/00-rocm-session.sh` на месте
- [ ] `/home/sess` отсутствует (у `sess` нет домашнего каталога)
- [ ] `rocminfo` видит `gfx1201`, `/dev/kfd`, `/dev/dri` на месте
- [ ] `session-enter --probe` — все строки `ok`
- [ ] шлюз на ПК1: `ip_forward`, nft, dnsmasq; с ПК2 `curl -sI https://github.com` — ок
- [ ] `session-verify --mark` выполнен
- [ ] первый полный цикл пройден, `git apply --reverse --check` проходит
- [ ] ребут + `session-verify` — чисто

---

## 12. Риски и ограничения

### 12.1 Принципиальные

- **Факт включения машины скрыть нельзя**: SMART power-on hours, число включений, счётчики NIC, `/sys/fs/pstore` при панике. Скрывается работа агента, не факт работы компьютера.
- **`mtime` изменённых файлов останется** — неотличим от правки человека.
- **Принцип «не писать», а не «писать и стирать»**: надёжно стереть нельзя, ext4 хранит остатки в свободных блоках.

### 12.2 Технические

| Риск | Митигация |
|---|---|
| `bwrap` не стартует (userns запрещены) | `session-enter --probe` до сеанса |
| записи в `/var` из песочницы | `--tmpfs /var/tmp`, whitelist в verify |
| потеря правок при отключении питания | `session-deliver` после каждого шага; патч копируется в `/var/tmp` |
| переполнение tmpfs в середине сборки | `TMPFS_GB` под задачу, контроль `df` |
| MIOpen компилирует ядра каждый раз | тёплый кеш с версионной привязкой |
| `apt upgrade` ломает torch | `apt-mark hold` по фактическим именам |
| `/dev/kfd` недоступен в userns | `--keep-groups`; резерв — ACL через udev |
| `pypi.org` не отвечает с сети ПК2 | кэш-прокси на ПК1 или предзагрузка колёс |
| проект не на отдельном разделе | (v1.1) не нужно: ro-bind каталога проекта |
| проект ~20 ГБ не влезает в tmpfs | `session-up` считает `du` проекта + ИИ-слоя, `TMPFS_GB` по умолчанию = данные + 6 ГБ, отказ при RAM − tmpfs < 20 ГБ |
| ИИ-слой с ПК1 через NFS `fsc` кешируется на диск ПК2 | монтировать ПК1 без `fsc`, без `cachefilesd` |

### 12.3 Сеть (проверено в этой сессии)

- С домашней сети `pypi.org:443` — **timeout** при живом `github.com:443`. `pip install` внутри сеанса будет виснуть ⇒ зависимости держать на диске ПК2 или поднимать кэш-прокси.
- Внешние адреса, работавшие как VPN-выходы, блокируются по IP (ICMP + все порты), соседи по подсети при этом живы. Вывод: **не завязывать сеанс на конкретный внешний адрес**.

---

## 13. Открытые решения

1. `TMPFS_GB`: 20 или 16 (зависит от `du -sh /opt/rocm`)?
2. Зависимости: предзагрузка колёс в ro-каталог или кэш-прокси?
3. `session-deliver`: коммитить именем владельца или оставлять дерево грязным?
4. Тёплый кеш: обновлять автоматически после сеанса или только вручную?
5. Нужен ли `cloudflared` как резервный вход на ПК2?

---

## 14. Ревью: что найдено и что изменено

Документ прошёл состязательное ревью независимым агентом. Закрытые блокеры:

| # | Находка | Что изменено |
|---|---|---|
| B1 | `bash -l` перетирает `PATH` из `--setenv` (`/etc/profile`), ROCm не виден | добавлен `/etc/profile.d/00-rocm-session.sh` (§8.6), PATH пересобран |
| B2 | `install.sh` падал: нет каталога `/etc/systemd/journald.conf.d` | `install -d`, плюс `rm -rf /var/log/journal` |
| B3 | повторный `session-up` падал на `disksize` (EBUSY) | `echo 1 > /sys/block/zram0/reset` |
| B4 | `rm -rf` рабочей копии мог уничтожить живой сеанс | `flock` + проверки `mountpoint`/`fuser` |
| B5 | `git add -A -N` тащил `.claude/`, `AGENTS.md`, `*.log` — провал A5 | pathspec-исключения в deliver |
| B6 | правки могли пропасть: патч только в tmpfs | копия в `/var/tmp` + подтверждение в `session-down` |
| B7 | `|| true` глушил ошибки git, `--3way` без базовых блобов | проверка `BASE == TARGET_BASE`, без `|| true`, `-c safe.directory` |

Существенные (MAJOR):

| # | Находка | Что изменено |
|---|---|---|
| M1 | fstab `ro` противоречил «закоммить своим именем» | fstab `rw`; ro ставит/снимает только сеанс |
| M2 | `runuser` пишет `wtmp`/`lastlog` → A1 недостижим | заменён на `setpriv`, whitelist в verify |
| M3 | нет `/dev/shm`, `/var/tmp`, `/run/systemd/resolve` | явные tmpfs + `--ro-bind-try` |
| M4 | группа `render` теряется в userns → EACCES на `/dev/kfd` | `--keep-groups`, резерв — ACL |
| M5 | `adduser` создаёт `/home/sess` со skel → A3 провален | `useradd --no-create-home`, `rm -rf` |
| M6 | `verify.sh` слеп к `/data` и вложенным каталогам | отдельные блоки, без `-maxdepth` |
| M7 | отказ `remount,ro` только логировался | `die` + проверка `findmnt ... ro` |
| M8 | `--tmpfs` без `--size` даёт 50 % RAM | явные размеры для `/tmp`, `/var/tmp`, `/dev/shm` |
| M9 | `nft` дубли таблиц, `policy drop` ломает форвардинг хоста | уникальные таблицы, `delete`, точечные правила |
| M10 | `apt-mark hold 'rocm*'` не понимает глобы | имена из `dpkg-query`, проверка `showhold` |

Добавлено по итогам «пробелов»: `uninstall.sh` (полный откат), режим `session-enter --probe` (смоук-тест до сеанса), копия патча в `/var/tmp`, версионная привязка кеша, whitelist в `verify.sh`, проверка единственного маршрута у ПК2.

**Легенда серьёзности:** B — приводило к потере данных или к провалу приёмки; M — работало, но неверно или небезопасно; m — косметика и расхождения.

### 14.2 Второе ревью (v1.1) — исправлено в `pc2/*`, `pc1/install.sh`

| # | Находка | Что изменено |
|---|---|---|
| B8 | `bwrap --keep-groups` — такой опции нет, `session-enter` не стартовал | убрано; группы даёт `setpriv --init-groups`, в userns они сохраняются (проверено) |
| B9 | `--bind … /work` поверх `--ro-bind / /` → `Can't mkdir /work: Read-only file system` | корень песочницы = tmpfs bwrap + ro-bind системных каталогов, в конце `--remount-ro /` |
| B10 | `**/.claude*` не исключает содержимое каталогов: `.claude/…`, `.cursor/…` уезжали в патч | к каждому шаблону добавлен `**/<имя>*/**` (проверено на git) |
| B11 | патч = рабочее дерево − **индекс**: `git add` агента молча терялся; коммит агента ломал deliver | база — снимок в `session-up` (`state/base.tree`, объекты вне песочницы); патч = база → текущее дерево |
| B12 | `session-down` проверял только старый `out.patch`: без deliver или после него правки терялись без предупреждения | `session-down` пересобирает патч (`session-deliver --patch-only`) |
| B13 | `cp -a $PROJECT_SRC work/` давал `work/<имя>`, а enter/deliver ждут `work/proj` | копия всегда в `work/proj` |
| B14 | git в рабочей копии запускался root-ом вне песочницы: фильтры/fsmonitor из `.git/config` агента = запись на диск | сборка патча в отдельном bwrap от `sess`, без сети, рабочая копия ro |
| M11 | патч применялся root-ом: root-овые файлы/каталоги в проекте и `.git/objects` владельца, на NFS — root_squash | `git apply` от владельца репозитория (`setpriv`, его HOME) на ПК2 и ПК1 |
| M12 | remount всего раздела; проект в `/home/alex` (корневая ФС) → отказ | ro-bind самого каталога; `session-down`/`deliver` снимают только свои маунты |
| M13 | песочница видела `/home/alex` и `/mnt/PC1` (ИИ-слой, настоящий проект) | скрыты `/home`, `/root`, `/mnt`, `/media`, `/run`, верх `PC1_MOUNT` |
| M14 | `swapoff -a \|\| true`: при отказе дисковый swap оставался | ошибка = отказ; проверка, что swap только zram |
| M15 | нет проверки размера: 20 ГБ проекта в tmpfs 20 ГБ | `du` проекта + ИИ-слоя, авторазмер, проверка остатка RAM |
| M16 | `fuser -m /run/session` на немонтированном каталоге ловит всех пользователей `/run` | проверка убрана (есть `mountpoint`) |
| M17 | повторный deliver повторно нёс уже применённое | база сдвигается после успешного применения |
| m5 | `uninstall.sh` снимал **все** hold; `pc1/install.sh` затирал `/etc/nftables.conf` | только ROCm-пакеты; бэкап `nftables.conf.pre-session` |

---

## Приложение A. Резервные варианты

**A.1 `overlayroot`** — пакет есть в trixie (0.18.debian14). `overlayroot="tmpfs"` → корень ro + overlay upper в RAM. Для AMD безопасно (нет dkms). Минус: делит RAM с сеансом. Включать, если понадобится «ноль записей в корень».

**A.2 Debian Live + `toram`** — только для физически отдельного носителя. Не рекомендуется: пересборка образа, весь образ в RAM.

**A.3 btrfs-снапшот** — работать в снапшоте, затем удалить. Проще overlayroot, но записи на диск всё равно идут.

---

## Приложение B. Справочные команды

```bash
# GPU
rocminfo | grep -m2 gfx
rocm-smi
python3 -c "import torch;print(torch.__version__, torch.version.hip, torch.cuda.is_available())"

# память
free -h; zramctl; df -h /run/session

# состояние сеанса
findmnt /run/session; findmnt /data
fuser -vm /run/session
cat /run/session.lock 2>/dev/null

# откат
sudo /usr/local/sbin/uninstall-session-scheme
```
