#!/bin/bash
# astra-chroot-build-env — установка.
#
#   wget -qO- https://raw.githubusercontent.com/u20291022/astra-chroot-build-env/main/install.sh | bash
#   wget -qO- .../install.sh | bash -s -- --help
set -euo pipefail

REPO=u20291022/astra-chroot-build-env
REF=${BUILD_ENV_REF:-main}
SUITE=trixie
MIRROR=https://deb.debian.org/debian
CHROOT=""
TOUR=ask
ASSUME_YES=0
SKIP_PACKAGES=0
ACTION=install
REMOVE_TARGET=""

BIN_DIR=$HOME/.local/bin
OPT_DIR=$HOME/.local/opt/buildenv
CONFIG_DIR=$HOME/.config/astra-build-env
CONFIG=$CONFIG_DIR/config
WORK_DIR=$HOME/.cache/astra-build-env
MARK="# astra-chroot-build-env"

PACKAGES="build-essential git curl wget ca-certificates patchelf binutils pkg-config
cmake meson ninja-build ncurses-term kitty-terminfo xz-utils unzip file"

if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else B=""; G=""; Y=""; R=""; N=""; fi

say()  { printf '\n%s==> %s%s\n' "$B" "$*" "$N"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '    %s!%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '\n%sОшибка:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
astra-chroot-build-env — сборка свежих программ на Astra Linux / Debian 10+
в chroot с новым Debian и установка их на хост.

Использование:
  install.sh [параметры]                 установить или обновить
  install.sh --uninstall                 удалить скрипты и настройки
  install.sh --remove-chroot ПАПКА       удалить chroot

Параметры:
  --chroot ПАПКА     где chroot (по умолчанию ~/.local/share/astra-build-env/$SUITE).
                     Если там уже есть chroot, он будет использован.
  --suite ИМЯ        версия Debian для нового chroot (по умолчанию $SUITE)
  --mirror URL       зеркало Debian (по умолчанию $MIRROR)
  --ref ВЕТКА        ветка или тег репозитория для скачивания скриптов (по умолчанию $REF)
  --skip-packages    не устанавливать сборочные пакеты в chroot
  --tour / --no-tour показать или пропустить экскурс с примером (btop)
  -y, --yes          не задавать вопросов

Через wget параметры передаются так:
  wget -qO- https://raw.githubusercontent.com/$REPO/main/install.sh | bash -s -- --uninstall
EOF
}

# Как пользователю перезапустить этот скрипт (из файла или через wget)
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SELF_CMD="bash ${BASH_SOURCE[0]}"
else
  SELF_CMD="wget -qO- https://raw.githubusercontent.com/$REPO/main/install.sh | bash -s --"
fi

has_tty() { (exec </dev/tty) 2>/dev/null; }

ask() {  # ВОПРОС y|n
  local def=$2 ans hint
  if [ "$ASSUME_YES" = 1 ]; then return 0; fi
  if ! has_tty; then [ "$def" = y ]; return; fi
  if [ "$def" = y ]; then hint="Y/n"; else hint="y/N"; fi
  printf '    %s [%s] ' "$1" "$hint" > /dev/tty
  read -r ans < /dev/tty || ans=""
  ans=${ans:-$def}
  case "$ans" in [YyДд]*) return 0 ;; *) return 1 ;; esac
}

fetch() {  # URL ФАЙЛ
  if command -v wget >/dev/null 2>&1; then wget -q -O "$2" "$1"
  elif command -v curl >/dev/null 2>&1; then curl -fsSL -o "$2" "$1"
  else die "нужен wget или curl"
  fi
}

config_chroot() {
  [ -f "$CONFIG" ] || return 0
  sed -n 's/^CHROOT=//p' "$CONFIG" | tail -n1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --chroot)        CHROOT=${2:?"--chroot требует папку"}; shift 2 ;;
    --suite)         SUITE=${2:?}; shift 2 ;;
    --mirror)        MIRROR=${2:?}; shift 2 ;;
    --ref)           REF=${2:?}; shift 2 ;;
    --skip-packages) SKIP_PACKAGES=1; shift ;;
    --tour)          TOUR=yes; shift ;;
    --no-tour)       TOUR=no; shift ;;
    -y|--yes)        ASSUME_YES=1; shift ;;
    --uninstall)     ACTION=uninstall; shift ;;
    --remove-chroot) ACTION=remove-chroot; REMOVE_TARGET=${2:?"--remove-chroot требует папку"}; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "неизвестный параметр: $1 (см. --help)" ;;
  esac
done

[ "$(id -u)" -ne 0 ] || die "запускайте от обычного пользователя — sudo будет вызван, когда понадобится"

# --- Удаление chroot -----------------------------------------------------------
remove_chroot() {
  local dir=${1%/} users
  dir=$(readlink -m "$dir")
  [ "$dir" != / ] && [ -n "$dir" ] || die "некорректная папка"
  [ -x "$dir/bin/bash" ] && [ -d "$dir/etc/apt" ] || die "$dir не похож на chroot Debian"
  if findmnt -rn -o TARGET | awk -v d="$dir" '$0 == d || index($0, d "/") == 1 { f = 1 } END { exit !f }'; then
    die "внутри $dir есть смонтированные каталоги — закройте все activate-build-env или перезагрузитесь"
  fi
  say "Удаление chroot $dir"
  users=$(grep -rlsF "$dir/" "$OPT_DIR" "$HOME/.local/bin" 2>/dev/null | head -n 20 || true)
  if [ -n "$users" ]; then
    warn "эти программы используют библиотеки из этого chroot и перестанут запускаться:"
    printf '%s\n' "$users" | sed 's/^/        /' >&2
  fi
  ask "Удалить $dir безвозвратно?" n || { info "Отменено."; exit 0; }
  sudo rm -rf --one-file-system -- "$dir"
  ok "удалено"
  if [ "$(config_chroot)" = "$dir" ]; then
    rm -f "$CONFIG"
    info "Настройка CHROOT сброшена."
  fi
}

# --- Удаление скриптов -------------------------------------------------------------
uninstall() {
  local d f current
  say "Удаление astra-chroot-build-env"
  current=$(config_chroot)
  if [ -d "$OPT_DIR" ] && [ -n "$(ls -A "$OPT_DIR" 2>/dev/null)" ] && [ -x "$BIN_DIR/install-binary-from-build-env" ]; then
    "$BIN_DIR/install-binary-from-build-env" --list
    if ask "Удалить и эти программы?" n; then
      for d in "$OPT_DIR"/*/; do
        [ -d "$d" ] && "$BIN_DIR/install-binary-from-build-env" --remove "$(basename "$d")"
      done
    fi
  fi
  rm -f "$BIN_DIR/activate-build-env" "$BIN_DIR/install-binary-from-build-env"
  rm -rf "$CONFIG_DIR" "$WORK_DIR"
  for f in "$HOME/.profile" "$HOME/.bashrc"; do
    [ -f "$f" ] && grep -qxF "$MARK" "$f" && sed -i "/^$MARK\$/,+1d" "$f"
  done
  ok "скрипты и настройки удалены"
  if [ -n "$current" ] && [ -d "$current" ]; then
    info "Chroot оставлен: $current"
    info "Удалить его:  $SELF_CMD --remove-chroot $current"
  fi
}

# --- Установка -----------------------------------------------------------------------
check_host() {
  say "Проверка системы"
  [ "$(uname -m)" = x86_64 ] || die "поддерживается только x86_64"
  local c
  for c in sudo dpkg-deb gzip awk sed findmnt flock; do
    command -v "$c" >/dev/null 2>&1 || die "не найдена команда $c"
  done
  if [ -r /etc/astra_version ]; then ok "Astra Linux $(cat /etc/astra_version)"
  elif [ -r /etc/debian_version ]; then ok "Debian $(cat /etc/debian_version)"
  else warn "система не похожа на Debian — продолжаю на свой страх и риск"
  fi
  info "Для монтирования и chroot нужен sudo."
  sudo -v || die "sudo недоступен"
  ok "sudo"
}

install_scripts() {
  local src="" s d
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    d=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    [ -f "$d/bin/activate-build-env" ] && src=$d/bin
  fi
  say "Установка скриптов в $BIN_DIR"
  mkdir -p "$BIN_DIR"
  for s in activate-build-env install-binary-from-build-env; do
    if [ -n "$src" ]; then
      cp "$src/$s" "$BIN_DIR/$s.tmp"
    else
      if ! fetch "https://raw.githubusercontent.com/$REPO/$REF/bin/$s" "$BIN_DIR/$s.tmp"; then
        rm -f "$BIN_DIR/$s.tmp"
        die "не удалось скачать $s (ветка $REF репозитория $REPO)"
      fi
    fi
    head -n1 "$BIN_DIR/$s.tmp" | grep -q '^#!/bin/bash' || { rm -f "$BIN_DIR/$s.tmp"; die "скачанный $s повреждён"; }
    chmod +x "$BIN_DIR/$s.tmp"
    mv -f "$BIN_DIR/$s.tmp" "$BIN_DIR/$s"
    ok "$s  ${src:+(из локальной копии)}"
  done
}

ensure_path() {
  local f line
  case ":$PATH:" in *":$BIN_DIR:"*) return 0 ;; esac
  # shellcheck disable=SC2016
  line='case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac'
  for f in "$HOME/.profile" "$HOME/.bashrc"; do
    grep -qxF "$MARK" "$f" 2>/dev/null || printf '\n%s\n%s\n' "$MARK" "$line" >> "$f"
  done
  export PATH="$BIN_DIR:$PATH"
  # shellcheck disable=SC2088
  warn "~/.local/bin добавлен в PATH через ~/.profile и ~/.bashrc — откройте новый терминал"
}

create_chroot() {
  local tmp f p
  say "Создание chroot Debian $SUITE: $CHROOT"
  info "Скачивается около 300 МБ, это займёт 5–15 минут."
  if ! command -v wget >/dev/null 2>&1; then
    info "debootstrap нужен wget."
    sudo apt-get install -y wget || die "установите wget"
  fi
  command -v gpgv >/dev/null 2>&1 || die "не найден gpgv (пакет gpgv)"

  tmp=$(mktemp -d)
  # Свежий debootstrap и ключи архива Debian берутся из самого репозитория Debian,
  # так как в Debian 10 / Astra 1.7 они слишком старые для новых версий.
  fetch "$MIRROR/dists/$SUITE/main/binary-all/Packages.gz" "$tmp/Packages.gz" \
    || fetch "$MIRROR/dists/$SUITE/main/binary-amd64/Packages.gz" "$tmp/Packages.gz" \
    || die "не удалось скачать список пакетов $SUITE"
  for p in debootstrap debian-archive-keyring; do
    f=$(gzip -dc "$tmp/Packages.gz" 2>/dev/null \
      | awk -v p="$p" '$1 == "Package:" { cur = $2 } cur == p && $1 == "Filename:" { print $2; exit }' || true)
    [ -n "$f" ] || die "пакет $p не найден в $SUITE"
    fetch "$MIRROR/$f" "$tmp/$p.deb" || die "не удалось скачать $p"
    dpkg-deb -x "$tmp/$p.deb" "$tmp/root"
  done
  ok "debootstrap $(basename "$(gzip -dc "$tmp/Packages.gz" | awk '$1=="Package:"{c=$2} c=="debootstrap" && $1=="Version:"{print $2; exit}' || true)")"

  mkdir -p "$(dirname "$CHROOT")"
  sudo env DEBOOTSTRAP_DIR="$tmp/root/usr/share/debootstrap" \
    sh "$tmp/root/usr/sbin/debootstrap" --variant=minbase \
    --keyring="$tmp/root/usr/share/keyrings/debian-archive-keyring.gpg" \
    "$SUITE" "$CHROOT" "$MIRROR" \
    || die "debootstrap завершился с ошибкой (лог: $CHROOT/debootstrap/debootstrap.log)"
  rm -rf "$tmp"

  case "$SUITE" in
    sid|unstable)
      echo "deb $MIRROR $SUITE main" | sudo tee "$CHROOT/etc/apt/sources.list" > /dev/null ;;
    *)
      printf 'deb %s %s main\ndeb %s %s-updates main\ndeb https://security.debian.org/debian-security %s-security main\n' \
        "$MIRROR" "$SUITE" "$MIRROR" "$SUITE" "$SUITE" | sudo tee "$CHROOT/etc/apt/sources.list" > /dev/null ;;
  esac
  printf '#!/bin/sh\nexit 101\n' | sudo tee "$CHROOT/usr/sbin/policy-rc.d" > /dev/null
  sudo chmod +x "$CHROOT/usr/sbin/policy-rc.d"
  ok "chroot создан"
}

install_packages() {
  say "Сборочные пакеты в chroot"
  info "$(echo $PACKAGES)"
  sudo cp -L /etc/resolv.conf "$CHROOT/etc/resolv.conf" 2>/dev/null || true
  sudo chroot "$CHROOT" apt-get update -qq || die "apt-get update в chroot завершился с ошибкой"
  # shellcheck disable=SC2086
  if ! BUILD_ENV_CHROOT="$CHROOT" "$BIN_DIR/activate-build-env" --root \
    env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $PACKAGES \
    > "$WORK_DIR/apt.log" 2>&1; then
    tail -n 20 "$WORK_DIR/apt.log" >&2
    die "не удалось установить пакеты (полный лог: $WORK_DIR/apt.log)"
  fi
  ok "пакеты установлены"
}

create_user() {
  local uid gid user group name
  uid=$(id -u); gid=$(id -g); user=$(id -un); group=$(id -gn)
  say "Пользователь в chroot"
  if sudo chroot "$CHROOT" getent passwd "$uid" > /dev/null; then
    ok "уже есть: $(sudo chroot "$CHROOT" getent passwd "$uid" | cut -d: -f1,6)"
    return 0
  fi
  if ! sudo chroot "$CHROOT" getent group "$gid" > /dev/null; then
    sudo chroot "$CHROOT" getent group "$group" > /dev/null && group=$group-build
    sudo chroot "$CHROOT" groupadd -g "$gid" "$group"
  fi
  name=$user
  sudo chroot "$CHROOT" getent passwd "$name" > /dev/null && name=$user-build
  # Домашний каталог отличается от хостового, чтобы не пересекаться с монтированиями
  sudo chroot "$CHROOT" useradd -m -u "$uid" -g "$gid" -d "/home/$user-build" -s /bin/bash "$name"
  ok "$name (UID $uid, дом /home/$user-build внутри chroot)"
}

self_test() {
  say "Проверка окружения"
  mkdir -p "$WORK_DIR"
  (
    cd "$WORK_DIR"
    BUILD_ENV_CHROOT="$CHROOT" "$BIN_DIR/activate-build-env" bash -c \
      'echo "    ✓ gcc $(gcc -dumpfullversion), $(ldd --version | head -n1 | grep -o "[0-9.]*$" | sed "s/^/glibc /")"'
  ) || die "не удалось войти в окружение"
  info "у хоста: glibc $(ldd --version | head -n1 | grep -o '[0-9.]*$')"
}

cheatsheet() {
  cat <<EOF

${B}Как пользоваться${N}

  cd ~/путь/к/проекту
  activate-build-env                         ${Y}# войти в окружение сборки${N}
  (build-env) \$ make                         ${Y}# или cargo build, go build, cmake...${N}
  (build-env) \$ install-binary-from-build-env путь/к/программе
  (build-env) \$ exit

  activate-build-env --root apt install libfoo-dev   ${Y}# не хватает библиотеки для сборки${N}
  install-binary-from-build-env --list               ${Y}# что установлено${N}
  install-binary-from-build-env --remove ИМЯ         ${Y}# удалить программу${N}
  install-binary-from-build-env --help               ${Y}# параметры и сложные случаи${N}

  Chroot: $CHROOT
  Не удаляйте его: установленные программы берут оттуда библиотеки.
EOF
}

tour() {
  local demo=$WORK_DIR/demo j
  say "Экскурс: соберём btop — красивый системный монитор"
  cat <<EOF
    На хосте старые glibc и компилятор, поэтому свежий btop (C++23) здесь не собрать.
    Соберём его в chroot и установим на хост. Руками это выглядит так:

      git clone https://github.com/aristocratos/btop && cd btop
      activate-build-env
      (build-env) \$ make -j4
      (build-env) \$ make install PREFIX="\$BUILD_ENV_OPT/btop" DESTDIR="\$PWD/stage"
      (build-env) \$ install-binary-from-build-env --strip --tree "stage\$BUILD_ENV_OPT/btop"
      (build-env) \$ exit

    PREFIX указывает, где программа будет жить на хосте (там она найдёт свои темы),
    DESTDIR — временная папка, куда make install положит файлы.
EOF
  if [ -d "$OPT_DIR/btop" ]; then
    ok "btop уже установлен через build-env — сборку пропускаю"
    return 0
  fi
  ask "Выполнить это сейчас (≈5 минут)?" y || return 0

  rm -rf "$demo"
  mkdir -p "$demo"
  j=$(nproc); [ "$j" -gt 4 ] && j=4
  (
    cd "$demo"
    BUILD_ENV_CHROOT="$CHROOT" "$BIN_DIR/activate-build-env" bash -c '
      set -e
      tag=$(git ls-remote --tags --refs https://github.com/aristocratos/btop "v*" \
        | awk -F/ "{print \$3}" | grep -E "^v[0-9.]+$" | sort -V | tail -n1)
      echo "    btop $tag"
      git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" https://github.com/aristocratos/btop btop'
    cd btop
    BUILD_ENV_CHROOT="$CHROOT" "$BIN_DIR/activate-build-env" bash -c "
      set -e
      make -j$j >/dev/null 2>build.log || { tail -n 30 build.log; exit 1; }
      echo '    ✓ make'
      make install PREFIX=\"\$BUILD_ENV_OPT/btop\" DESTDIR=\"\$PWD/stage\" >/dev/null
      echo '    ✓ make install'
      install-binary-from-build-env --strip --tree \"stage\$BUILD_ENV_OPT/btop\""
  ) || { warn "демонстрация не удалась, исходники оставлены в $demo"; return 0; }
  rm -rf "$demo"

  cat <<EOF

    ${G}Готово!${N} Запустите ${B}btop${N} в терминале (или найдите в меню приложений).
      readelf -l ~/.local/opt/buildenv/btop/bin/btop | grep interpreter   ${Y}# загрузчик из chroot${N}
      install-binary-from-build-env --remove btop                         ${Y}# удалить${N}
EOF
}

main_install() {
  check_host
  CHROOT=${CHROOT:-$(config_chroot)}
  CHROOT=${CHROOT:-$HOME/.local/share/astra-build-env/$SUITE}
  CHROOT=$(readlink -m "$CHROOT")
  case "$CHROOT/" in "$HOME/.local/bin/"*|"$OPT_DIR/"*) die "неподходящее место для chroot" ;; esac

  install_scripts
  ensure_path

  if [ -x "$CHROOT/bin/bash" ]; then
    say "Chroot"
    ok "использую существующий: $CHROOT ($(cat "$CHROOT/etc/debian_version" 2>/dev/null || echo '?'))"
  else
    create_chroot
  fi

  mkdir -p "$CONFIG_DIR" "$WORK_DIR"
  printf '%s\nCHROOT=%s\n' "$MARK" "$CHROOT" > "$CONFIG"

  cd "$WORK_DIR"
  [ "$SKIP_PACKAGES" = 1 ] || install_packages
  create_user
  self_test

  case "$TOUR" in
    yes) tour ;;
    ask) if has_tty && [ "$ASSUME_YES" = 0 ]; then tour; fi ;;
  esac
  cheatsheet
}

case "$ACTION" in
  install)       main_install ;;
  uninstall)     uninstall ;;
  remove-chroot) remove_chroot "$REMOVE_TARGET" ;;
esac
