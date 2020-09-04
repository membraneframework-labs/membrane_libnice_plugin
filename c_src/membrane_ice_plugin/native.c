#include <gio/gnetworking.h>
#include <nice/agent.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

#include "native.h"
#include "parser.h"
#include "unifex_util.h"

static void cb_candidate_gathering_done(NiceAgent *agent, guint stream_id, gpointer user_data);
static void cb_component_state_changed(NiceAgent *agent, guint stream_id, guint component_id,
                                       guint component_state, gpointer user_data);
static void cb_new_candidate_full(NiceAgent *agent, NiceCandidate *candidate, gpointer user_data);
static void cb_new_remote_candidate_full(NiceAgent *agent, NiceCandidate *candidate,
                                         gpointer user_data);
static void cb_new_selected_pair(NiceAgent *agent, guint stream_id, guint component_id,
                                 gchar * lfoundation, gchar *rfoundation, gpointer user_data);
static void cb_recv(NiceAgent *agent, guint stream_id, guint component_id, guint len, gchar *buf,
                    gpointer user_data);
static void *main_loop_thread_func(void *user_data);
static gboolean attach_recv(UnifexState *state, guint stream_id, guint n_components);

UNIFEX_TERM init(UnifexEnv *env, char **stun_servers, unsigned int stun_servers_length,
                 char **turn_servers, unsigned int turn_servers_length, int controlling_mode,
                 unsigned int min_port, unsigned int max_port) {
  State *state = unifex_alloc_state(env);
  state->gloop = g_main_loop_new(NULL, FALSE);
  state->agent = nice_agent_new_full(g_main_loop_get_context(state->gloop),
                                NICE_COMPATIBILITY_RFC5245,
                                NICE_AGENT_OPTION_REGULAR_NOMINATION);
  /*
  FIXME
  This option seems not working.
  Refer to: https://gitlab.freedesktop.org/libnice/libnice/-/issues/120
  */
  g_object_set (G_OBJECT (state->agent), "ice-trickle", TRUE, NULL);
  state->env = env;
  state->min_port = min_port;
  state->max_port = max_port;
  NiceAgent *agent = state->agent;

  int parse_res = parse_args(agent, stun_servers, stun_servers_length, turn_servers,
                             turn_servers_length, controlling_mode);
  switch(parse_res) {
    case BAD_STUN_FORMAT:
      return unifex_raise(env, "bad stun server format");
    case BAD_TURN_FORMAT:
      return unifex_raise(env, "bad turn server format");
    case BAD_TURN_PROTO:
      return unifex_raise(env, "bad turn server protocol");
    case BAD_TURN_ADDR:
      return unifex_raise(env, "bad turn server address");
    case BAD_CTLM_FORMAT:
      return unifex_raise(env, "unknown controlling mode");
    default:
      break;
  }

  g_signal_connect(G_OBJECT(agent), "candidate-gathering-done",
                   G_CALLBACK(cb_candidate_gathering_done), state);
  g_signal_connect(G_OBJECT(agent), "component-state-changed",
                   G_CALLBACK(cb_component_state_changed), state);
  g_signal_connect(G_OBJECT(agent), "new-candidate-full",
                   G_CALLBACK(cb_new_candidate_full), state);
  g_signal_connect(G_OBJECT(agent), "new-remote-candidate-full",
                   G_CALLBACK(cb_new_remote_candidate_full), state);
  g_signal_connect(G_OBJECT(agent), "new-selected-pair",
                   G_CALLBACK(cb_new_selected_pair), state);

  if(pthread_create(&state->gloop_tid, NULL, main_loop_thread_func, (void *)state->gloop) != 0) {
    return unifex_raise(env, "failed to create main loop thread");
  }

  return init_result_ok(env, state);
}

static void *main_loop_thread_func(void *user_data) {
  GMainLoop *loop = (GMainLoop *)user_data;
  g_main_loop_run(loop);
  g_main_loop_unref(loop);
  return NULL;
}

static void cb_candidate_gathering_done(NiceAgent *agent, guint stream_id,
                                        gpointer user_data) {
  UNIFEX_UNUSED(agent);
  UNIFEX_UNUSED(stream_id);
  State *state = (State *)user_data;
  send_candidate_gathering_done(state->env, *state->env->reply_to, 0, stream_id);
}

static void cb_component_state_changed(NiceAgent *agent, guint stream_id,
                                       guint component_id, guint component_state,
                                       gpointer user_data) {
  UNIFEX_UNUSED(agent);
  State *state = (State *)user_data;
  if(component_state == NICE_COMPONENT_STATE_FAILED) {
    send_component_state_failed(state->env, *state->env->reply_to, 0, stream_id, component_id);
  } else if(component_state == NICE_COMPONENT_STATE_READY) {
    send_component_state_ready(state->env, *state->env->reply_to, 0, stream_id, component_id);
  }
}

static void cb_new_candidate_full(NiceAgent *agent, NiceCandidate *candidate,
                                  gpointer user_data) {
  State *state = (State *)user_data;
  gchar *candidate_sdp_str =
      nice_agent_generate_local_candidate_sdp(agent, candidate);
  send_new_candidate_full(state->env, *state->env->reply_to, 0, candidate_sdp_str);
  g_free(candidate_sdp_str);
}


static void cb_new_remote_candidate_full(NiceAgent *agent, NiceCandidate *candidate,
                                         gpointer user_data) {
  State *state = (State *)user_data;
  /*
  FIXME
  Potentially we may be forced to parse it on our own instead of using generate_sdp().
  Similarly to https://github.com/meetecho/janus-gateway/blob/be78b7935d434ec935e5d15e63f885e7ea84607b/ice.c#L1879-L1904
  */
  gchar *candidate_sdp_str =
      nice_agent_generate_local_candidate_sdp(agent, candidate);
  send_new_remote_candidate_full(state->env, *state->env->reply_to, 0, candidate_sdp_str);
  g_free(candidate_sdp_str);
}

static void cb_new_selected_pair(NiceAgent *agent, guint stream_id,
                                 guint component_id, gchar *lfoundation,
                                 gchar *rfoundation, gpointer user_data) {
  UNIFEX_UNUSED(agent);
  State *state = (State *)user_data;
  send_new_selected_pair(state->env, *state->env->reply_to, 0, stream_id, component_id,
                         lfoundation, rfoundation);
}

static void cb_recv(NiceAgent *agent, guint stream_id, guint component_id,
                    guint len, gchar *buf, gpointer user_data) {
  UNIFEX_UNUSED(agent);
  UNIFEX_UNUSED(len);
  State *state = (State *)user_data;
  UnifexPayload *payload = deserialize(state->env, buf);
  send_ice_payload(state->env, *state->env->reply_to, 0, stream_id, component_id, payload);
}

UNIFEX_TERM add_stream(UnifexEnv *env, UnifexState *state,
                       unsigned int n_components, char *name) {
  guint stream_id = nice_agent_add_stream(state->agent, n_components);
  if (stream_id == 0) {
    return add_stream_result_error_failed_to_add_stream(env);
  }

  if(!attach_recv(state, stream_id, n_components)) {
    return add_stream_result_error_failed_to_attach_recv(env);
  }

  // set name if one was specified
  if (strcmp(name, "") == 0) {
    return add_stream_result_ok(env, stream_id);
  } else {
    if (!nice_agent_set_stream_name(state->agent, stream_id, name)) {
      return add_stream_result_error_invalid_stream_or_duplicate_name(env);
    }
  }

  // set port range for each component in stream
  for (unsigned int i = 1; i <= n_components; i++) {
    nice_agent_set_port_range(state->agent, stream_id, i, state->min_port, state->max_port);
  }

  return add_stream_result_ok(env, stream_id);
}

static gboolean attach_recv(UnifexState *state, guint stream_id, guint n_components) {
  for (guint i = 1; i <= n_components; i++) {
    GMainContext *ctx = g_main_loop_get_context(state->gloop);
    if (!nice_agent_attach_recv(state->agent, stream_id, i, ctx, cb_recv, state)) {
      return FALSE;
    }
  }
  return TRUE;
}

UNIFEX_TERM remove_stream(UnifexEnv *env, UnifexState *state, unsigned int stream_id) {
  nice_agent_remove_stream(state->agent, stream_id);
  return remove_stream_result_ok(env);
}

UNIFEX_TERM generate_local_sdp(UnifexEnv *env, UnifexState *state) {
  gchar *local_sdp = nice_agent_generate_local_sdp(state->agent);
  return generate_local_sdp_result_ok(env, local_sdp);
}

UNIFEX_TERM parse_remote_sdp(UnifexEnv *env, UnifexState *state, char *remote_sdp) {
  int cand_added_num = nice_agent_parse_remote_sdp(state->agent, remote_sdp);
	if (cand_added_num < 0) {
    return parse_remote_sdp_result_error_failed_to_parse_sdp(env);
  }
  return parse_remote_sdp_result_ok(env, cand_added_num);
}

UNIFEX_TERM gather_candidates(UnifexEnv *env, State *state, unsigned int stream_id) {
  g_networking_init();
  if(!nice_agent_gather_candidates(state->agent, stream_id)) {
    return gather_candidates_result_error_invalid_stream_or_allocation(env);
  }
  return gather_candidates_result_ok(env, state);
}

UNIFEX_TERM peer_candidate_gathering_done(UnifexEnv *env, State *state, unsigned int stream_id) {
  if(!nice_agent_peer_candidate_gathering_done(state->agent, stream_id)) {
    return peer_candidate_gathering_done_result_error_stream_not_found(env);
  }
  return peer_candidate_gathering_done_result_ok(env, state);
}

UNIFEX_TERM get_local_credentials(UnifexEnv *env, State *state, unsigned int stream_id) {
  gchar *ufrag = NULL;
  gchar *pwd = NULL;
  if (!nice_agent_get_local_credentials(state->agent, stream_id, &ufrag, &pwd)) {
    return get_local_credentials_result_error_failed_to_get_credentials(env);
  }
  const size_t lenufrag = strlen(ufrag);
  const size_t lenpwd = strlen(pwd);
  char *credentials = malloc(lenufrag + lenpwd + 2); // null terminator and space
  memcpy(credentials, ufrag, lenufrag);
  memcpy(credentials + lenufrag, " ", 1);
  memcpy(credentials + lenufrag + 1, pwd, lenpwd + 1);
  g_free(ufrag);
  g_free(pwd);
  return get_local_credentials_result_ok(env, credentials);
}

UNIFEX_TERM set_remote_credentials(UnifexEnv *env, State *state,
                                   char *credentials, unsigned int stream_id) {
  char *ufrag = NULL;
  char *pwd = NULL;
  parse_credentials(credentials, &ufrag, &pwd);
  if (!nice_agent_set_remote_credentials(state->agent, stream_id, ufrag, pwd)) {
    return set_remote_credentials_result_error_failed_to_set_credentials(env);
  }
  return set_remote_credentials_result_ok(env, state);
}

UNIFEX_TERM set_remote_candidate(UnifexEnv *env, State *state,
                                  char *candidate, unsigned int stream_id, unsigned int component_id) {
  NiceCandidate *cand = nice_agent_parse_remote_candidate_sdp(state->agent, stream_id, candidate);
  if (cand == NULL) {
    return set_remote_candidate_result_error_failed_to_parse_sdp_string(env);
  }
  GSList *cands = NULL;
  cands = g_slist_append(cands, cand);
  if (nice_agent_set_remote_candidates(state->agent, stream_id, component_id, cands) < 0) {
    return set_remote_candidate_result_error_failed_to_set(env);
  }
  return set_remote_candidate_result_ok(env, state);
}

UNIFEX_TERM send_payload(UnifexEnv *env, State *state, unsigned int stream_id,
                         unsigned int component_id, UnifexPayload *payload) {
  size_t size = payload->size + sizeof(int) + sizeof(UnifexPayloadType) + sizeof(int);
  char *data = serialize(payload, size);
  if(nice_agent_send(state->agent, stream_id, component_id, size, data) < 0) {
    return send_payload_result_error_failed_to_send(env);
  }
  return send_payload_result_ok(env, state);
}

void handle_destroy_state(UnifexEnv *env, State *state) {
  UNIFEX_UNUSED(env);
  g_main_loop_quit(state->gloop);
  pthread_kill(state->gloop_tid, SIGKILL);
  if (state->gloop) {
    g_main_loop_unref(state->gloop);
    state->gloop = NULL;
  }
  if (state->agent) {
    g_object_unref(state->agent);
    state->agent = NULL;
  }
}
