#include <stdio.h>
#include <gnu/libc-version.h>

void greet(void) { printf("hello from glibc %s\n", gnu_get_libc_version()); }
