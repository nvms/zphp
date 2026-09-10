#include "zphp_extension.h"
static void f(zphp_ctx *ctx) { zphp_return_null(ctx); }
static int init(zphp_module *m) { return zphp_register_function(m, "strlen", f); }
static const zphp_extension ext = { .abi = ZPHP_EXTENSION_ABI, .name = "clash", .version = "1", .module_init = init };
ZPHP_EXTENSION(clash, &ext)
