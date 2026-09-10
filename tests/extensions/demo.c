/*
 * The extension the test-suite loads. It touches every part of the API:
 * functions, a class with methods and constants, an interface, an exception
 * class, global constants, an ini default, a resource type with a destructor,
 * callbacks into PHP, and request-local plus worker-local state.
 */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "zphp_extension.h"

static uint32_t buffer_type;
static long freed_buffers;

typedef struct demo_buffer {
    char *data;
    size_t len;
    size_t cap;
} demo_buffer;

typedef struct request_state {
    long counter;
} request_state;

typedef struct worker_state {
    long hits;
} worker_state;

static void buffer_dtor(void *ptr)
{
    demo_buffer *buf = ptr;
    free(buf->data);
    free(buf);
    freed_buffers++;
}

/* demo_add(int $a, int $b): int */
static void demo_add(zphp_ctx *ctx)
{
    if (zphp_arg_count(ctx) < 2) {
        zphp_throw(ctx, "ArgumentCountError", "demo_add() expects exactly 2 arguments");
        return;
    }
    zphp_return_int(ctx, zphp_get_int(zphp_arg(ctx, 0)) + zphp_get_int(zphp_arg(ctx, 1)));
}

/* demo_greet(string $name): string */
static void demo_greet(zphp_ctx *ctx)
{
    size_t name_len = 0, greeting_len = 0;
    const char *name = zphp_arg_count(ctx) > 0 ? zphp_get_string(ctx, zphp_arg(ctx, 0), &name_len) : NULL;
    const char *greeting = zphp_ini_get(ctx, "demo.greeting", &greeting_len);
    char out[256];
    int n = snprintf(out, sizeof out, "%.*s, %.*s!", (int)greeting_len, greeting ? greeting : "", (int)name_len, name ? name : "");
    zphp_return_string(ctx, out, (size_t)n);
}

/* demo_stats(array $values): array{count, sum, keys, first} */
static void demo_stats(zphp_ctx *ctx)
{
    const zphp_value *input = zphp_arg(ctx, 0);
    if (zphp_type_of(input) != ZPHP_ARRAY) {
        zphp_throw(ctx, "TypeError", "demo_stats(): Argument #1 ($values) must be of type array");
        return;
    }
    zphp_value *keys = zphp_array(ctx);
    int64_t sum = 0;
    size_t count = zphp_array_count(input);
    for (size_t i = 0; i < count; i++) {
        const zphp_value *key, *value;
        if (zphp_array_at(ctx, input, i, &key, &value) != 0) break;
        sum += zphp_get_int(value);
        zphp_array_push(ctx, keys, key);
    }
    zphp_value *result = zphp_array(ctx);
    zphp_array_set_string(ctx, result, "count", 5, zphp_int(ctx, (int64_t)count));
    zphp_array_set_string(ctx, result, "sum", 3, zphp_int(ctx, sum));
    zphp_array_set_string(ctx, result, "keys", 4, keys);
    const zphp_value *first = zphp_array_get_int(ctx, input, 0);
    zphp_array_set_string(ctx, result, "first", 5, first ? first : zphp_null(ctx));
    const zphp_value *named = zphp_array_get_string(ctx, input, "name", 4);
    zphp_array_set_string(ctx, result, "name", 4, named ? named : zphp_string(ctx, "none", 4));
    zphp_return_value(ctx, result);
}

/* demo_types(mixed ...$values): string[] */
static void demo_types(zphp_ctx *ctx)
{
    static const char *const names[] = { "null", "bool", "int", "float", "string", "array", "object", "other" };
    zphp_value *out = zphp_array(ctx);
    for (size_t i = 0; i < zphp_arg_count(ctx); i++) {
        const char *name = names[zphp_type_of(zphp_arg(ctx, i))];
        zphp_array_push(ctx, out, zphp_string(ctx, name, strlen(name)));
    }
    zphp_return_value(ctx, out);
}

/* demo_apply(string $function, mixed $value): mixed, calls back into PHP */
static void demo_apply(zphp_ctx *ctx)
{
    size_t len = 0;
    const char *name = zphp_get_string(ctx, zphp_arg(ctx, 0), &len);
    char fn[128];
    snprintf(fn, sizeof fn, "%.*s", (int)len, name);
    const zphp_value *args[1] = { zphp_arg(ctx, 1) };
    zphp_value *result = zphp_call(ctx, fn, args, 1);
    if (result == NULL) return;
    zphp_return_value(ctx, result);
}

/* demo_throw(string $message): never */
static void demo_throw(zphp_ctx *ctx)
{
    size_t len = 0;
    const char *msg = zphp_get_string(ctx, zphp_arg(ctx, 0), &len);
    char out[256];
    snprintf(out, sizeof out, "%.*s", (int)len, msg);
    zphp_throw(ctx, "DemoException", out);
}

/* demo_counter(): int, increments the request-local counter */
static void demo_counter(zphp_ctx *ctx)
{
    request_state *state = zphp_request_data(ctx);
    zphp_return_int(ctx, ++state->counter);
}

/* demo_hits(): int, increments the worker-local counter */
static void demo_hits(zphp_ctx *ctx)
{
    worker_state *state = zphp_worker_data(ctx);
    zphp_return_int(ctx, ++state->hits);
}

/* demo_echo(string $text): void */
static void demo_echo(zphp_ctx *ctx)
{
    size_t len = 0;
    const char *text = zphp_get_string(ctx, zphp_arg(ctx, 0), &len);
    zphp_echo(ctx, text, len);
}

/* demo_open(int $capacity): DemoBuffer */
static void demo_open(zphp_ctx *ctx)
{
    int64_t cap = zphp_arg_count(ctx) > 0 ? zphp_get_int(zphp_arg(ctx, 0)) : 64;
    if (cap <= 0) {
        zphp_throw(ctx, "ValueError", "demo_open(): Argument #1 ($capacity) must be greater than 0");
        return;
    }
    demo_buffer *buf = calloc(1, sizeof *buf);
    buf->cap = (size_t)cap;
    buf->data = malloc(buf->cap);
    zphp_return_value(ctx, zphp_resource(ctx, buffer_type, buf));
}

/* demo_write(DemoBuffer $buffer, string $text): int */
static void demo_write(zphp_ctx *ctx)
{
    demo_buffer *buf = zphp_resource_ptr(ctx, zphp_arg(ctx, 0), buffer_type);
    if (buf == NULL) {
        zphp_throw(ctx, "TypeError", "demo_write(): Argument #1 ($buffer) must be an open DemoBuffer");
        return;
    }
    size_t len = 0;
    const char *text = zphp_get_string(ctx, zphp_arg(ctx, 1), &len);
    size_t room = buf->cap - buf->len;
    size_t n = len < room ? len : room;
    memcpy(buf->data + buf->len, text, n);
    buf->len += n;
    zphp_return_int(ctx, (int64_t)n);
}

/* demo_read(DemoBuffer $buffer): string */
static void demo_read(zphp_ctx *ctx)
{
    demo_buffer *buf = zphp_resource_ptr(ctx, zphp_arg(ctx, 0), buffer_type);
    if (buf == NULL) {
        zphp_throw(ctx, "TypeError", "demo_read(): Argument #1 ($buffer) must be an open DemoBuffer");
        return;
    }
    zphp_return_string(ctx, buf->data, buf->len);
}

/* demo_freed(): int, buffers destroyed so far in this process */
static void demo_freed(zphp_ctx *ctx)
{
    zphp_return_int(ctx, freed_buffers);
}

/* demo_describe(object $o): string, reads a property and calls a method */
static void demo_describe(zphp_ctx *ctx)
{
    const zphp_value *obj = zphp_arg(ctx, 0);
    if (zphp_type_of(obj) != ZPHP_OBJECT) {
        zphp_throw(ctx, "TypeError", "demo_describe(): Argument #1 ($o) must be of type object");
        return;
    }
    size_t class_len = 0;
    const char *class_name = zphp_object_class(ctx, obj, &class_len);
    zphp_value *label = zphp_call_method(ctx, obj, "label", NULL, 0);
    if (label == NULL) return;
    size_t label_len = 0;
    const char *label_text = zphp_get_string(ctx, label, &label_len);
    const zphp_value *count = zphp_object_get(ctx, obj, "count");
    char out[256];
    int n = snprintf(out, sizeof out, "%.*s(%.*s, count=%lld, tally=%s)", (int)class_len, class_name, (int)label_len, label_text,
                     (long long)zphp_get_int(count), zphp_instance_of(ctx, obj, "Demo\\Tally") ? "yes" : "no");
    zphp_return_string(ctx, out, (size_t)n);
}

/* Demo\Counter */
static void counter_construct(zphp_ctx *ctx)
{
    zphp_value *this = (zphp_value *)zphp_this(ctx);
    int64_t start = zphp_arg_count(ctx) > 0 ? zphp_get_int(zphp_arg(ctx, 0)) : 0;
    zphp_object_set(ctx, this, "count", zphp_int(ctx, start));
}

static void counter_increment(zphp_ctx *ctx)
{
    zphp_value *this = (zphp_value *)zphp_this(ctx);
    int64_t count = zphp_get_int(zphp_object_get(ctx, this, "count"));
    int64_t step = zphp_arg_count(ctx) > 0 ? zphp_get_int(zphp_arg(ctx, 0)) : 1;
    if (count + step > 10) {
        zphp_throw(ctx, "DemoException", "counter limit reached");
        return;
    }
    zphp_object_set(ctx, this, "count", zphp_int(ctx, count + step));
    zphp_return_value(ctx, this);
}

static void counter_value(zphp_ctx *ctx)
{
    zphp_return_value(ctx, zphp_object_get(ctx, zphp_this(ctx), "count"));
}

static void counter_label(zphp_ctx *ctx)
{
    zphp_return_string(ctx, "native counter", 14);
}

static void counter_make(zphp_ctx *ctx)
{
    zphp_value *obj = zphp_object(ctx, "Demo\\Counter");
    if (obj == NULL) {
        zphp_throw(ctx, "Error", "Demo\\Counter is not registered");
        return;
    }
    const zphp_value *args[1] = { zphp_arg(ctx, 0) };
    if (zphp_call_method(ctx, obj, "__construct", args, 1) == NULL) return;
    zphp_return_value(ctx, obj);
}

static int module_init(zphp_module *m)
{
    zphp_register_function(m, "demo_add", demo_add);
    zphp_register_function(m, "demo_greet", demo_greet);
    zphp_register_function(m, "demo_stats", demo_stats);
    zphp_register_function(m, "demo_types", demo_types);
    zphp_register_function(m, "demo_apply", demo_apply);
    zphp_register_function(m, "demo_throw", demo_throw);
    zphp_register_function(m, "demo_counter", demo_counter);
    zphp_register_function(m, "demo_hits", demo_hits);
    zphp_register_function(m, "demo_echo", demo_echo);
    zphp_register_function(m, "demo_open", demo_open);
    zphp_register_function(m, "demo_write", demo_write);
    zphp_register_function(m, "demo_read", demo_read);
    zphp_register_function(m, "demo_freed", demo_freed);
    zphp_register_function(m, "demo_describe", demo_describe);

    static const char *const tally_methods[] = { "value" };
    zphp_register_interface(m, "Demo\\Tally", tally_methods, 1);

    zphp_class *counter = zphp_register_class(m, "Demo\\Counter", NULL);
    zphp_class_implements(counter, "Demo\\Tally");
    zphp_class_add_property_int(counter, "count", 0);
    zphp_class_add_constant_int(counter, "LIMIT", 10);
    zphp_class_add_constant_string(counter, "NAME", "counter");
    zphp_class_add_method(counter, "__construct", counter_construct, 1, 0);
    zphp_class_add_method(counter, "increment", counter_increment, 1, 0);
    zphp_class_add_method(counter, "value", counter_value, 0, 0);
    zphp_class_add_method(counter, "label", counter_label, 0, 0);
    zphp_class_add_method(counter, "make", counter_make, 1, ZPHP_METHOD_STATIC);

    zphp_register_class(m, "DemoException", "Exception");

    zphp_register_constant_string(m, "DEMO_VERSION", "1.2.3");
    zphp_register_constant_int(m, "DEMO_ANSWER", 42);
    zphp_register_constant_float(m, "DEMO_RATIO", 0.5);
    zphp_register_constant_bool(m, "DEMO_ENABLED", true);
    zphp_register_ini(m, "demo.greeting", "hello");

    buffer_type = zphp_register_resource(m, "DemoBuffer", buffer_dtor);
    return buffer_type == 0 ? -1 : 0;
}

static int worker_init(zphp_ctx *ctx)
{
    zphp_set_worker_data(ctx, calloc(1, sizeof(worker_state)));
    return 0;
}

static void worker_shutdown(zphp_ctx *ctx)
{
    free(zphp_worker_data(ctx));
}

static int request_init(zphp_ctx *ctx)
{
    zphp_set_request_data(ctx, calloc(1, sizeof(request_state)));
    return 0;
}

static void request_shutdown(zphp_ctx *ctx)
{
    free(zphp_request_data(ctx));
}

static const zphp_extension demo_extension = {
    .abi = ZPHP_EXTENSION_ABI,
    .name = "demo",
    .version = "1.0.0",
    .module_init = module_init,
    .module_shutdown = NULL,
    .worker_init = worker_init,
    .worker_shutdown = worker_shutdown,
    .request_init = request_init,
    .request_shutdown = request_shutdown,
};

ZPHP_EXTENSION(demo, &demo_extension)
