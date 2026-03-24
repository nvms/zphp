# performance optimization backlog

potential improvements to investigate. not prioritized, not promised - just documented avenues for when the time comes.

## serve

### shrink idle connection buffers
current: 65 KB per-connection read buffer allocated at connect time. most WebSocket frames are < 1 KB.
change: allocate 4 KB initially, grow to 65 KB on demand when a large frame arrives. shrink back after processing.
impact: per-connection overhead drops from ~68 KB to ~8 KB. at 1000 connections, total memory drops from ~72 MB to ~15 MB.

### HTTP throughput - VM dispatch overhead
current: zphp's VM uses hash-map-based variable lookup (`StringHashMap`) per frame. every `get_var`/`set_var` is a hash lookup.
change: register-based variable indexing at compile time (variables get numeric slots, accessed by index instead of name).
impact: significant speedup for all PHP execution. this is the single biggest performance gap between zphp and Zend/Swoole.

### writev for response coalescing
current: separate `write()` calls for HTTP headers and body.
change: use `writev()` (scatter-gather I/O) to send headers + body in a single syscall.
impact: reduces syscalls per response from 2 to 1. small but measurable at high request rates.

## VM

### register-based locals
current: variables stored in `StringHashMapUnmanaged(Value)` per frame. every variable access is a hash lookup.
change: compiler assigns stack slots to local variables. `get_var`/`set_var` become indexed reads/writes to a fixed-size array.
impact: eliminates hash overhead for the most frequent operations. estimated 2-5x speedup for variable-heavy code.

### constant folding
current: `evalConstExpr()` handles basic literals for default parameter values only.
change: expand to fold constant binary expressions (`2 + 3`), string concatenation of literals, array construction from constants.
impact: reduces runtime work for static expressions. moderate impact.

### inline caching for property access
current: `get_prop`/`set_prop` do a hash lookup on the object's property map every time.
change: cache the property offset after first lookup (monomorphic inline cache).
impact: significant for OOP-heavy code. property access becomes O(1) after warmup.

## arrays

### hash table for large arrays
current: `PhpArray` uses linear scan (`O(n)`) for all lookups.
change: switch to hash table (or hybrid: linear for < 8 entries, hash for larger) for key lookup.
impact: critical for any code using arrays with 100+ elements. current implementation is `O(n)` per lookup.

## strings

### string interning
current: identical strings may exist as separate heap allocations.
change: intern strings in a global table. string comparison becomes pointer comparison.
impact: reduces memory usage and speeds up string comparison in hash maps, switch statements, and equality checks.
