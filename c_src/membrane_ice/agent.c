#include "agent.h"

static void *main_loop_thread_func(void *user_data) {
  GMainLoop *loop = (GMainLoop *)user_data;
  g_main_loop_run(loop);
  g_main_loop_unref(loop);
  return NULL;
}

static gboolean main_loop_schedule_quit(gpointer user_data) {
  GMainLoop *loop = (GMainLoop *)user_data;
  g_main_loop_quit(loop);
  return FALSE;
}

UNIFEX_TERM create(UnifexEnv *env) {
  int err;

  State *state = unifex_alloc_state(env);
  if (!state) {
    return unifex_raise(env, "not enough memory");
  }

  // Zero all state values
  memset(state, 0, sizeof(State));

  state->ctx = g_main_context_new();
  if (!state->ctx) {
    unifex_release_state(env, state);
    return unifex_raise(env, "not enough memory");
  }

  g_main_context_push_thread_default(state->ctx);

  state->loop = g_main_loop_new(state->ctx, FALSE);
  if (!state->loop) {
    unifex_release_state(env, state);
    return unifex_raise(env, "not enough memory");
  }

  err = enif_thread_create("membrane_ice_glib_main_loop", &(state->thread_id),
                           main_loop_thread_func, state->loop, NULL);
  if (err != 0) {
    unifex_release_state(env, state);
    MEMBRANE_WARN(env, "Failed to create main loop thread: %d", err);
    return unifex_raise(env, "failed to create main loop thread");
  }

  g_main_context_pop_thread_default(state->ctx);
  return create_result(env, state);
}

UNIFEX_TERM destroy(UnifexEnv *env, UnifexNifState *state) {
  unifex_release_state(env, state);
  return destroy_result(env);
}

void handle_destroy_state(UnifexEnv *env, UnifexNifState *state) {
  int err;

  if (state->ctx) {
    if (state->loop) {
      if (state->thread_id) {
        // Main loop thread is running, it will unref the loop by itself.
        GSource *source = g_idle_source_new();
        g_source_set_callback(source, main_loop_schedule_quit, state->loop,
                              NULL);
        g_source_attach(source, state->ctx);
        g_source_unref(source);

        // FIXME: This part is shady, we are running in Erlang resource dtor,
        // not sure if joining a thread is legal here.
        err = enif_thread_join(state->thread_id, NULL);
        if (err != 0) {
          MEMBRANE_WARN(env,
                        "Failed to join main loop thread, system may crash: %d",
                        err);
        }

        state->thread_id = NULL;
      } else {
        // Thread failed to start
        g_main_loop_unref(state->loop);
      }

      state->loop = NULL;
    }

    g_main_context_unref(state->ctx);
    state->ctx = NULL;
  }
}
