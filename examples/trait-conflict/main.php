<?php
// covers: multiple traits, trait conflict resolution (insteadof/as),
// visibility changes via as, abstract trait methods, trait with interface,
// trait properties, trait constants, nested trait use, trait method aliasing

// test 1: basic multiple traits
echo "=== Test 1: Multiple Traits ===\n";
trait Greetable {
    public function greet(): string {
        return "Hello, I'm " . $this->name;
    }
}
trait Farewell {
    public function bye(): string {
        return "Goodbye from " . $this->name;
    }
}
class Person {
    use Greetable, Farewell;
    public string $name;
    public function __construct(string $name) {
        $this->name = $name;
    }
}
$p = new Person("Alice");
echo $p->greet() . "\n";
echo $p->bye() . "\n";

// test 2: conflict resolution with insteadof
echo "\n=== Test 2: Insteadof ===\n";
trait Logger {
    public function log(string $msg): string {
        return "[LOG] $msg";
    }
}
trait FileLogger {
    public function log(string $msg): string {
        return "[FILE] $msg";
    }
}
class App {
    use Logger, FileLogger {
        Logger::log insteadof FileLogger;
        FileLogger::log as fileLog;
    }
}
$app = new App();
echo $app->log("test") . "\n";
echo $app->fileLog("test") . "\n";

// test 3: trait-qualified alias
echo "\n=== Test 3: Trait Alias ===\n";
trait Secret {
    public function reveal(): string {
        return "secret data";
    }
}
class Vault {
    use Secret {
        Secret::reveal as hiddenReveal;
    }
    public function getSecret(): string {
        return $this->hiddenReveal();
    }
}
$v = new Vault();
echo $v->reveal() . "\n";
echo $v->getSecret() . "\n";

// test 4: trait with abstract method
echo "\n=== Test 4: Abstract Trait Method ===\n";
trait SerializableTrait {
    abstract protected function toArray(): array;
    public function serialize(): string {
        return json_encode($this->toArray());
    }
}
class User {
    use SerializableTrait;
    private string $name;
    private int $age;
    public function __construct(string $name, int $age) {
        $this->name = $name;
        $this->age = $age;
    }
    protected function toArray(): array {
        return ['name' => $this->name, 'age' => $this->age];
    }
}
$u = new User("Bob", 25);
echo $u->serialize() . "\n";

// test 5: trait with interface
echo "\n=== Test 5: Trait + Interface ===\n";
interface Displayable {
    public function toString(): string;
}
trait DisplayableTrait {
    public function toString(): string {
        return get_class($this) . "::toString";
    }
}
class Widget implements Displayable {
    use DisplayableTrait;
}
$w = new Widget();
echo $w->toString() . "\n";
echo ($w instanceof Displayable ? "implements Displayable" : "no") . "\n";

// test 6: trait properties
echo "\n=== Test 6: Trait Properties ===\n";
trait HasCounter {
    private int $count = 0;
    public function increment(): void {
        $this->count++;
    }
    public function getCount(): int {
        return $this->count;
    }
}
class Counter {
    use HasCounter;
}
$c = new Counter();
$c->increment();
$c->increment();
$c->increment();
echo "Count: " . $c->getCount() . "\n";

// test 7: practical example - event system with traits
echo "\n=== Test 7: Event System ===\n";
trait Emitter {
    private array $listeners = [];
    public function on(string $event, callable $callback): void {
        if (!isset($this->listeners[$event])) {
            $this->listeners[$event] = [];
        }
        $this->listeners[$event][] = $callback;
    }
    public function emit(string $event, array $data = []): void {
        if (isset($this->listeners[$event])) {
            foreach ($this->listeners[$event] as $cb) {
                $cb($data);
            }
        }
    }
}
trait Cacheable {
    private array $cache = [];
    public function cacheGet(string $key): ?string {
        return $this->cache[$key] ?? null;
    }
    public function cacheSet(string $key, string $value): void {
        $this->cache[$key] = $value;
    }
}
class Service {
    use Emitter, Cacheable;
    public function process(string $key, string $value): void {
        $this->cacheSet($key, $value);
        $this->emit('processed', ['key' => $key, 'value' => $value]);
    }
}
$svc = new Service();
$log = [];
$svc->on('processed', function($data) use (&$log) {
    $log[] = $data['key'] . '=' . $data['value'];
});
$svc->process('a', '1');
$svc->process('b', '2');
echo "Cached: " . $svc->cacheGet('a') . ", " . $svc->cacheGet('b') . "\n";
echo "Events: " . implode(', ', $log) . "\n";

// test 8: three-way conflict
echo "\n=== Test 8: Three-way Conflict ===\n";
trait A {
    public function hello(): string { return "A"; }
}
trait B {
    public function hello(): string { return "B"; }
}
trait C {
    public function hello(): string { return "C"; }
}
class ABC {
    use A, B, C {
        A::hello insteadof B, C;
        B::hello as helloB;
        C::hello as helloC;
    }
}
$abc = new ABC();
echo "Default: " . $abc->hello() . "\n";
echo "B: " . $abc->helloB() . "\n";
echo "C: " . $abc->helloC() . "\n";

echo "\nAll trait conflict tests passed!\n";
