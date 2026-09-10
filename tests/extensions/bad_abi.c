#include "zphp_extension.h"
static const zphp_extension ext = { .abi = 99, .name = "bad_abi", .version = "1" };
ZPHP_EXTENSION(bad_abi, &ext)
