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

## Установка

```bash
wget -qO- https://raw.githubusercontent.com/u20291022/astra-chroot-build-env/main/install.sh | bash
```

Установщик:

- кладёт `activate-build-env` и `install-binary-from-build-env` в `~/.local/bin`;
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

## Что где лежит

| Путь | Что |
|---|---|
| `~/.local/share/astra-build-env/trixie` | chroot |
| `~/.config/astra-build-env/config` | путь к chroot |
| `~/.local/opt/buildenv/ИМЯ` | установленные программы |
| `~/.local/bin` | ссылки на них |
| `~/.local/share/applications` | ярлыки |

> **Не удаляйте и не переносите chroot**, пока установлены программы: путь к нему
> прописан в их бинарниках. Обновлять пакеты внутри (`activate-build-env --root apt upgrade`)
> можно.

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
