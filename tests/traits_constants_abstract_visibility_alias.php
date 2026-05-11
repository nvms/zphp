<?php
trait HasVersion {
    public const VERSION = "1.0";
    public const MAJOR = 1;
    public const MINOR = 0;
}

class App {
    use HasVersion;
}

echo App::VERSION, "\n";
echo App::MAJOR, " ", App::MINOR, "\n";

class App2 {
    use HasVersion;
}

echo App2::VERSION, "\n";
echo App2::MAJOR, "\n";

trait WithMethod {
    public function pub(): string { return "T-pub"; }
    protected function prot(): string { return "T-prot"; }
    private function priv(): string { return "T-priv"; }
}

class C1 {
    use WithMethod;
    public function dump(): array {
        return [$this->pub(), $this->prot(), $this->priv()];
    }
}

$c = new C1;
echo $c->pub(), "\n";
print_r($c->dump());

trait AbstractMix {
    abstract public function getName(): string;
    public function hello(): string {
        return "hello, " . $this->getName();
    }
}

class Named {
    use AbstractMix;
    public function getName(): string { return "alice"; }
}

echo (new Named)->hello(), "\n";

abstract class AbsBase {
    use AbstractMix;
}

class NamedFromBase extends AbsBase {
    public function getName(): string { return "from-base"; }
}

echo (new NamedFromBase)->hello(), "\n";

trait WithConst {
    public const X = 100;
}
trait WithMethod2 {
    public function getX(): int { return self::X; }
}

class HasBoth {
    use WithConst, WithMethod2;
}
echo (new HasBoth)->getX(), "\n";
echo HasBoth::X, "\n";

trait Greeter {
    public function greet(): string { return "Greeter::greet"; }
}
trait Farewell {
    public function greet(): string { return "Farewell::greet"; }
}

class Conflict {
    use Greeter, Farewell {
        Greeter::greet insteadof Farewell;
        Farewell::greet as farewell;
    }
}

$x = new Conflict;
echo $x->greet(), "\n";
echo $x->farewell(), "\n";

trait Renamable {
    public function publish(): string { return "trait-publish"; }
}

class WithAlias {
    use Renamable {
        publish as private internalPublish;
    }
    public function go(): string { return $this->internalPublish(); }
}

echo (new WithAlias)->go(), "\n";

trait Properties {
    public string $name = "default";
    public int $count = 0;
}

class WithProps {
    use Properties;
    public function describe(): string { return "$this->name/$this->count"; }
}

$o = new WithProps;
echo $o->describe(), "\n";
$o->name = "custom";
$o->count = 5;
echo $o->describe(), "\n";

trait Stat {
    public static int $shared = 0;
}

class S1 { use Stat; }
class S2 { use Stat; }
echo S1::$shared, " ", S2::$shared, "\n";
S1::$shared = 5;
echo S1::$shared, "\n";

trait T1 { public function a(): string { return "T1::a"; } }
trait T2 { public function b(): string { return "T2::b"; } }
trait T3 {
    use T1, T2;
    public function c(): string { return "T3::c"; }
}

class HasNested { use T3; }
$n = new HasNested;
echo $n->a(), " ", $n->b(), " ", $n->c(), "\n";

trait AbsConcrete {
    abstract public function impl(): int;
    public function double(): int { return $this->impl() * 2; }
    public function triple(): int { return $this->impl() * 3; }
}

class Concrete {
    use AbsConcrete;
    public function impl(): int { return 5; }
}

$c = new Concrete;
echo $c->double(), " ", $c->triple(), "\n";

trait T4 {
    public function shared(): string { return "T4"; }
}

trait T5 {
    public function shared(): string { return "T5"; }
}

class PickT4 {
    use T4, T5 {
        T4::shared insteadof T5;
    }
}
class PickT5 {
    use T4, T5 {
        T5::shared insteadof T4;
    }
}
echo (new PickT4)->shared(), "\n";
echo (new PickT5)->shared(), "\n";

trait WithVisModifier {
    public function pub(): string { return "vis-modified"; }
}

class VisChanged {
    use WithVisModifier {
        pub as protected protectedPub;
    }
    public function callInternal(): string { return $this->protectedPub(); }
}

echo (new VisChanged)->callInternal(), "\n";

trait StaticTrait {
    public static function create(string $n): self { return new self; }
}

class Item {
    use StaticTrait;
    public string $name = "default";
}

echo get_class(Item::create("test")), "\n";
