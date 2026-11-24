<?php
// an unserialize() made while loading an enum (its autoloader, or the
// constant expression behind a backed case) starts a table of its own:
// it runs its __unserialize() at once and doesn't shift the outer call's
// back references
class Init {
    public bool $ready = false;

    public function __unserialize(array $data): void {
        $this->ready = true;
    }
}

enum Backed: string {
    case Foo = Value::FOO;
    case Bar = 'bar';
}

spl_autoload_register(function ($class) {
    echo "autoload $class\n";
    var_dump(unserialize('O:4:"Init":0:{}')->ready);
    var_dump(unserialize('a:2:{i:0;i:5;i:1;R:2;}'));
    eval(match ($class) {
        'Pure' => 'enum Pure { case Foo; }',
        'Value' => 'class Value { const FOO = "foo"; }',
    });
});

foreach (['E:8:"Pure:Foo";', 'E:10:"Backed:Foo";'] as $enum) {
    $data = unserialize('a:3:{i:0;' . $enum . 'i:1;O:8:"stdClass":0:{}i:2;r:3;}');
    var_dump($data[0]);
    var_dump($data[1] === $data[2]);
}
var_dump(Backed::Foo->value, Backed::Bar->value);
