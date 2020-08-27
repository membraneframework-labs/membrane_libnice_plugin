#pragma once

#include <nice/agent.h>

#define SERVERS_DELIM ":"

#define BAD_STUN_FORMAT -1
#define BAD_TURN_FORMAT -2
#define BAD_TURN_PROTO -3
#define BAD_TURN_ADDR -4
#define BAD_CTLM_FORMAT -5

int parse_args(NiceAgent *agent, char **stun_servers, unsigned int stun_servers_length,
                char **turn_servers, unsigned int turn_servers_length, int controlling_mode);
