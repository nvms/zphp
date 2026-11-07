<?php
// php adds Stringable to a class or interface that declares __toString,
// directly or through a trait, so the interface's rules apply to it
class Plain { public function __toString(): string { return 'plain'; } }
class Child extends Plain {}
interface Named { public function __toString(): string; }
trait Printable { public function __toString(): string { return 'printable'; } }
class Printed { use Printable; }
class Counted implements Countable {
    public function count(): int { return 0; }
    public function __toString(): string { return 'counted'; }
}
foreach (['Plain', 'Child', 'Named', 'Printed', 'Counted'] as $name) {
    echo $name, ': ', implode(', ', (new ReflectionClass($name))->getInterfaceNames()), "\n";
}
var_dump(new Printed instanceof Stringable, (string) new Child);

echo "declaring\n";
if (true) {
    class Hidden { protected function __toString(): string { return 'hidden'; } }
}
echo "not reached\n";
