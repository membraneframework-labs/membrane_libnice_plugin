#include "native.h"

#include <gio/gnetworking.h>
#include <nice/agent.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

static void cb_candidate_gathering_done(NiceAgent *, guint, gpointer);
static void cb_component_state_changed(NiceAgent *, guint, guint, guint,
                                       gpointer);
static void cb_new_candidate_full(NiceAgent *, NiceCandidate *, gpointer);
static void cb_new_selected_pair(NiceAgent *, guint, guint, gchar *, gchar *,
                                 gpointer);
static void cb_recv(NiceAgent *, guint, guint, guint, gchar *, gpointer);
static void *main_loop_thread_func(void *);
static void parse_credentials(char *, char **, char **);
static gboolean attach_recv(UnifexState *, guint, guint);

static GMainLoop *gloop;
static UnifexEnv *env;

// TODO handle errors

UNIFEX_TERM init(UnifexEnv *envl) {
  State *state = unifex_alloc_state(envl);
  state->gloop = g_main_loop_new(NULL, FALSE);
  state->agent = nice_agent_new(g_main_loop_get_context(state->gloop),
                                NICE_COMPATIBILITY_RFC5245);
  gloop = state->gloop;
  NiceAgent *agent = state->agent;
  g_object_set(agent, "stun-server", "64.233.161.127", NULL);
  g_object_set(agent, "stun-server-port", 19302, NULL);
  g_object_set(agent, "controlling-mode", FALSE, NULL);

  g_signal_connect(G_OBJECT(agent), "candidate-gathering-done",
                   G_CALLBACK(cb_candidate_gathering_done), NULL);
  g_signal_connect(G_OBJECT(agent), "component-state-changed",
                   G_CALLBACK(cb_component_state_changed), NULL);
  g_signal_connect(G_OBJECT(agent), "new-candidate-full",
                   G_CALLBACK(cb_new_candidate_full), NULL);
  g_signal_connect(G_OBJECT(agent), "new-selected-pair",
                   G_CALLBACK(cb_new_selected_pair), NULL);

  pthread_t tid =
      pthread_create(&tid, NULL, main_loop_thread_func, (void *)state->gloop);
  state->gloop_tid = tid;

  env = envl;
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
  UNIFEX_UNUSED(user_data);
  gchar *candidate_sdp_str =
      nice_agent_generate_local_candidate_sdp(agent, candidate);
  send_new_candidate_full(env, *env->reply_to, 0, candidate_sdp_str);
}

static void cb_candidate_gathering_done(NiceAgent *agent, guint stream_id,
                                        gpointer user_data) {
  UNIFEX_UNUSED(agent);
  UNIFEX_UNUSED(stream_id);
  UNIFEX_UNUSED(user_data);
  send_candidate_gathering_done(env, *env->reply_to, 0);
  g_main_loop_quit(gloop);
}

static void cb_component_state_changed(NiceAgent *agent, guint stream_id,
                                       guint component_id, guint state,
                                       gpointer user_data) {
  UNIFEX_UNUSED(agent);
  UNIFEX_UNUSED(stream_id);
  UNIFEX_UNUSED(component_id);
  UNIFEX_UNUSED(state);
  UNIFEX_UNUSED(user_data);
}

static void cb_new_selected_pair(NiceAgent *agent, guint stream_id,
                                 guint component_id, gchar *lfoundation,
                                 gchar *rfoundation, gpointer user_data) {
  UNIFEX_UNUSED(agent);
  UNIFEX_UNUSED(stream_id);
  UNIFEX_UNUSED(component_id);
  UNIFEX_UNUSED(lfoundation);
  UNIFEX_UNUSED(rfoundation);
  UNIFEX_UNUSED(user_data);
}

static void cb_recv(NiceAgent *agent, guint stream_id, guint component_id,
                    guint len, gchar *buf, gpointer user_data) {
  UNIFEX_UNUSED(agent);
  UNIFEX_UNUSED(stream_id);
  UNIFEX_UNUSED(component_id);
  UNIFEX_UNUSED(len);
  UNIFEX_UNUSED(buf);
  UNIFEX_UNUSED(user_data);
  if (len == 1 && buf[0] == '\0')
    g_main_loop_quit(gloop);
  printf("%.*s", len, buf);
  fflush(stdout);
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
    if (!nice_agent_attach_recv(state->agent, stream_id, i,
                                g_main_loop_get_context(state->gloop), cb_recv,
                                NULL)) {
      return FALSE;
    }
  }
  return TRUE;
}

UNIFEX_TERM remove_stream(UnifexEnv *env, UnifexState *state, unsigned int stream_id) {
  nice_agent_remove_stream(state->agent, stream_id);
  return remove_stream_result_ok(env);
}

UNIFEX_TERM gather_candidates(UnifexEnv *_env, State *state, unsigned int stream_id) {
  UNIFEX_UNUSED(_env);
  g_networking_init();
  nice_agent_gather_candidates(state->agent, stream_id);
  return gather_candidates_result_ok(env, state);
}

UNIFEX_TERM get_local_credentials(UnifexEnv *env, State *state, unsigned int stream_id) {
  gchar *ufrag = NULL;
  gchar *pwd = NULL;
  if (!nice_agent_get_local_credentials(state->agent, stream_id, &ufrag,
                                        &pwd)) {
    return get_local_credentials_result_error_failed_to_get_credentials(env);
  }
  ufrag = strcat(ufrag, " ");
  gchar *credentials = strcat(ufrag, pwd);
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

UNIFEX_TERM set_remote_candidates(UnifexEnv *env, State *state,
                                  char *candidates, unsigned int stream_id, unsigned int component_id) {
  NiceCandidate *candidate = nice_agent_parse_remote_candidate_sdp(
      state->agent, stream_id, candidates);
  if (candidate == NULL) {
    return set_remote_candidates_result_error_failed_to_parse_sdp_string(env);
  }
  GSList *cands = NULL;
  cands = g_slist_append(cands, candidate);
  if (nice_agent_set_remote_candidates(state->agent, stream_id, component_id,
                                       cands) < 0) {
    return set_remote_candidates_result_error_failed_to_set(env);
  }
  return set_remote_candidates_result_ok(env, state);
}

void handle_destroy_state(UnifexEnv *env, State *state) {
  UNIFEX_UNUSED(env);
  if (state->gloop) {
    g_main_loop_unref(state->gloop);
    state->gloop = NULL;
  }
  if (state->agent) {
    g_object_unref(state->agent);
    state->agent = NULL;
  }
  // TODO flush main loop thread here
}
