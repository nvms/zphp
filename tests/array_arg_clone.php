<?php
// regression: array function parameters must be cloned at call boundary
// so unset/sort/ksort inside the callee don't mutate the caller's array.
// the bug was that method_call (and several sibling call sites) stored
// self.stack[arg] directly into new_vars without copyValue - the callee
// then operated on the caller's underlying PhpArray. mirrors WordPress's
// WP_Query::generate_cache_key which unsets 7 keys + ksort on $args,
// causing the caller's $query_vars to lose those keys.
class Holder {
    public array $data;
    public function __construct(array $data) { $this->data = $data; }
}
class Sink {
    public function ksort_and_unset(array $args): int {
        unset($args['c'], $args['e']);
        ksort($args);
        return count($args);
    }
}
$h = new Holder(['z' => 1, 'a' => 2, 'c' => 3, 'b' => 4, 'e' => 5]);
$keys_before = array_keys($h->data);
$result = (new Sink)->ksort_and_unset($h->data);
$keys_after = array_keys($h->data);
echo "callee count: $result\n";
echo "before: ", implode(',', $keys_before), "\n";
echo "after:  ", implode(',', $keys_after), "\n";
echo "preserved: ", ($keys_before === $keys_after ? 'yes' : 'no'), "\n";
