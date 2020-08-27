#include "arg_parser.h"

static int parse_stun_servers(NiceAgent *agent, char **stun_servers, unsigned int length);
static int parse_turn_servers(NiceAgent *agent, char **turn_servers, unsigned int length);
static int parse_controlling_mode(NiceAgent *agent, int controlling_mode);

int parse_args(NiceAgent *agent, char **stun_servers, unsigned int stun_servers_length,
                char **turn_servers, unsigned int turn_servers_length, int controlling_mode) {
  int res;
  res = parse_stun_servers(agent, stun_servers, stun_servers_length);
  if(res) {
    return res;
  }
  res = parse_turn_servers(agent, turn_servers, turn_servers_length);
  if(res) {
    return res;
  }
  res = parse_controlling_mode(agent, controlling_mode);
  if(res) {
    return res;
  }
  return 0;
}

static int parse_stun_servers(NiceAgent *agent, char **stun_servers, unsigned int length) {
  for(unsigned int i = 0; i < length; i++) {
    char *addr = strtok(stun_servers[i], ":");
    char *port = strtok(NULL, ":");
    if(!addr || !port) {
      return BAD_STUN_FORMAT;
    }
    g_object_set(agent, "stun-server", addr, NULL);
    g_object_set(agent, "stun-server-port", atoi(port), NULL);
  }
  return 0;
}

static int parse_turn_servers(NiceAgent *agent, char **turn_servers, unsigned int length) {
  for(unsigned int i = 0; i < length; i++) {
    char *addr = strtok(turn_servers[i], ":");
    char *port = strtok(NULL, SERVERS_DELIM);
    char *proto = strtok(NULL, SERVERS_DELIM);
    char *username = strtok(NULL, SERVERS_DELIM);
    char *passwd = strtok(NULL, SERVERS_DELIM);
    if(!addr || !port || !proto || !username || !passwd) {
      return BAD_TURN_FORMAT;
    }

    NiceRelayType type;
    if (strcmp(proto, "udp") == 0) {
      type = NICE_RELAY_TYPE_TURN_UDP;
    } else if(strcmp(proto, "tcp") == 0) {
      type = NICE_RELAY_TYPE_TURN_TCP;
    } else if(strcmp(proto, "tls") == 0) {
      type = NICE_RELAY_TYPE_TURN_TLS;
    } else {
      return BAD_TURN_PROTO;
    }
    // TODO don't hardcode stream_id and component_id
    if(!nice_agent_set_relay_info(agent, 1, 1, addr, atoi(port), username, passwd, type)) {
      return BAD_TURN_ADDR;
    }
  }
  return 0;
}

static int parse_controlling_mode(NiceAgent *agent, int controlling_mode) {
  if(controlling_mode == 0) {
    g_object_set(agent, "controlling_mode", FALSE, NULL);
  } else if(controlling_mode == 1) {
    g_object_set(agent, "controlling_mode", TRUE, NULL);
  } else {
    return BAD_CTLM_FORMAT;
  }
  return 0;
}
