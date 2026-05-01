<?php

// PHP 8.2+ allows constants in traits. Classes that use the trait
// inherit the constants.
trait HasFlags {
    const FLAG_A = 1;
    const FLAG_B = 2;
    const FLAG_C = 4;
    public function flags(): int {
        return self::FLAG_A | self::FLAG_B | self::FLAG_C;
    }
}

class Setup {
    use HasFlags;
}

echo Setup::FLAG_A . "\n";
echo Setup::FLAG_B . "\n";
echo Setup::FLAG_C . "\n";
echo (new Setup())->flags() . "\n";

// constants alongside other trait members
trait Stateful {
    const VERSION = '1.0';
    public string $name = 'default';
    public function describe(): string {
        return self::VERSION . ':' . $this->name;
    }
}

class Service {
    use Stateful;
}

echo Service::VERSION . "\n";
$s = new Service();
$s->name = 'svc';
echo $s->describe() . "\n";

// expression in const
trait HasColors {
    const RED = 0xFF0000;
    const GREEN = 0x00FF00;
    const BLUE = 0x0000FF;
}
class Palette { use HasColors; }
echo dechex(Palette::RED) . "\n";

// multiple traits with separate constants
trait A { const X = 'a'; }
trait B { const Y = 'b'; }
class Both { use A, B; }
echo Both::X . "/" . Both::Y . "\n";
