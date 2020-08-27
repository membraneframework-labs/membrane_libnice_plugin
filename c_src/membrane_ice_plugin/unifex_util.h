#pragma once

#include <unifex/payload.h>
#include <unifex/unifex.h>

char *serialize(UnifexPayload *payload, size_t size);
UnifexPayload *deserialize(UnifexEnv *env, char *data);
