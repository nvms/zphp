<?php

class Foo_readonly_clone_success1 {
    public function __construct(
        public readonly int $bar
    ) {}

    public function __clone()
    {
        $this->bar++;
    }
}

$foo = new Foo_readonly_clone_success1(1);

var_dump(clone $foo);

$foo2 = clone $foo;
var_dump($foo2);

var_dump(clone $foo2);


class Foo_readonly_clone_error1 {
    public function __construct(
        public readonly int $bar
    ) {}

    public function __clone()
    {
        $this->bar = 2;
        var_dump($this);
        $this->bar = 3;
    }
}

$foo = new Foo_readonly_clone_error1(1);

try {
    clone $foo;
} catch (Error $exception) {
    echo $exception->getMessage() . "\n";
}

echo "done";


readonly class Clazz_clone_with_008 {
	public function __construct(
		public public(set) string $a,
		public public(set) string $b,
	) { }

	public function __clone() {
		$this->b = '__clone';
	}
}

$c = new Clazz_clone_with_008('default', 'default');

var_dump(clone($c, [ 'a' => "with" ]));

try {
	var_dump(clone($c, [ 'b' => "with" ]));
} catch (Throwable $e) {
	echo $e::class, ": ", $e->getMessage(), PHP_EOL;
}


class Clazz_clone_with_012 {
	public string $foo {
		set {
			$this->foo = $value;
			$this->bar = 'bar updated in hook';
		}
	}

	public public(set) readonly string $bar;
}

$f = new Clazz_clone_with_012();

var_dump(clone($f, ['foo' => 'foo updated in clone-with']));

try {
	var_dump(clone($f, ['foo' => 'foo updated in clone-with', 'bar' => 'bar updated in clone-with']));
} catch (Throwable $e) {
	echo $e::class, ": ", $e->getMessage(), PHP_EOL;
}

class FooR {
    public function __construct(public readonly int $bar) {}
    public function __clone() { $this->bar += 2; throw new Exception("x"); }
}
$foo = new FooR(1);
try { clone $foo; } catch (Exception $e) { echo $e->getMessage(), "\n"; }
var_dump(spl_object_id(new stdClass));
unset($e);
var_dump(spl_object_id(new stdClass));
class BarR { public function __clone() { throw new Exception("y"); } }
$b = new BarR;
try { clone $b; } catch (Exception $e) { echo $e->getMessage(), "\n"; }
var_dump(spl_object_id(new stdClass));
