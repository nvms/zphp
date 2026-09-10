/*
 * zphp extension API.
 *
 * An extension is a C (or C-ABI) module that exports one entry point and
 * registers functions, classes, constants, ini defaults, and resource types
 * with zphp. The same source builds as a dynamic extension (a shared library
 * loaded with `--extension=PATH` or from `ZPHP_EXTENSION_DIR`) or as a static
 * extension compiled into zphp with `zig build -Dextension=PATH`.
 *
 * Every runtime call goes through the `zphp_api` table zphp hands to the entry
 * point, so an extension never links against zphp symbols and never sees the
 * layout of a PHP value. The inline wrappers below give the table ordinary
 * function names.
 *
 * Ownership: every `zphp_value` an extension receives or creates belongs to
 * the current request and must not be kept past the function that obtained
 * it. Bytes returned by zphp_get_string and zphp_ini_get follow the same
 * rule. Pointers stored with zphp_set_request_data are released by the
 * extension in request_shutdown; pointers stored with zphp_set_worker_data
 * live until worker_shutdown. Native handles wrapped with zphp_resource are
 * destroyed by the registered destructor when the PHP value is unset, goes
 * out of scope, is freed by an exception, or when the request ends.
 */
#ifndef ZPHP_EXTENSION_H
#define ZPHP_EXTENSION_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#define ZPHP_EXTENSION_ABI 1u

#if defined(_WIN32)
#define ZPHP_EXPORT __declspec(dllexport)
#else
#define ZPHP_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct zphp_ctx zphp_ctx;       /* one call, hook invocation, or lifecycle event */
typedef struct zphp_value zphp_value;   /* a PHP value */
typedef struct zphp_module zphp_module; /* registration handle passed to module_init */
typedef struct zphp_class zphp_class;   /* a class being registered */

typedef void (*zphp_fn)(zphp_ctx *ctx);
typedef void (*zphp_resource_dtor)(void *ptr);

typedef enum zphp_type {
    ZPHP_NULL = 0,
    ZPHP_BOOL = 1,
    ZPHP_INT = 2,
    ZPHP_FLOAT = 3,
    ZPHP_STRING = 4,
    ZPHP_ARRAY = 5,
    ZPHP_OBJECT = 6,
    ZPHP_OTHER = 7
} zphp_type;

enum {
    ZPHP_METHOD_STATIC = 1
};

/*
 * Lifecycle. module_init runs once per process when the extension loads and
 * is the only place registration is allowed. worker_init/worker_shutdown run
 * once per VM (one per serve worker, one for a CLI run); request_init and
 * request_shutdown wrap every request. Hooks returning int report failure
 * with a non-zero value: module_init failure rejects the extension, the
 * others fail the worker or request. Any hook may be NULL.
 */
typedef struct zphp_extension {
    uint32_t abi;
    const char *name;
    const char *version;
    int (*module_init)(zphp_module *m);
    void (*module_shutdown)(void);
    int (*worker_init)(zphp_ctx *ctx);
    void (*worker_shutdown)(zphp_ctx *ctx);
    int (*request_init)(zphp_ctx *ctx);
    void (*request_shutdown)(zphp_ctx *ctx);
} zphp_extension;

typedef struct zphp_api {
    uint32_t abi;

    /* registration (module_init only). 0 on success, -1 on failure */
    int (*register_function)(zphp_module *m, const char *name, zphp_fn fn);
    zphp_class *(*register_class)(zphp_module *m, const char *name, const char *parent);
    int (*class_add_method)(zphp_class *cls, const char *name, zphp_fn fn, uint8_t arity, uint32_t flags);
    int (*class_add_constant_int)(zphp_class *cls, const char *name, int64_t value);
    int (*class_add_constant_float)(zphp_class *cls, const char *name, double value);
    int (*class_add_constant_bool)(zphp_class *cls, const char *name, bool value);
    int (*class_add_constant_string)(zphp_class *cls, const char *name, const char *value);
    int (*class_add_property)(zphp_class *cls, const char *name);
    int (*class_add_property_int)(zphp_class *cls, const char *name, int64_t value);
    int (*class_add_property_string)(zphp_class *cls, const char *name, const char *value);
    int (*class_implements)(zphp_class *cls, const char *interface_name);
    int (*register_interface)(zphp_module *m, const char *name, const char *const *methods, size_t method_count);
    int (*register_constant_int)(zphp_module *m, const char *name, int64_t value);
    int (*register_constant_float)(zphp_module *m, const char *name, double value);
    int (*register_constant_bool)(zphp_module *m, const char *name, bool value);
    int (*register_constant_string)(zphp_module *m, const char *name, const char *value);
    int (*register_ini)(zphp_module *m, const char *name, const char *default_value);
    uint32_t (*register_resource)(zphp_module *m, const char *class_name, zphp_resource_dtor dtor);

    /* arguments and $this */
    size_t (*arg_count)(zphp_ctx *ctx);
    const zphp_value *(*arg)(zphp_ctx *ctx, size_t index);
    const zphp_value *(*this_object)(zphp_ctx *ctx);

    /* reading values */
    zphp_type (*type_of)(const zphp_value *v);
    int64_t (*get_int)(const zphp_value *v);
    double (*get_float)(const zphp_value *v);
    bool (*get_bool)(const zphp_value *v);
    const char *(*get_string)(zphp_ctx *ctx, const zphp_value *v, size_t *len);

    /* creating values */
    zphp_value *(*make_null)(zphp_ctx *ctx);
    zphp_value *(*make_bool)(zphp_ctx *ctx, bool value);
    zphp_value *(*make_int)(zphp_ctx *ctx, int64_t value);
    zphp_value *(*make_float)(zphp_ctx *ctx, double value);
    zphp_value *(*make_string)(zphp_ctx *ctx, const char *bytes, size_t len);

    /* arrays */
    zphp_value *(*make_array)(zphp_ctx *ctx);
    size_t (*array_count)(const zphp_value *array);
    int (*array_push)(zphp_ctx *ctx, zphp_value *array, const zphp_value *value);
    int (*array_set_int)(zphp_ctx *ctx, zphp_value *array, int64_t key, const zphp_value *value);
    int (*array_set_string)(zphp_ctx *ctx, zphp_value *array, const char *key, size_t key_len, const zphp_value *value);
    const zphp_value *(*array_get_int)(zphp_ctx *ctx, const zphp_value *array, int64_t key);
    const zphp_value *(*array_get_string)(zphp_ctx *ctx, const zphp_value *array, const char *key, size_t key_len);
    int (*array_at)(zphp_ctx *ctx, const zphp_value *array, size_t index, const zphp_value **key, const zphp_value **value);

    /* objects */
    zphp_value *(*make_object)(zphp_ctx *ctx, const char *class_name);
    const char *(*object_class)(zphp_ctx *ctx, const zphp_value *object, size_t *len);
    bool (*instance_of)(zphp_ctx *ctx, const zphp_value *value, const char *class_name);
    const zphp_value *(*object_get)(zphp_ctx *ctx, const zphp_value *object, const char *name);
    int (*object_set)(zphp_ctx *ctx, zphp_value *object, const char *name, const zphp_value *value);

    /* resources: a native pointer wrapped in an instance of the class registered for the type */
    zphp_value *(*make_resource)(zphp_ctx *ctx, uint32_t type, void *ptr);
    void *(*resource_ptr)(zphp_ctx *ctx, const zphp_value *value, uint32_t type);

    /* calling back into PHP. NULL means the call threw; the exception propagates when the extension function returns */
    zphp_value *(*call)(zphp_ctx *ctx, const char *function, const zphp_value *const *args, size_t arg_count);
    zphp_value *(*call_method)(zphp_ctx *ctx, const zphp_value *object, const char *method, const zphp_value *const *args, size_t arg_count);

    /* exceptions: the extension function should return after throwing */
    void (*throw_exception)(zphp_ctx *ctx, const char *class_name, const char *message);

    /* the function's return value (null when none is set) */
    void (*return_null)(zphp_ctx *ctx);
    void (*return_bool)(zphp_ctx *ctx, bool value);
    void (*return_int)(zphp_ctx *ctx, int64_t value);
    void (*return_float)(zphp_ctx *ctx, double value);
    void (*return_string)(zphp_ctx *ctx, const char *bytes, size_t len);
    void (*return_value)(zphp_ctx *ctx, const zphp_value *value);

    /* output and configuration */
    void (*echo)(zphp_ctx *ctx, const char *bytes, size_t len);
    const char *(*ini_get)(zphp_ctx *ctx, const char *name, size_t *len);

    /* per-extension state slots on the current VM */
    void *(*request_data)(zphp_ctx *ctx);
    void (*set_request_data)(zphp_ctx *ctx, void *data);
    void *(*worker_data)(zphp_ctx *ctx);
    void (*set_worker_data)(zphp_ctx *ctx, void *data);
} zphp_api;

typedef const zphp_extension *(*zphp_entry_fn)(const zphp_api *api);

extern const zphp_api *zphp_api_v1;

/*
 * ZPHP_EXTENSION(ident, descriptor_pointer) defines the entry point. `ident`
 * must be a C identifier; for a static extension it must match the source
 * file's stem, which is how the build finds the entry.
 */
#ifdef ZPHP_STATIC_EXTENSION
#define ZPHP_EXTENSION_DYNAMIC_ENTRY(ident)
#else
#define ZPHP_EXTENSION_DYNAMIC_ENTRY(ident) \
    ZPHP_EXPORT const zphp_extension *zphp_extension_entry(const zphp_api *api) { return zphp_extension_entry_##ident(api); }
#endif

#define ZPHP_EXTENSION(ident, descriptor) \
    const zphp_api *zphp_api_v1 = 0; \
    ZPHP_EXPORT const zphp_extension *zphp_extension_entry_##ident(const zphp_api *api) { \
        zphp_api_v1 = api; \
        return (descriptor); \
    } \
    ZPHP_EXTENSION_DYNAMIC_ENTRY(ident)

/* registration */
static inline int zphp_register_function(zphp_module *m, const char *name, zphp_fn fn) { return zphp_api_v1->register_function(m, name, fn); }
static inline zphp_class *zphp_register_class(zphp_module *m, const char *name, const char *parent) { return zphp_api_v1->register_class(m, name, parent); }
static inline int zphp_class_add_method(zphp_class *cls, const char *name, zphp_fn fn, uint8_t arity, uint32_t flags) { return zphp_api_v1->class_add_method(cls, name, fn, arity, flags); }
static inline int zphp_class_add_constant_int(zphp_class *cls, const char *name, int64_t value) { return zphp_api_v1->class_add_constant_int(cls, name, value); }
static inline int zphp_class_add_constant_float(zphp_class *cls, const char *name, double value) { return zphp_api_v1->class_add_constant_float(cls, name, value); }
static inline int zphp_class_add_constant_bool(zphp_class *cls, const char *name, bool value) { return zphp_api_v1->class_add_constant_bool(cls, name, value); }
static inline int zphp_class_add_constant_string(zphp_class *cls, const char *name, const char *value) { return zphp_api_v1->class_add_constant_string(cls, name, value); }
static inline int zphp_class_add_property(zphp_class *cls, const char *name) { return zphp_api_v1->class_add_property(cls, name); }
static inline int zphp_class_add_property_int(zphp_class *cls, const char *name, int64_t value) { return zphp_api_v1->class_add_property_int(cls, name, value); }
static inline int zphp_class_add_property_string(zphp_class *cls, const char *name, const char *value) { return zphp_api_v1->class_add_property_string(cls, name, value); }
static inline int zphp_class_implements(zphp_class *cls, const char *interface_name) { return zphp_api_v1->class_implements(cls, interface_name); }
static inline int zphp_register_interface(zphp_module *m, const char *name, const char *const *methods, size_t method_count) { return zphp_api_v1->register_interface(m, name, methods, method_count); }
static inline int zphp_register_constant_int(zphp_module *m, const char *name, int64_t value) { return zphp_api_v1->register_constant_int(m, name, value); }
static inline int zphp_register_constant_float(zphp_module *m, const char *name, double value) { return zphp_api_v1->register_constant_float(m, name, value); }
static inline int zphp_register_constant_bool(zphp_module *m, const char *name, bool value) { return zphp_api_v1->register_constant_bool(m, name, value); }
static inline int zphp_register_constant_string(zphp_module *m, const char *name, const char *value) { return zphp_api_v1->register_constant_string(m, name, value); }
static inline int zphp_register_ini(zphp_module *m, const char *name, const char *default_value) { return zphp_api_v1->register_ini(m, name, default_value); }
static inline uint32_t zphp_register_resource(zphp_module *m, const char *class_name, zphp_resource_dtor dtor) { return zphp_api_v1->register_resource(m, class_name, dtor); }

/* arguments and $this */
static inline size_t zphp_arg_count(zphp_ctx *ctx) { return zphp_api_v1->arg_count(ctx); }
static inline const zphp_value *zphp_arg(zphp_ctx *ctx, size_t index) { return zphp_api_v1->arg(ctx, index); }
static inline const zphp_value *zphp_this(zphp_ctx *ctx) { return zphp_api_v1->this_object(ctx); }

/* reading values. get_int/get_float/get_bool convert the way PHP casts do */
static inline zphp_type zphp_type_of(const zphp_value *v) { return zphp_api_v1->type_of(v); }
static inline int64_t zphp_get_int(const zphp_value *v) { return zphp_api_v1->get_int(v); }
static inline double zphp_get_float(const zphp_value *v) { return zphp_api_v1->get_float(v); }
static inline bool zphp_get_bool(const zphp_value *v) { return zphp_api_v1->get_bool(v); }
static inline const char *zphp_get_string(zphp_ctx *ctx, const zphp_value *v, size_t *len) { return zphp_api_v1->get_string(ctx, v, len); }

/* creating values */
static inline zphp_value *zphp_null(zphp_ctx *ctx) { return zphp_api_v1->make_null(ctx); }
static inline zphp_value *zphp_bool(zphp_ctx *ctx, bool value) { return zphp_api_v1->make_bool(ctx, value); }
static inline zphp_value *zphp_int(zphp_ctx *ctx, int64_t value) { return zphp_api_v1->make_int(ctx, value); }
static inline zphp_value *zphp_float(zphp_ctx *ctx, double value) { return zphp_api_v1->make_float(ctx, value); }
static inline zphp_value *zphp_string(zphp_ctx *ctx, const char *bytes, size_t len) { return zphp_api_v1->make_string(ctx, bytes, len); }

/* arrays */
static inline zphp_value *zphp_array(zphp_ctx *ctx) { return zphp_api_v1->make_array(ctx); }
static inline size_t zphp_array_count(const zphp_value *array) { return zphp_api_v1->array_count(array); }
static inline int zphp_array_push(zphp_ctx *ctx, zphp_value *array, const zphp_value *value) { return zphp_api_v1->array_push(ctx, array, value); }
static inline int zphp_array_set_int(zphp_ctx *ctx, zphp_value *array, int64_t key, const zphp_value *value) { return zphp_api_v1->array_set_int(ctx, array, key, value); }
static inline int zphp_array_set_string(zphp_ctx *ctx, zphp_value *array, const char *key, size_t key_len, const zphp_value *value) { return zphp_api_v1->array_set_string(ctx, array, key, key_len, value); }
static inline const zphp_value *zphp_array_get_int(zphp_ctx *ctx, const zphp_value *array, int64_t key) { return zphp_api_v1->array_get_int(ctx, array, key); }
static inline const zphp_value *zphp_array_get_string(zphp_ctx *ctx, const zphp_value *array, const char *key, size_t key_len) { return zphp_api_v1->array_get_string(ctx, array, key, key_len); }
static inline int zphp_array_at(zphp_ctx *ctx, const zphp_value *array, size_t index, const zphp_value **key, const zphp_value **value) { return zphp_api_v1->array_at(ctx, array, index, key, value); }

/* objects */
static inline zphp_value *zphp_object(zphp_ctx *ctx, const char *class_name) { return zphp_api_v1->make_object(ctx, class_name); }
static inline const char *zphp_object_class(zphp_ctx *ctx, const zphp_value *object, size_t *len) { return zphp_api_v1->object_class(ctx, object, len); }
static inline bool zphp_instance_of(zphp_ctx *ctx, const zphp_value *value, const char *class_name) { return zphp_api_v1->instance_of(ctx, value, class_name); }
static inline const zphp_value *zphp_object_get(zphp_ctx *ctx, const zphp_value *object, const char *name) { return zphp_api_v1->object_get(ctx, object, name); }
static inline int zphp_object_set(zphp_ctx *ctx, zphp_value *object, const char *name, const zphp_value *value) { return zphp_api_v1->object_set(ctx, object, name, value); }

/* resources */
static inline zphp_value *zphp_resource(zphp_ctx *ctx, uint32_t type, void *ptr) { return zphp_api_v1->make_resource(ctx, type, ptr); }
static inline void *zphp_resource_ptr(zphp_ctx *ctx, const zphp_value *value, uint32_t type) { return zphp_api_v1->resource_ptr(ctx, value, type); }

/* calling PHP */
static inline zphp_value *zphp_call(zphp_ctx *ctx, const char *function, const zphp_value *const *args, size_t arg_count) { return zphp_api_v1->call(ctx, function, args, arg_count); }
static inline zphp_value *zphp_call_method(zphp_ctx *ctx, const zphp_value *object, const char *method, const zphp_value *const *args, size_t arg_count) { return zphp_api_v1->call_method(ctx, object, method, args, arg_count); }

/* exceptions */
static inline void zphp_throw(zphp_ctx *ctx, const char *class_name, const char *message) { zphp_api_v1->throw_exception(ctx, class_name, message); }

/* return values */
static inline void zphp_return_null(zphp_ctx *ctx) { zphp_api_v1->return_null(ctx); }
static inline void zphp_return_bool(zphp_ctx *ctx, bool value) { zphp_api_v1->return_bool(ctx, value); }
static inline void zphp_return_int(zphp_ctx *ctx, int64_t value) { zphp_api_v1->return_int(ctx, value); }
static inline void zphp_return_float(zphp_ctx *ctx, double value) { zphp_api_v1->return_float(ctx, value); }
static inline void zphp_return_string(zphp_ctx *ctx, const char *bytes, size_t len) { zphp_api_v1->return_string(ctx, bytes, len); }
static inline void zphp_return_value(zphp_ctx *ctx, const zphp_value *value) { zphp_api_v1->return_value(ctx, value); }

/* output and configuration */
static inline void zphp_echo(zphp_ctx *ctx, const char *bytes, size_t len) { zphp_api_v1->echo(ctx, bytes, len); }
static inline const char *zphp_ini_get(zphp_ctx *ctx, const char *name, size_t *len) { return zphp_api_v1->ini_get(ctx, name, len); }

/* state slots */
static inline void *zphp_request_data(zphp_ctx *ctx) { return zphp_api_v1->request_data(ctx); }
static inline void zphp_set_request_data(zphp_ctx *ctx, void *data) { zphp_api_v1->set_request_data(ctx, data); }
static inline void *zphp_worker_data(zphp_ctx *ctx) { return zphp_api_v1->worker_data(ctx); }
static inline void zphp_set_worker_data(zphp_ctx *ctx, void *data) { zphp_api_v1->set_worker_data(ctx, data); }

#ifdef __cplusplus
}
#endif

#endif
