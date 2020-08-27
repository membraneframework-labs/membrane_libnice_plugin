#include "unifex_util.h"

char *serialize(UnifexPayload *payload, size_t size) {
  char *data = malloc(size);
  memcpy(data, &payload->size, sizeof(int));
  memcpy(data + sizeof(int), payload->data, payload->size);
  memcpy(data + payload->size + sizeof(int), &payload->type, sizeof(UnifexPayloadType));
  memcpy(data + payload->size + sizeof(int) + sizeof(UnifexPayloadType), &payload->owned,
         sizeof(int));
  return data;
}

UnifexPayload *deserialize(UnifexEnv *env, char *data) {
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
