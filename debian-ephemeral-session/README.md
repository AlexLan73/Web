# Эфемерные сеансы агента на ПК2

Готовый комплект: агент работает на ПК2 (GPU), всё состояние сеанса — в RAM,
на диске остаются только правки проекта, которые человек вернул сам.

**Главный документ — [PLAN.md](PLAN.md):** архитектура, бюджет памяти,
протокол приёмки, риски, результаты ревью. **Эталон скриптов — файлы в
`pc1/` и `pc2/`** (перечень — PLAN.md §8).

## Состав

```
pc1/                     шлюз: интернет с USB-тетеринга раздаётся на ПК2
  install.sh             NAT + DHCP/DNS, точечные правила nftables
  gateway.nft            правила (идемпотентные, не ломают docker/libvirt)
  dnsmasq-session.conf   DHCP/DNS для ПК2

pc2/                     вычислительный узел
  install.sh             установка: пользователь, journald→RAM, profile.d, hold ROCm
  uninstall.sh           полный откат
  session-up             tmpfs + zram + копия проекта + ИИ-слой с ПК1 в RAM, ro-bind проекта
  session-enter          песочница bwrap (/home, /mnt, ПК1 скрыты); --probe для смоук-теста
  session-deliver        на диск ПК2 и в репозиторий ПК1 едет только diff исходников
  session-down           снять сеанс, спасти невыгруженный патч
  verify.sh              проверка следов (9 блоков)
  journald-volatile.conf журнал в RAM
```

## Быстрый старт

```bash
# ПК1
sudo WAN=usb0 LAN=enp3s0 ./pc1/install.sh

# ПК2
sudo ./pc2/install.sh
sudo session-verify --mark

# цикл (ПК1 примонтирован в /mnt/PC1 или PC1_MOUNT=...)
sudo PROJECT_SRC=/home/alex/DSP-GPU session-up
sudo session-enter --probe      # смоук-тест до первого сеанса
sudo session-enter              # здесь работает агент
exit
sudo session-deliver
sudo session-down --poweroff
```

## Три правила, без которых схема не работает

1. **ИИ-слой только с ПК1 и только в RAM.** На диске ПК2 его нет (проверяет
   `session-verify`, блок 9); в патч он не попадает.
2. **Правки возвращаются diff-ом**, а не копированием каталога: иначе в проект
   уедут `__pycache__`, `*.o`, `.claude/` и `*.log` — то есть следы.
3. **Коммит делает человек.** Автор коммита в `.git/logs/HEAD` — самый явный
   след работы агента.

## Требования

Debian 13 (trixie), ext4, AMD RX 9070 (`gfx1201`), системный ROCm 7.4.2,
не менее 64 ГБ RAM, `bubblewrap`. Подробнее — §2 и §5 в [PLAN.md](PLAN.md).
