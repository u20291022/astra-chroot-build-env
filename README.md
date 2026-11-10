# astra-chroot-build-env

Сборка свежих программ на **Astra Linux 1.7 / Debian 10+** без обновления системы.

На старой системе многое не собирается: glibc 2.28 и GCC 8 не знают C++20/23 и новых
функций, а обновлять саму ОС нельзя или не хочется. Этот инструмент:

1. создаёт рядом chroot с современным Debian (по умолчанию 13 trixie: GCC 14, glibc 2.41);
2. даёт войти в него из папки проекта одной командой — как `venv` в Python;
3. устанавливает собранную программу **на хост**, прописывая ей загрузчик и библиотеки
   из chroot. Программа запускается нативно, видит ваши файлы, шрифты, терминал и
   инструменты, а система остаётся нетронутой.

```text
~/проект $ activate-build-env
(build-env) $ make
(build-env) $ install-binary-from-build-env ./myprogram
(build-env) $ exit
~/проект $ myprogram          # работает на хосте с glibc 2.41 из chroot
```

А если собирать ничего не хочется — **astra-get**, пакетный менеджер поверх всего этого:

```text
$ astra-get install https://github.com/zed-industries/zed    # готовый релиз с GitHub
$ astra-get install htop-dev/htop                            # нет релиза -> соберёт сам
$ astra-get install deb:krita                                # пакет Debian trixie
$ astra-get-gui                                              # то же в окне
```

## Установка

```bash
wget -qO- https://raw.githubusercontent.com/u20291022/astra-chroot-build-env/main/install.sh | bash
```

Установщик:

- кладёт `activate-build-env`, `install-binary-from-build-env`, `update-build-env`, `astra-get`
  и `astra-get-gui` в `~/.local/bin`, ярлык «astra-get» — в меню приложений;
- создаёт chroot в `~/.local/share/astra-build-env/trixie` (≈300 МБ загрузки, 1–2 ГБ с пакетами);
- ставит в него компиляторы и сборочные утилиты;
- проводит короткий экскурс: собирает и устанавливает [btop](https://github.com/aristocratos/btop).

Параметры передаются после `bash -s --`:

```bash
wget -qO- https://raw.githubusercontent.com/u20291022/astra-chroot-build-env/main/install.sh | bash -s -- --no-tour
```

| Параметр | Что делает |
|---|---|
| `--chroot ПАПКА` | где создать chroot или какой существующий использовать |
| `--suite ИМЯ` | версия Debian (`trixie`, `bookworm`, `sid`) |
| `--mirror URL` | зеркало Debian |
| `--no-tour` | без экскурса с btop |
| `--skip-packages` | не ставить сборочные пакеты |
| `-y` | без вопросов |
| `--uninstall` | удалить скрипты и настройки |
| `--remove-chroot ПАПКА` | удалить chroot |

Требования: x86_64, `sudo`, `wget` или `curl`. На хосте не нужны ни git, ни компилятор.

Повторный запуск установщика безопасен: он обновит скрипты и не тронет существующий chroot.

## astra-get: установка в одну команду

`astra-get` понимает три вида источников и сам выбирает, как ставить:

| Что указать | Что произойдёт |
|---|---|
| ссылку на GitHub или `владелец/репозиторий` | берёт последний релиз и выбирает файл под Linux x86_64: `.deb`, архив, AppImage или бинарник |
| то же, но релиза под Linux нет | клонирует исходники и собирает (см. ниже, какие системы сборки) |
| `deb:пакет` или просто имя пакета | ставит пакет Debian trixie в chroot и выводит программу на хост |
| прямую ссылку на `.deb`/архив/AppImage | скачивает и ставит этот файл |

Известные программы ставятся просто по имени:

```bash
astra-get install zed          # редактор Zed (Vulkan из chroot)
astra-get install helium       # браузер Helium
astra-get install python       # свежий CPython (python-build-standalone): команды python3.X и pip3.X
astra-get install python@3.13  # конкретная версия; системный python3 не перекрывается
astra-get install uv           # uv и uvx
```

```bash
astra-get install https://github.com/sharkdp/bat
astra-get install helix-editor/helix --name helix
astra-get install htop-dev/htop                  # сборка из исходников
astra-get install deb:mousepad
astra-get search markdown                        # поиск в Debian и на GitHub
astra-get resolve zed-industries/zed             # что будет поставлено, без установки
astra-get list
astra-get update                                 # проверить обновления
astra-get update --all                           # поставить все
astra-get rollback zed                           # вернуть прошлую версию
astra-get remove bat
astra-get track zed                              # подключить к обновлениям старую установку
```

Системы сборки, которые astra-get узнаёт по файлам проекта:

| Язык | Файл | Как собирается | Что ставится при первой встрече |
|---|---|---|---|
| Rust | `Cargo.toml` | `cargo build --release` | rustup со свежим Rust (в домашнюю папку chroot) |
| Go | `go.mod` | `go build` (`GOTOOLCHAIN=auto` — нужная версия Go скачается сама; сначала статически без cgo) | `golang-go` |
| Zig | `build.zig` | `zig build` (версия из `build.zig.zon`) | официальный Zig нужной версии |
| Haskell | `stack.yaml` / `*.cabal` | `stack build` / `cabal install` | `haskell-stack` или `ghc` + `cabal-install` |
| C/C++ | `meson.build`, `CMakeLists.txt`, `configure(.ac)`, `*.pro`, `Makefile` | meson, cmake, autotools, qmake, make | базовые — при установке; для qmake — Qt 6 |
| Nim | `*.nimble` | `nimble build` | `nim`, `nimble` |
| D | `dub.json` / `dub.sdl` | `dub build` | `ldc`, `dub` |
| Python | `pyproject.toml` / `setup.py` | `pip install` в собственный переносимый Python программы | python-build-standalone 3.13 |
| Node.js | `package.json` с `bin` | `npm install`, `npm run build`, свой `node` внутри программы | официальный Node.js LTS |

Базовые инструменты (компилятор C/C++, make, cmake, meson, autotools, pkg-config, apt-file)
ставит `install.sh`; всё остальное — только когда встретится проект на этом языке. Если
программа выпущена одним бинарником без расширения (как `greenclip`), astra-get возьмёт его
из релиза и собирать не будет. Прокси из окружения (`https_proxy` и др., например системный
прокси Clash) передаётся и в сборку внутри chroot.

**Недостающие пакеты для сборки.** Если сборка падает на отсутствующем заголовке
(`fatal error: boost/foreach.hpp: No such file or directory`), библиотеке (`cannot find -lfoo`),
файле pkg-config или модуле CMake, astra-get сам ищет пакет Debian с этим файлом через `apt-file`,
ставит его в chroot и повторяет сборку. Найденные пакеты запоминаются (`DEPS` в `.update`),
и при обновлении ставятся сразу, без повторных попыток. Если пакет найти не удалось, их можно
указать вручную — astra-get подскажет команду поиска:

```bash
activate-build-env -- apt-file search boost/foreach.hpp     # какой пакет даёт файл
astra-get install fph/bastet --source --deps 'libboost-dev libncurses-dev'
```

В окне `astra-get-gui` для этого есть поле «Пакеты для сборки».

Что astra-get делает сам, без подсказок:

- **недостающие библиотеки** ищет по индексу пакетов Debian (`apt-file`) и ставит в chroot;
  для `.deb` дополнительно ставит его зависимости — так находятся библиотеки, которые
  программа грузит через `dlopen` (например, иконка в трее);
- **при сборке из исходников** сначала одним разом ставит всё, что объявлено в `meson.build`,
  `CMakeLists.txt` и `configure.ac`, плюс зависимости сборки пакета Debian с тем же именем
  (`apt-get build-dep`); если чего-то всё равно не хватит — читает ошибки компилятора,
  `pkg-config`, `meson`, `cmake` и `configure`, доставляет пакеты и повторяет сборку, пока
  каждая попытка что-то находит (до 25 раз);
- **пароль sudo** спрашивается один раз на всю операцию: astra-get открывает один сеанс
  build-env (`activate-build-env --session`) и выполняет в нём все шаги;
- **GPU** (Vulkan/OpenGL) — `--gpu`; **GTK** — модули, схемы и иконки из chroot; **Qt** — плагины
  из chroot; **Electron** — запуск с `--no-sandbox`;
- **WebKitGTK** (Tauri-приложения): путь к процессам WebKit зашит в библиотеку, поэтому
  программа получает копию `libwebkit2gtk` с путём, заменённым на ссылку `~/.abe/ID`;
- **пакеты Debian**: копирует программы, ярлыки и иконки, данные оставляет в chroot. Если
  программа ищет данные по жёсткому пути (`/usr/lib/x86_64-linux-gnu/mousepad`), создаёт на хосте
  ссылку на каталог в chroot (через sudo, только если такого каталога на хосте нет; удаляется
  вместе с программой). Отключить: `--no-host-links`.

Окно `astra-get-gui` (нужен `python3-pyqt5` из репозитория Astra, установщик предложит его
поставить): список установленного с обновлениями, поиск, установка по ссылке, журнал.
Пароль sudo спрашивает отдельным окном; при входе по отпечатку сначала приложите палец.

Ограничения: GitHub без токена даёт 60 запросов API в час (`export GITHUB_TOKEN=...`), при нехватке
astra-get читает страницы релизов напрямую.

`update-build-env` по-прежнему работает, но `astra-get update` умеет больше источников.

## Использование

### Простая программа

```bash
cd ~/Documents/my-tool
activate-build-env
(build-env) $ cargo build --release
(build-env) $ install-binary-from-build-env --strip target/release/my-tool
(build-env) $ exit
my-tool
```

### Программа с данными (`make install`, CMake, Meson)

Соберите с префиксом итоговой папки, установите во временную и поставьте деревом:

```bash
cd ~/Documents/btop
activate-build-env
(build-env) $ make -j4
(build-env) $ make install PREFIX="$BUILD_ENV_OPT/btop" DESTDIR="$PWD/stage"
(build-env) $ install-binary-from-build-env --strip --tree "stage$BUILD_ENV_OPT/btop"
(build-env) $ exit
```

Ярлыки из `share/applications` появятся в меню (rofi, KDE, Fly) с правильными путями и иконками.

### Не хватает библиотеки для сборки

```bash
activate-build-env --root apt install libsdl2-dev
```

### Одна команда без входа в оболочку

```bash
activate-build-env make -j4
```

### Управление установленным

```bash
install-binary-from-build-env --list
install-binary-from-build-env --remove btop
install-binary-from-build-env --help      # все параметры и сложные случаи
```

## Обновление программ

`update-build-env` проверяет, вышли ли новые версии, и ставит их так же, как
`install-binary-from-build-env`: с загрузчиком и библиотеками из chroot и с теми же
параметрами, что и прошлая установка (`--gpu`, `--env`, `--link`...).

```bash
update-build-env --track zed                      # известная программа: источник уже знаком
update-build-env --track clash-verge
update-build-env --track helix github:helix-editor/helix --asset 'x86_64-linux\.tar\.xz$'

update-build-env                                  # что можно обновить
update-build-env --install                        # поставить все обновления (один пароль sudo)
update-build-env --install zed                    # только одну программу
update-build-env --chroot                         # обновить пакеты самого chroot
```

Перед установкой текущая версия сохраняется: `update-build-env --rollback ИМЯ` вернёт её.
Если программе нужны вспомогательные файлы из chroot внутри себя (например, процессы
WebKit у Tauri-приложений: `--env WEBKIT_EXEC_PATH=@APP@/lib/webkit2gtk-4.1`), они
определяются при `--track` и копируются из chroot заново при каждом обновлении.

Источник — последний релиз на GitHub. Подходят `.deb`, архивы `.tar.*`/`.zip`, AppImage
и одиночный бинарник. Программы, собранные из исходников, обновляются пересборкой.

**Встроенные автообновления программ отключайте** (в Zed: `"auto_update": false`):
они скачивают официальную сборку поверх пропатченной, и та перестаёт запускаться
(`GLIBC_2.29 not found`). Пакеты `.deb` таких программ не ставьте на хост через `dpkg -i`.

Уведомление о новых версиях при входе в сеанс (не чаще раза в 20 часов):
добавьте `update-build-env --notify` в автозапуск, например в `~/.config/awesome/rc.lua`:

```lua
awful.spawn.with_shell("sleep 60; update-build-env --notify")
```

## Что где лежит

| Путь | Что |
|---|---|
| `~/.local/share/astra-build-env/trixie` | chroot |
| `~/.config/astra-build-env/config` | путь к chroot |
| `~/.local/opt/buildenv/ИМЯ` | установленные программы (`.update` — откуда их обновлять) |
| `~/.local/bin` | ссылки на них |
| `~/.local/share/applications` | ярлыки |

> **Не удаляйте и не переносите chroot**, пока установлены программы: путь к нему
> прописан в их бинарниках. Обновлять пакеты внутри (`update-build-env --chroot`) можно.

## Как это работает

- `activate-build-env` монтирует в chroot `/proc`, `/sys`, `/dev`, `/run`, папку проекта и
  папки установки (по тем же путям), затем открывает оболочку от вашего UID.
  После выхода монтирования снимаются, если в chroot не осталось процессов.
- `install-binary-from-build-env` через `ldd` находит зависимости, копирует программу в
  `~/.local/opt/buildenv` и с помощью `patchelf` прописывает ей загрузчик
  `ld-linux` и `RPATH` из chroot. Библиотеки из папки проекта копируются рядом.
- Внутри процесса программы — только библиотеки chroot, а дочерние процессы
  (терминал, git, компиляторы хоста) запускаются уже хостовым загрузчиком.

Ограничения и что с ними делать (плагины по встроенным путям, GTK/Qt, Python,
статические Go/Rust-сборки) описаны в `install-binary-from-build-env --help`.

## Безопасность

Для монтирования и chroot нужен `sudo`, пароль спрашивается при входе в окружение.
`activate-build-env --root` даёт root-оболочку внутри chroot, поэтому правило
`NOPASSWD` для этого скрипта равносильно root без пароля — не рекомендуется.

## Удаление

```bash
wget -qO- https://raw.githubusercontent.com/u20291022/astra-chroot-build-env/main/install.sh | bash -s -- --uninstall
wget -qO- https://raw.githubusercontent.com/u20291022/astra-chroot-build-env/main/install.sh | bash -s -- --remove-chroot ~/.local/share/astra-build-env/trixie
```

`--uninstall` предложит удалить и установленные программы. `--remove-chroot` откажется
работать, пока в chroot что-то смонтировано, и не выйдет за пределы его файловой системы.

## Лицензия

MIT
