<?php
// Randomizer::getFloat() draws by php's gamma-section algorithm: a seeded
// engine gives php's floats for each Random\IntervalBoundary
use Random\IntervalBoundary;
use Random\Randomizer;
use Random\Engine\Xoshiro256StarStar;

var_dump(IntervalBoundary::cases());
foreach (IntervalBoundary::cases() as $boundary) {
    $r = new Randomizer(new Xoshiro256StarStar(42));
    echo $boundary->name, ":";
    foreach ([[0.0, 1.0], [-5.5, 2.25], [1e10, 1e10 + 1], [-1e-300, -1e-301]] as [$min, $max]) {
        for ($i = 0; $i < 3; $i++) printf(" %.17g", $r->getFloat($min, $max, $boundary));
    }
    echo "\n";
}

$r = new Randomizer(new Xoshiro256StarStar(7));
printf("%.17g\n", $r->getFloat(1.0, 2.0));
foreach ([[INF, 1.0], [0.0, NAN], [2.0, 1.0], [1.0, 1.0]] as [$min, $max]) {
    try {
        var_dump($r->getFloat($min, $max));
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}
var_dump($r->getFloat(1.0, 1.0, IntervalBoundary::ClosedClosed));
try {
    $r->getFloat(1.0, nextafter_up(1.0), IntervalBoundary::OpenOpen);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}

function nextafter_up(float $x): float {
    return unpack('d', pack('q', unpack('q', pack('d', $x))[1] + 1))[1];
}
