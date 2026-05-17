<?php
// regression: set_prop's IC fast path was writing to obj.slots[idx] but
// not clearing the unset marker that init()'s unset($this->prop) had set.
// subsequent get_prop saw the unset marker and returned null (or fell to
// __get). second invocation of the same method (where IC is hot) failed
// because every property write that resurrected an unset slot silently
// failed at the IC level, while the first invocation took the slow path
// which DOES clearUnset. mirrors WordPress::WP_Query's init() unset(query)
// followed by query() reassigning $this->query
class C {
    public string $name = 'default';
    public function reset() { unset($this->name); }
    public function set($n) {
        $this->reset();
        $this->name = $n;
    }
}
$c = new C();
$c->set('first');
$c->set('second');
$c->set('third');
echo $c->name, "\n";
