#include "native.h"

#include <gio/gnetworking.h>
#include <nice/agent.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

static void cb_candidate_gathering_done(NiceAgent *, guint, gpointer);
static void cb_component_state_changed(NiceAgent *, guint, guint, guint, gpointer);
static void cb_new_candidate_full(NiceAgent *, NiceCandidate *, gpointer);
static void cb_new_selected_pair(NiceAgent *, guint, guint, gchar *, gchar *, gpointer);
static void cb_recv(NiceAgent *, guint, guint, guint, gchar *, gpointer);
static void *main_loop_thread_func(void *);
static void parse_credentials(char *, char **, char **);
static gboolean attach_recv(UnifexState *, guint, guint);
static char *serialize(UnifexPayload *payload, size_t size);
static UnifexPayload *deserialize(UnifexEnv *env, char *data);

UNIFEX_TERM init(UnifexEnv *env) {
  State *state = unifex_alloc_state(env);
  state->gloop = g_main_loop_new(NULL, FALSE);
  state->agent = nice_agent_new(g_main_loop_get_context(state->gloop),
                                NICE_COMPATIBILITY_RFC5245);
  state->env = env;
  NiceAgent *agent = state->agent;
  // TODO pass this by function params after implementing lists and strings for CNodes in Unifex
  g_object_set(agent, "stun-server", "64.233.161.127", NULL);
  g_object_set(agent, "stun-server-port", 19302, NULL);
  g_object_set(agent, "controlling-mode", FALSE, NULL);

  g_signal_connect(G_OBJECT(agent), "candidate-gathering-done",
                   G_CALLBACK(cb_candidate_gathering_done), state);
  g_signal_connect(G_OBJECT(agent), "component-state-changed",
                   G_CALLBACK(cb_component_state_changed), state);
  g_signal_connect(G_OBJECT(agent), "new-candidate-full",
                   G_CALLBACK(cb_new_candidate_full), state);
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

static void cb_new_candidate_full(NiceAgent *agent, NiceCandidate *candidate,
                                  gpointer user_data) {
  State *state = (State *)user_data;
  gchar *candidate_sdp_str =
      nice_agent_generate_local_candidate_sdp(agent, candidate);
  send_new_candidate_full(state->env, *state->env->reply_to, 0, candidate_sdp_str);
  g_free(candidate_sdp_str);
}

static void cb_candidate_gathering_done(NiceAgent *agent, guint stream_id,
                                        gpointer user_data) {
  UNIFEX_UNUSED(agent);
  UNIFEX_UNUSED(stream_id);
  State *state = (State *)user_data;
  send_candidate_gathering_done(state->env, *state->env->reply_to, 0);
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

static void cb_new_selected_pair(NiceAgent *agent, guint stream_id,
                                 guint component_id, gchar *lfoundation,
                                 gchar *rfoundation, gpointer user_data) {
  UNIFEX_UNUSED(agent);
  State *state = (State *)user_data;
  send_new_selected_pair(state->env, *state->env->reply_to, 0, stream_id, component_id, lfoundation, rfoundation);
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
                       unsigned int n_components) {
  guint stream_id = nice_agent_add_stream(state->agent, n_components);
  if (stream_id == 0) {
    return add_stream_result_error_failed_to_add_stream(env);
  }
  if(!attach_recv(state, stream_id, n_components)) {
    return add_stream_result_error_failed_to_attach_recv(env);
  }
  return add_stream_result_ok(env, stream_id);
}

static gboolean attach_recv(UnifexState *state, guint stream_id, guint n_components) {
  for (guint i = 1; i <= n_components; i++) {
    GMainContext *ctx = g_main_loop_get_context(state->gloop);
    if (!nice_agent_attach_recv(state->agent, stream_id, i, ctx, cb_recv, NULL)) {
      return FALSE;
    }
  }
  return TRUE;
}

UNIFEX_TERM remove_stream(UnifexEnv *env, UnifexState *state, unsigned int stream_id) {
  nice_agent_remove_stream(state->agent, stream_id);
  return remove_stream_result_ok(env);
}

UNIFEX_TERM gather_candidates(UnifexEnv *env, State *state, unsigned int stream_id) {
  g_networking_init();
  if(!nice_agent_gather_candidates(state->agent, stream_id)) {
    gather_candidates_result_error_invalid_stream_or_allocation(env);
  }
  return gather_candidates_result_ok(env, state);
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

static void parse_credentials(char *credentials, char **ufrag, char **pwd) {
  *ufrag = strtok(credentials, " ");
  *pwd = strtok(NULL, " ");
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

UNIFEX_TERM send_payload(UnifexEnv *env, State *state, unsigned int stream_id, unsigned int component_id, UnifexPayload *payload) {
  size_t size = payload->size + sizeof(int) + sizeof(UnifexPayloadType) + sizeof(int);
  char *data = serialize(payload, size);
  if(nice_agent_send(state->agent, stream_id, component_id, size, data) < 0) {
    return send_payload_result_error_failed_to_send(env);
  }
  return send_payload_result_ok(env, state);
}

static char *serialize(UnifexPayload *payload, size_t size) {
  char *data = malloc(size);
  memcpy(data, &payload->size, sizeof(int));
  memcpy(data + sizeof(int), payload->data, payload->size);
  memcpy(data + payload->size + sizeof(int), &payload->type, sizeof(UnifexPayloadType));
  memcpy(data + payload->size + sizeof(int) + sizeof(UnifexPayloadType), &payload->owned, sizeof(int));
  return data;
}

static UnifexPayload *deserialize(UnifexEnv *env, char *data) {
  int payload_data_size;
  unsigned char *payload_data;
  UnifexPayloadType type;
  int owned;

  memcpy(&payload_data_size, data, sizeof(int));
  payload_data = malloc(payload_data_size);
  memcpy(payload_data, data + sizeof(int), payload_data_size);
  memcpy(&type, data + sizeof(int) + payload_data_size, sizeof(UnifexPayloadType));
  memcpy(&owned, data + sizeof(int) + payload_data_size + sizeof(UnifexPayloadType), sizeof(int));

  UnifexPayload *payload = unifex_payload_alloc(env, type, payload_data_size);
  payload->data = payload_data;
  payload->size = payload_data_size;
  payload->type = type;
  payload->owned = owned;
  return payload;
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
