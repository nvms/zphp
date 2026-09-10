#include "zphp_extension.h"
static int init(zphp_module *m) { (void)m; return 7; }
static const zphp_extension ext = { .abi = ZPHP_EXTENSION_ABI, .name = "failing_init", .version = "1", .module_init = init };
ZPHP_EXTENSION(failing_init, &ext)
