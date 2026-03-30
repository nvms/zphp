# Memory Model

zphp manages memory around the request lifecycle. Each request starts with a clean VM, and when the request ends, all allocations from that request are freed in bulk. There is no garbage collector.

## Request lifecycle

In serve mode, each worker thread owns a persistent VM instance. A request goes through these steps:

1. The VM resets, freeing all values (strings, arrays, objects, generators, fibers) from the previous request
2. Superglobals (`$_SERVER`, `$_GET`, `$_POST`, etc.) are populated from the incoming HTTP request
3. The PHP file executes from the top
4. The response is sent

Compiled bytecode is not freed between requests. It's compiled once at startup and re-executed each time.

Internal buffers are cleared between requests but keep their allocated capacity, so repeated requests reuse memory rather than reallocating.

## How values are stored

Primitives (integers, floats, booleans, null) live on a fixed-size value stack and don't require heap allocation.

Strings, arrays, and objects are heap-allocated and tracked in per-type lists on the VM. When a request ends, the VM walks each list and frees everything. Values cannot leak across requests.

## Copy-on-assign

PHP uses copy-on-write for arrays: assigning an array to a new variable shares the underlying data until one side is modified. zphp clones the array at the point of assignment instead.

```php
$a = [1, 2, 3, 4, 5];
$b = $a;  // zphp: full clone here. PHP: shared until modified.
```

The observable semantics are identical - both produce independent copies. The difference is when the copy happens. This can affect memory usage if you assign very large arrays without modifying the copy.

## Why no garbage collector

PHP's garbage collector handles reference cycles - objects that point to each other and can't be freed by reference counting alone. zphp doesn't need this because every heap-allocated value is tracked in a flat list and freed at the request boundary. Cycles are irrelevant when nothing survives the request.

## Environment variables

Environment variables are captured once when each worker thread starts, stored as a pre-built `$_ENV` array. Subsequent requests reference this snapshot directly. If you change environment variables after the server starts, workers won't see the changes until they're restarted.

## Stack and frame limits

The value stack holds 8,192 entries. The call stack supports 256 nested frames. Both are fixed at compile time, and exceeding them produces a runtime error.
