#include "agent.h"

UNIFEX_TERM create(UnifexEnv *env) {
  State *state = unifex_alloc_state(env);
  if (!state) {
    return unifex_raise(env, "not enough memory");
  }

  state->ctx = g_main_context_new();
  if (!state->ctx) {
    return unifex_raise(env, "not enough memory");
  }

  return 0;
}

UNIFEX_TERM destroy(UnifexEnv *env, UnifexNifState *state) {
  return enif_make_atom(env, "ok");
}
