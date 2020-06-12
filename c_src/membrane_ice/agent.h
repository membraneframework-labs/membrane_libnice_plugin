#pragma once

#define MEMBRANE_LOG_TAG "Membrane.ICE.Agent.Native"

#include <membrane/log.h>
#include <nice/agent.h>
#include <erl_nif.h>

typedef struct _AgentState UnifexNifState;
typedef UnifexNifState State;

struct _AgentState {
  GMainContext *ctx;
  GMainLoop *loop;
  ErlNifTid thread_id;
  NiceAgent *agent;
};

#include "_generated/agent.h"
