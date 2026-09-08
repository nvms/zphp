<?php
function failWithString(): string {
    throw new RuntimeException('failure');
}
function consumeStrings(string $first, string $second): void {}
class StringTarget {
    public array $values = [];
}
$target = new StringTarget();
for ($i = 0; $i < 20; ++$i) {
    try {
        consumeStrings('argument-' . $i, failWithString());
    } catch (RuntimeException $e) {}
    try {
        $target->values['key-' . $i] = failWithString();
    } catch (RuntimeException $e) {}
}
gc_collect_cycles();
var_dump($target->values);
echo "caught\n";
