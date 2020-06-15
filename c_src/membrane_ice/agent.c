#include "agent.h"

#define NAMEOF(x) #x

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

UNIFEX_TERM create(UnifexEnv *env, char *compatibility, char **options,
                   unsigned int options_length) {
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

  NiceCompatibility nice_compatibility;
  if (strcmp(compatibility, "rfc5245") == 0) {
    nice_compatibility = NICE_COMPATIBILITY_RFC5245;
  } else if (strcmp(compatibility, "google") == 0) {
    nice_compatibility = NICE_COMPATIBILITY_GOOGLE;
  } else if (strcmp(compatibility, "msn") == 0) {
    nice_compatibility = NICE_COMPATIBILITY_MSN;
  } else if (strcmp(compatibility, "wlm2009") == 0) {
    nice_compatibility = NICE_COMPATIBILITY_WLM2009;
  } else if (strcmp(compatibility, "oc2007") == 0) {
    nice_compatibility = NICE_COMPATIBILITY_OC2007;
  } else if (strcmp(compatibility, "oc2007r2") == 0) {
    nice_compatibility = NICE_COMPATIBILITY_OC2007R2;
  } else {
    unifex_release_state(env, state);
    return unifex_raise_args_error(env, NAMEOF(compatibility),
                                   "unknown compatibility mode");
  }

  int nice_flags = 0;
  for (size_t i = 0; i < options_length; i++) {
    const char *option = options[i];
    if (strcmp(option, "regular_nomination") == 0) {
      nice_flags |= NICE_AGENT_OPTION_REGULAR_NOMINATION;
    } else if (strcmp(option, "reliable") == 0) {
      nice_flags |= NICE_AGENT_OPTION_RELIABLE;
    } else if (strcmp(option, "lite_mode") == 0) {
      nice_flags |= NICE_AGENT_OPTION_LITE_MODE;
    } else if (strcmp(option, "ice_trickle") == 0) {
      nice_flags |= NICE_AGENT_OPTION_ICE_TRICKLE;
    } else if (strcmp(option, "support_renomination") == 0) {
      nice_flags |= NICE_AGENT_OPTION_SUPPORT_RENOMINATION;
    } else {
      unifex_release_state(env, state);
      return unifex_raise_args_error(env, NAMEOF(options), "unknown option");
    }
  }

  state->agent = nice_agent_new_full(state->ctx, nice_compatibility,
                                     (NiceAgentOption)nice_flags);
  if (!state->agent) {
    unifex_release_state(env, state);
    return unifex_raise(env, "not enough memory");
  }

  return create_result(env, state);
}

UNIFEX_TERM destroy(UnifexEnv *env, UnifexNifState *state) {
  unifex_release_state(env, state);
  return destroy_result(env);
}

void handle_destroy_state(UnifexEnv *env, UnifexNifState *state) {
  int err;

  if (state->agent) {
    g_object_unref(state->agent);
    state->agent = NULL;
  }

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

UNIFEX_TERM add_stream(UnifexEnv *env, UnifexNifState *state,
                       unsigned int n_components) {
  guint stream_id = nice_agent_add_stream(state->agent, n_components);
  if (stream_id > 0) {
    return add_stream_result_ok(env, stream_id);
  } else {
    return add_stream_result_error_failed_to_add(env);
  }
}

UNIFEX_TERM remove_stream(UnifexEnv *env, UnifexNifState *state,
                          unsigned int stream_id) {
  nice_agent_remove_stream(state->agent, stream_id);
  return remove_stream_result_ok(env);
}

UNIFEX_TERM set_port_range(UnifexEnv *env, UnifexNifState *state,
                           unsigned int stream_id, unsigned int component_id,
                           unsigned int min_port, unsigned int max_port) {
  nice_agent_set_port_range(state->agent, stream_id, component_id, min_port,
                            max_port);
  return set_port_range_result_ok(env);
}

// TODO Subscribe to signals
UNIFEX_TERM gather_candidates(UnifexEnv *env, UnifexNifState *state,
                              unsigned int stream_id) {
  gboolean res = nice_agent_gather_candidates(state->agent, stream_id);
  if (res) {
    return gather_candidates_result_ok(env);
  } else {
    return gather_candidates_result_error_invalid_stream_or_interface(env);
  }
}
