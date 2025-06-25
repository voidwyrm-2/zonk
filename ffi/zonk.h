#pragma once

#define ZonkIndex unsigned long

typedef enum {
  ZONK_INC,
  ZONK_DEC,
  ZONK_LEFT,
  ZONK_RIGHT,
  ZONK_LOOP_OPEN,
  ZONK_LOOP_CLOSE,
  ZONK_PUTC,
  ZONK_GETC,
  ZONK_COPY,
  ZONK_JUMP_FORWARD,
  ZONK_JUMP_BACK,
  ZONK_STRING,
  ZONK_IMPORT,
  ZONK_MODULE_SWITCH,
  ZONK_FUNC_CALL,
} ZonkTokenType;

typedef struct {
  ZonkTokenType kind;
  const char *lit;
} ZonkToken;
