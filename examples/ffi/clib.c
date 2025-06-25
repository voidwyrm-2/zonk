#include <stdio.h>
#include <stdlib.h>

#include "../../ffi/zonk.h"

char bfputs(char *mem, ZonkIndex size, ZonkIndex *ptr) {
  ZonkIndex str_size = 1;

  for (ZonkIndex i = *ptr; i < size && mem[i] != 0; i++)
    str_size++;

  char *str = malloc(str_size);
  if (str == NULL)
    return 1;

  for (ZonkIndex i = *ptr; i - *ptr < str_size; i++)
    str[i - *ptr] = mem[i];

  str[str_size - 1] = 0;

  puts(str);

  free(str);

  return 0;
}
