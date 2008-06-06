
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
  else if(name ## _size > desired_len * 16) \
  { \
    name ## _size /= 2; \
    name = realloc(name, name ## _size * sizeof(*name)); \
  } \
  name ## _len = desired_len;

#define INIT_DYNARRAY(name, initial_len, initial_size) \
  name ## _len = initial_len; \
  name ## _size = initial_size; \
  name = realloc(NULL, name ## _size)

#define FREE_DYNARRAY(name) \
  free(name);

#define DYNARRAY_GET_TOP(name) \
  (&name[name ## _len - 1])

