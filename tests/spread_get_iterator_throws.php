<?php
// an exception from getIterator() or a generator ends argument and array
// spreading and reaches the caller's catch
function take(...$args) { var_dump($args); }
class Items implements IteratorAggregate {
    public function getIterator(): Traversable { throw new RuntimeException('getIterator'); }
}
function rows() { yield 1; throw new RuntimeException('rows'); }
foreach ([fn () => take(1, ...new Items, ...[2]), fn () => take(...rows()), fn () => [...new Items], fn () => [0, ...rows()]] as $f) {
    try { $f(); } catch (RuntimeException $e) { echo "caught ", $e->getMessage(), "\n"; }
}
