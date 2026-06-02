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

## Copy-on-write

Like PHP, zphp uses copy-on-write for arrays. Assigning an array to a new variable, passing it to a function, or returning it shares the underlying data; the copy is made lazily the first time one side modifies the array.

```php
$a = [1, 2, 3, 4, 5];
$b = $a;   // shared, no copy
$b[2] = 0; // $b separates here; $a still [1,2,3,4,5]
```

The observable semantics are full value isolation - both ends behave as independent copies. Because the clone is deferred to the first write, reading or passing large arrays without modifying them costs nothing. Reference counting on the shared array decides when a write needs to separate; the request-boundary bulk free still reclaims everything at the end.

## Why no garbage collector

PHP's garbage collector handles reference cycles - objects that point to each other and can't be freed by reference counting alone. zphp doesn't need this because every heap-allocated value is tracked in a flat list and freed at the request boundary. Cycles are irrelevant when nothing survives the request.

## Environment variables

Environment variables are captured once when each worker thread starts, stored as a pre-built `$_ENV` array. Subsequent requests reference this snapshot directly. If you change environment variables after the server starts, workers won't see the changes until they're restarted.

## Stack and frame limits

The value stack holds 2,048 entries. The call stack supports 2,048 nested frames. Both are fixed at compile time, and exceeding them produces a runtime error.
