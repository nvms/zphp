<?php

// readonly class: all instance properties become readonly
readonly class Point {
    public function __construct(public int $x, public int $y) {}
}

$p = new Point(3, 4);
echo $p->x . "," . $p->y . "\n";
try { $p->x = 99; echo "wrote\n"; } catch (Error $e) { echo "blocked x\n"; }
try { $p->y = 99; echo "wrote\n"; } catch (Error $e) { echo "blocked y\n"; }

// non-promoted properties also become readonly
readonly class Config {
    public string $env;
    public int $port;
    public function __construct(string $env, int $port) {
        $this->env = $env;
        $this->port = $port;
    }
}

$c = new Config("prod", 8080);
echo $c->env . ":" . $c->port . "\n";
try { $c->env = "dev"; } catch (Error $e) { echo "blocked env\n"; }

// final readonly class
final readonly class Immutable {
    public function __construct(public string $tag) {}
}

$im = new Immutable("frozen");
echo $im->tag . "\n";
try { $im->tag = "thawed"; } catch (Error $e) { echo "blocked tag\n"; }
