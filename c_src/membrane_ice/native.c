#include <gio/gnetworking.h>
#include <nice/agent.h>
#include <stdio.h>

static void cb_candidate_gathering_done(NiceAgent *, guint, gpointer);
static void cb_component_state_changed(NiceAgent *, guint, guint, guint,
                                       gpointer);
static void cb_new_selected_pair(NiceAgent *, guint, guint, gchar *, gchar *,
                                 gpointer);
static void cb_recv(NiceAgent *, guint, guint, guint, gchar *, gpointer);

static GMainLoop *gloop;

int main(int argc, char **argv) {
  g_networking_init();
  gloop = g_main_loop_new(NULL, FALSE);
  NiceAgent *agent = nice_agent_new(g_main_loop_get_context(gloop),
                                    NICE_COMPATIBILITY_RFC5245);

  g_object_set(agent, "stun-server", "64.233.161.127", NULL);
  g_object_set(agent, "stun-server-port", 19302, NULL);
  g_object_set(agent, "controlling-mode", FALSE, NULL);

  g_signal_connect(G_OBJECT(agent), "candidate-gathering-done",
                   G_CALLBACK(cb_candidate_gathering_done), NULL);
  g_signal_connect(G_OBJECT(agent), "component-state-changed",
                   G_CALLBACK(cb_component_state_changed), NULL);
  g_signal_connect(G_OBJECT(agent), "new-selected-pair",
                   G_CALLBACK(cb_new_selected_pair), NULL);

  guint stream_id = nice_agent_add_stream(agent, 1);
  if (stream_id == 0) {
    printf("error");
  }
  nice_agent_attach_recv(agent, stream_id, 1, g_main_loop_get_context(gloop),
                         cb_recv, NULL);
  nice_agent_gather_candidates(agent, stream_id);

  g_main_loop_run(gloop);
  g_main_loop_unref(gloop);
  g_object_unref(agent);
  return 0;
}

static void cb_candidate_gathering_done(NiceAgent *agent, guint stream_id,
                                        gpointer user_data) {
  printf("Gathering done\n");
  fflush(stdout);
  gchar ipstr[INET6_ADDRSTRLEN];
  GSList *cands = nice_agent_get_local_candidates(agent, stream_id, 1);
  for (GSList *cand = cands; cand != NULL; cand = cand->next) {
    NiceCandidate *c = (NiceCandidate *)cand->data;
    nice_address_to_string(&c->addr, ipstr);
    printf("%s:%u\n", ipstr, nice_address_get_port(&c->addr));
  }
  g_main_loop_quit(gloop);
}

static void cb_component_state_changed(NiceAgent *agent, guint stream_id,
                                       guint component_id, guint state,
                                       gpointer user_data) {
  printf("cb component state changed\n");
}

static void cb_new_selected_pair(NiceAgent *agent, guint stream_id,
                                 guint component_id, gchar *lfoundation,
                                 gchar *rfoundation, gpointer user_data) {}

static void cb_recv(NiceAgent *agent, guint sream_id, guint component_id,
                    guint len, gchar *buf, gpointer user_data) {
  printf("cb recv");
  if (len == 1 && buf[0] == '\0')
    g_main_loop_quit(gloop);
  printf("%.*s", len, buf);
  fflush(stdout);
}
