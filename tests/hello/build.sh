#!/bin/bash
# Запускается внутри activate-build-env: собирает программу со своей библиотекой
# и устанавливает её на хост.
set -euo pipefail
gcc -shared -fPIC greet.c -o libgreet.so
gcc main.c -L. -lgreet -Wl,-rpath,'$ORIGIN' -o hello
install-binary-from-build-env --desktop --terminal hello
