#pragma once

#include <nice/agent.h>
#include <unifex/unifex.h>

typedef struct State State;

struct State {
  GMainLoop *gloop;
  NiceAgent *agent;
  unsigned int stream_id;
  pthread_t gloop_tid;
};

#include "_generated/native.h"
