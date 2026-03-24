<?php

// trait conflict resolution: insteadof and as

trait A {
    public function hello(): string { return "A::hello"; }
    public function shared(): string { return "A::shared"; }
}

trait B {
    public function world(): string { return "B::world"; }
    public function shared(): string { return "B::shared"; }
}

// insteadof to resolve conflict, as to alias the excluded method
class Foo {
    use A, B {
        A::shared insteadof B;
        B::shared as sharedFromB;
    }
}

$f = new Foo();
echo $f->hello() . "\n";
echo $f->world() . "\n";
echo $f->shared() . "\n";
echo $f->sharedFromB() . "\n";

// simple alias without conflict
trait Logger {
    public function log(string $msg): string { return "log:" . $msg; }
}

class App {
    use Logger {
        Logger::log as writeLog;
    }
}

$app = new App();
echo $app->log("test") . "\n";
echo $app->writeLog("test") . "\n";

// three traits, multiple conflicts
trait X {
    public function run(): string { return "X"; }
}
trait Y {
    public function run(): string { return "Y"; }
}
trait Z {
    public function run(): string { return "Z"; }
}

class Multi {
    use X, Y, Z {
        X::run insteadof Y, Z;
        Y::run as runY;
        Z::run as runZ;
    }
}

$m = new Multi();
echo $m->run() . "\n";
echo $m->runY() . "\n";
echo $m->runZ() . "\n";
