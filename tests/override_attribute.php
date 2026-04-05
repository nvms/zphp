<?php
// covers: #[Override] attribute enforcement on parent methods, interface methods, abstract methods

// --- valid: parent method ---
class Base {
    public function greet(): string { return 'hello'; }
}

class Child extends Base {
    #[Override]
    public function greet(): string { return 'hi'; }
}

$c = new Child();
echo $c->greet() . "\n";

// --- valid: interface method ---
interface Loggable {
    public function log(): void;
}

class Logger implements Loggable {
    #[Override]
    public function log(): void { echo "logged\n"; }
}

$l = new Logger();
$l->log();

// --- valid: grandparent method ---
class GrandChild extends Child {
    #[Override]
    public function greet(): string { return 'hey'; }
}

$gc = new GrandChild();
echo $gc->greet() . "\n";

// --- valid: abstract parent method ---
abstract class AbstractBase {
    abstract public function render(): string;
}

class Concrete extends AbstractBase {
    #[Override]
    public function render(): string { return 'rendered'; }
}

$r = new Concrete();
echo $r->render() . "\n";

// --- valid: interface from parent ---
interface Printable {
    public function print(): void;
}

abstract class PrintBase implements Printable {}

class Printer extends PrintBase {
    #[Override]
    public function print(): void { echo "printed\n"; }
}

$p = new Printer();
$p->print();
