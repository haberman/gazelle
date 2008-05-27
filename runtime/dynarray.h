
#define ROUND_UP_TO_POWER_OF_TWO(num) \
  unsigned int v = num; \
  v--; \
  v |= v >> 1; \
  v |= v >> 2; \
  v |= v >> 4; \
  v |= v >> 8; \
  v |= v >> 16; \
  v++; \
  num = v;

#define DEFINE_DYNARRAY(name, type) \
  type *name; \
  int name ## _len; \
  int name ## _size;

#define RESIZE_DYNARRAY(name, desired_len) \
  if(name ## _size < desired_len) \
  { \
    name ## _size *= 2; \
    name = realloc(name, name ## _size * sizeof(*name)); \
  } \
  else if(name ## _size > desired_len * 4) \
  { \
    name ## _size /= 2; \
    name = realloc(name, name ## _size * sizeof(*name)); \
  } \
  name ## _len = desired_len;

#define INIT_DYNARRAY(name, initial_len, initial_size) \
  name ## _len = initial_len; \
  name ## _size = initial_len; \
  ROUND_UP_TO_POWER_OF_TWO(name ## _size) \
  name = realloc(NULL, name ## _size)

#define FREE_DYNARRAY(name) \
  free(name);

#define DYNARRAY_GET_TOP(name) \
  (&name[name ## _len - 1])

