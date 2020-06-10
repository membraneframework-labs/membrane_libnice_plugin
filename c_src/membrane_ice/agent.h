#pragma once

#define MEMBRANE_LOG_TAG "Membrane.ICE.Agent.Native"

#include <membrane/log.h>
#include <membrane/membrane.h>
#include <nice/agent.h>

typedef struct _AgentState UnifexNifState;
typedef UnifexNifState State;

struct _AgentState {
  GMainContext *ctx;
  NiceAgent *agent;
};

#include "_generated/agent.h"
