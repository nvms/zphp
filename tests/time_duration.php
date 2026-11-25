<?php
// php 8.6's Time\Duration: the factories, arithmetic, comparison,
// readonly properties, serialization and the errors of each, after
// php-src's ext/date/tests/time/duration

function f(Time\Duration $d, bool $pad = true, bool $plus_sign = true): string {
    $result = sprintf("%s%d.%09d", ($d->negative ? "-" : ($plus_sign ? "+" : " ")), $d->seconds, $d->nanoseconds);
    if ($pad) {
        $result = str_pad($result, 21, pad_type: STR_PAD_LEFT);
    }

    return $result;
}

function as_int(Time\Duration $d): int {
    return ($d->negative ? -1 : 1) * ($d->seconds * 1_000_000_000 + $d->nanoseconds);
}

function negate(Time\Duration $d): Time\Duration {
    return $d->negate();
}

function is_negative(Time\Duration $d): bool {
    return $d->negative;
}

/** @return Time\Duration[] */
function negate_all(
    array $d /** @param Time\Duration[] */,
): array {
    $negated = array_map(negate(...), $d);

    /* Filter out values that were not successfully negated (i.e. 0-values). */
    return array_filter($negated, is_negative(...));
}

echo "--- output, comparison and the factory cache\n";
(function () {
$d = Time\Duration::fromSeconds(5, 123);
var_dump($d);
print_r($d); echo "\n";
var_export($d); echo "\n";
echo json_encode($d), "\n";
var_dump((array)$d);
var_dump(get_object_vars($d));
echo serialize($d), "\n";
$c = clone $d;
var_dump($c == $d, $c === $d, $c <=> $d);
var_dump(Time\Duration::fromSeconds(1) === Time\Duration::fromSeconds(1));
$a = Time\Duration::fromSeconds(1); $b = Time\Duration::fromSeconds(2); $a2 = Time\Duration::fromSeconds(1);
var_dump($a === $a2, spl_object_id($a), spl_object_id($a2));
var_dump($a < $b, $a->negate() < $b->negate(), $a == $a->negate());
var_dump(Time\Duration::fromSeconds(3)->absolute() === Time\Duration::fromSeconds(3));
$x = Time\Duration::fromSeconds(9);
var_dump($x->absolute() === $x, $x->add(Time\Duration::fromSeconds(0)) === $x);
try { $d->foo = 1; } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { unset($d->seconds); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
var_dump(isset($d->seconds), $d->seconds);
try { var_dump(Time\Duration::fromSeconds(1) + 1); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { var_dump(Time\Duration::fromHours(PHP_INT_MAX)); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { var_dump(Time\Duration::fromSeconds(PHP_INT_MAX)); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { var_dump(Time\Duration::fromSeconds(9223372035, 999999999)->multiplyBy(PHP_INT_MAX)); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { var_dump(Time\Duration::fromSeconds("x")); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { var_dump(Time\Duration::fromSeconds()); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { echo f(Time\Duration::fromIso8601DurationString("PT1H")->sub(Time\Duration::fromSeconds(7200))), "\n"; } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
foreach ([Time\Duration::fromNanoseconds(1500000001), Time\Duration::fromMilliseconds(1500), Time\Duration::fromMicroseconds(1500001), Time\Duration::fromMinutes(2)] as $v) echo f($v), "\n";
foreach (['P0D','PT1H30M','PT36H','P1Y','PT-1S','pt1s','PT1S ', ' PT1S', 'P1DT1H', 'PT1,5S', 'P0Y0M0DT1S','P0W','PT0000S','PT1H0.5M','R2/PT1S','PT9999999999S','P2Y10M15DT10H30M20S','PTS','PT1H1H', 'P0000-00-00T01:00:00', 'P0Y', 'PT1M1H', 'PT99999999999999999999S'] as $s) {
  try { $r = Time\Duration::fromIso8601DurationString($s); echo "$s: {$r->seconds}.{$r->nanoseconds}\n"; } catch (Throwable $e) { echo "$s: ", get_class($e), ": ", $e->getMessage(), "\n"; }
}
var_dump(Time\Duration::compare($a, $b), Time\Duration::compare($b, $a), Time\Duration::compare($a, $a2));
var_dump($d instanceof Stringable);
var_dump($a == 1);
var_dump($a == new stdClass);
})();

echo "--- clone\n";
(function () {
function fc(Time\Duration $d): string {
	return f(clone($d));
}

echo fc(Time\Duration::fromSeconds(0, 0)), PHP_EOL;
echo fc(Time\Duration::fromSeconds(0, 1)), PHP_EOL;
echo fc(Time\Duration::fromSeconds(1, 1)), PHP_EOL;
echo fc(Time\Duration::fromSeconds(0, 1)->negate()), PHP_EOL;
echo fc(Time\Duration::fromSeconds(1, 1)->negate()), PHP_EOL;
})();

echo "--- compare\n";
(function () {
$durations = [
    Time\Duration::fromSeconds(0, 0),
    Time\Duration::fromSeconds(0, 1),
    Time\Duration::fromSeconds(0, 2),
    Time\Duration::fromSeconds(1, 0),
    Time\Duration::fromSeconds(1, 1),
    Time\Duration::fromSeconds(1, 2),
    Time\Duration::fromSeconds(2, 0),
    Time\Duration::fromSeconds(2, 1),
    Time\Duration::fromSeconds(2, 2),
];

function n(int $result) {
    return ($result === 0 ? '=' : ($result < 0 ? '<' : '>'));
}

$durations = [
    ...$durations,
    null,
    ...negate_all($durations),
];

foreach ($durations as $a) {
    if ($a === null) {
        continue;
    }

    foreach ($durations as $b) {
        if ($b === null) {
            continue;
        }

        if (n($a <=> $b) !== n(Time\Duration::compare($a, $b))) {
            echo sprintf('%1$s <=> %2$s !== Duration::compare(%1$s, %2$s)', f($a, pad: false), f($b, pad: false)), PHP_EOL;
        }
    }
}
})();

echo "--- gh23639\n";
(function () {
class Time_Duration {
    public int $seconds;
    public int $nanoseconds;
    public bool $negative;
}

$d = new Time_Duration();
$d->seconds = 1;
$a = [$d, &$d->seconds];

$payload = serialize($a);

try {
    unserialize(str_replace('Time_Duration', 'Time\\Duration', $payload));
} catch (Throwable $e) {
    do {
        echo $e::class, ": ", $e->getMessage(), "\n";
    } while ($e = $e->getPrevious());
}
})();

echo "--- new\n";
(function () {
try {
    new Time\Duration();
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

try {
    (new ReflectionClass(Time\Duration::class))->newInstance();
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

try {
    (new ReflectionClass(Time\Duration::class))->newInstanceWithoutConstructor();
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- oss_fuzz_562721806\n";
(function () {
try {
    unserialize('O:13:"Time\Duration"::{}');
} catch (Throwable $e) {
    echo $e::class, ": ", $e->getMessage(), "\n";
}
})();

echo "--- readonly\n";
(function () {
$d = Time\Duration::fromSeconds(1);

try {
    $d->seconds = 2;
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

echo f($d), PHP_EOL;

try {
    (new ReflectionProperty($d, 'seconds'))->setValue($d, 2);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

echo f($d), PHP_EOL;

try {
    (new ReflectionProperty($d, 'seconds'))->setRawValue($d, 2);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

echo f($d), PHP_EOL;

try {
    (new ReflectionProperty($d, 'seconds'))->setRawValueWithoutLazyInitialization($d, 2);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

echo f($d), PHP_EOL;

echo "====", PHP_EOL;

/* Recheck after cloning to verify that "modification allowed during cloning" has no lasting effect. */

$d = clone($d);

try {
    $d->seconds = 2;
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

echo f($d), PHP_EOL;

try {
    (new ReflectionProperty($d, 'seconds'))->setValue($d, 2);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

echo f($d), PHP_EOL;

try {
    (new ReflectionProperty($d, 'seconds'))->setRawValue($d, 2);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

echo f($d), PHP_EOL;

try {
    (new ReflectionProperty($d, 'seconds'))->setRawValueWithoutLazyInitialization($d, 2);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

echo f($d), PHP_EOL;

echo "====", PHP_EOL;

try {
    clone($d, ['seconds' => 2]);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

echo "====", PHP_EOL;

var_dump((new ReflectionProperty($d, 'seconds'))->isWritable(null, $d));

echo "====", PHP_EOL;

try {
    (new ReflectionMethod($d, '__construct'))->invoke($d);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

echo f($d), PHP_EOL;
})();

echo "--- serialize\n";
(function () {
var_dump($serialized = serialize(Time\Duration::fromSeconds(1, 2)->negate()));
echo f($unserialized = unserialize($serialized)), PHP_EOL;
var_dump(serialize($unserialized));
echo f($unserialized->add($unserialized)), PHP_EOL;

try {
    // $negative is not bool, but coercible.
    echo f(unserialize('O:13:"Time\Duration":3:{s:7:"seconds";i:1;s:11:"nanoseconds";i:1;s:8:"negative";i:999;}')), PHP_EOL;
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

try {
    // $negative is not bool and not coercible.
    unserialize('O:13:"Time\Duration":3:{s:7:"seconds";i:1;s:11:"nanoseconds";i:1;s:8:"negative";N;}');
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

try {
    // $seconds is negative.
    unserialize('O:13:"Time\Duration":3:{s:7:"seconds";i:-1;s:11:"nanoseconds";i:1;s:8:"negative";b:0;}');
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

try {
    // Dynamic property.
    unserialize('O:13:"Time\Duration":4:{s:7:"seconds";i:1;s:11:"nanoseconds";i:1;s:8:"negative";b:0;s:3:"foo";N;}');
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}


try {
    // Out of range nanoseconds
    unserialize('O:13:"Time\Duration":3:{s:7:"seconds";i:1;s:11:"nanoseconds";i:1000000000;s:8:"negative";b:0;}');
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

try {
    // Nanoseconds that would be truncated to a valid value by a 32-bit conversion (2^32 + 5).
    unserialize('O:13:"Time\Duration":3:{s:7:"seconds";i:1;s:11:"nanoseconds";i:4294967301;s:8:"negative";b:0;}');
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

try {
    // A negative zero duration is rejected.
    unserialize('O:13:"Time\Duration":3:{s:7:"seconds";i:0;s:11:"nanoseconds";i:0;s:8:"negative";b:1;}');
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

try {
    Time\Duration::fromSeconds(1, 1)
        ->__unserialize([
            'seconds' => 2,
            'nanoseconds' => 2,
            'negative' => true,
        ]);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- z_param_date_time_duration\n";
(function () {
try {
    Time\Duration::compare(1, 2);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/absolute\n";
(function () {
echo f(Time\Duration::fromSeconds(0, 0)->absolute()), PHP_EOL;
echo f(Time\Duration::fromSeconds(0, 0)->negate()->absolute()), PHP_EOL;

echo f(Time\Duration::fromSeconds(1, 0)->absolute()), PHP_EOL;
echo f(Time\Duration::fromSeconds(1, 0)->negate()->absolute()), PHP_EOL;

echo f(Time\Duration::fromSeconds(0, 1)->absolute()), PHP_EOL;
echo f(Time\Duration::fromSeconds(0, 1)->negate()->absolute()), PHP_EOL;

echo f(Time\Duration::fromSeconds(1, 1)->absolute()), PHP_EOL;
echo f(Time\Duration::fromSeconds(1, 1)->negate()->absolute()), PHP_EOL;
})();

echo "--- methods/add\n";
(function () {
$durations = [
    Time\Duration::fromSeconds(0, 0),
    Time\Duration::fromSeconds(0, 1),
    Time\Duration::fromSeconds(0, 2),
    Time\Duration::fromSeconds(1, 0),
    Time\Duration::fromSeconds(1, 1),
    Time\Duration::fromSeconds(1, 2),
    Time\Duration::fromSeconds(2, 0),
    Time\Duration::fromSeconds(2, 1),
    Time\Duration::fromSeconds(2, 2),
];

$durations = [
    ...$durations,
    null,
    ...negate_all($durations),
];

foreach ($durations as $a) {
    if ($a === null) {
        continue;
    }

    echo "========", PHP_EOL;

    foreach ($durations as $b) {
        if ($b === null) {
            echo "====", PHP_EOL;
            continue;
        }

        $result = $a->add($b);
        echo f($a, pad: false, plus_sign: false), " + ", f($b, pad: false, plus_sign: false), " = ", f($result, pad: false), PHP_EOL;
        if (PHP_INT_SIZE != 4 && (as_int($a) + as_int($b) !== as_int($result))) {
            throw new \Exception('Verification failed');
        }
    }
}
})();

echo "--- methods/add_64\n";
(function () {
$a = Time\Duration::fromSeconds(9_223_372_035, 999999999);
$b = Time\Duration::fromSeconds(0, 1);

try {
    $a->add($b);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/compare\n";
(function () {
$durations = [
    Time\Duration::fromSeconds(0, 0),
    Time\Duration::fromSeconds(0, 1),
    Time\Duration::fromSeconds(0, 2),
    Time\Duration::fromSeconds(1, 0),
    Time\Duration::fromSeconds(1, 1),
    Time\Duration::fromSeconds(1, 2),
    Time\Duration::fromSeconds(2, 0),
    Time\Duration::fromSeconds(2, 1),
    Time\Duration::fromSeconds(2, 2),
];

$durations = [
    ...$durations,
    null,
    ...negate_all($durations),
];

foreach ($durations as $a) {
    if ($a === null) {
        continue;
    }

    echo "========", PHP_EOL;

    foreach ($durations as $b) {
        if ($b === null) {
            echo "====", PHP_EOL;
            continue;
        }

        $result = Time\Duration::compare($a, $b);

        echo f($a, pad: false), " ", ($result === 0 ? '=' : ($result < 0 ? '<' : '>')), " ", f($b, pad: false), PHP_EOL;
    }
}
})();

echo "--- methods/divideBy\n";
(function () {
$durations = [
    Time\Duration::fromSeconds(0, 0),
    Time\Duration::fromSeconds(0, 1),
    Time\Duration::fromSeconds(0, 999999999),
    Time\Duration::fromSeconds(1, 0),
    Time\Duration::fromSeconds(2_147_483_647, 999999999),
];

$durations = [
    ...$durations,
    null,
    ...negate_all($durations),
];

$divisors = [
    1,
    2,
    3,
    4,
    999999999,
    1_000000000,
    2_147483647,
];

foreach ($durations as $d) {
    if ($d === null) {
        continue;
    }

    echo "========", PHP_EOL;

    foreach ($divisors as $divisor) {
        $result = $d->divideBy($divisor);
        echo f($d), " / ", sprintf("%10d", $divisor), " = ", f($result), PHP_EOL;

        if (PHP_INT_SIZE != 4 && (intdiv(as_int($d), $divisor) !== as_int($result))) {
            throw new \Exception('Verification failed');
        }
    }
}

echo "========", PHP_EOL;

$d = Time\Duration::fromSeconds(1, 0);
try {
    $d->divideBy(0);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/divideBy_64\n";
(function () {
$durations = [
    Time\Duration::fromSeconds(2_147_483_648, 0),
    Time\Duration::fromSeconds(9_223_372_035, 999999999),
];

$durations = [
    ...$durations,
    null,
    ...negate_all($durations),
];

$divisors = [
    1,
    2,
    3,
    4,
    999999999,
    1_000000000,
    9_223_372_035_999999999,
];

foreach ($durations as $d) {
    if ($d === null) {
        continue;
    }

    echo "========", PHP_EOL;

    foreach ($divisors as $factor) {
        echo f($d), " / ", sprintf("%19d", $factor), " = ", f($d->divideBy($factor)), PHP_EOL;
    }
}
})();

echo "--- methods/fromHours\n";
(function () {
echo f(Time\Duration::fromHours(0)), PHP_EOL;
echo f(Time\Duration::fromHours(1)), PHP_EOL;
echo f(Time\Duration::fromHours(596523)), PHP_EOL;

try {
    Time\Duration::fromHours(-1);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/fromHours_64\n";
(function () {
echo f(Time\Duration::fromHours(2562047)), PHP_EOL;

try {
    Time\Duration::fromHours(2562048);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/fromIso8601DurationString\n";
(function () {
$specifications = [
    'PT0S',
    'PT1S',
    'PT60S',
    'PT2147483647S',

    'PT0.1S',

    'PT0M',
    'PT1M',
    'PT1M1S',
    'PT1M60S',

    'PT0H',
    'PT1H',
    'PT1H1M',
    'PT1H1M1S',
    'PT1H60M',
    'PT1H60M60S',

    '',
    'P',
    'PT',
    'P1D',
    'P1W',
    'P1M',
    'P1DT0S',
    '2000-01-01T00:00:00Z',
    '2000-01-01T00:00:00Z/PT1H',

    "PT5S\0garbage",
    "PT5S\0",
    "\0PT5S",
];

foreach ($specifications as $specification) {
    printf("%-25s: ", addcslashes($specification, "\0"));

    try {
        echo f(Time\Duration::fromIso8601DurationString($specification)), PHP_EOL;
    } catch (Throwable $e) {
        echo $e::class, ': ', $e->getMessage(), PHP_EOL;
    }
}
})();

echo "--- methods/fromIso8601DurationString_64\n";
(function () {
$specifications = [
    'PT2147483648S',
    'PT9223372035S',
    'PT9223372036S',
];

foreach ($specifications as $specification) {
    printf("%-25s: ", $specification);

    try {
        echo f(Time\Duration::fromIso8601DurationString($specification)), PHP_EOL;
    } catch (Throwable $e) {
        echo $e::class, ': ', $e->getMessage(), PHP_EOL;
    }
}
})();

echo "--- methods/fromMicroseconds\n";
(function () {
echo f(Time\Duration::fromMicroseconds(0)), PHP_EOL;
echo f(Time\Duration::fromMicroseconds(1)), PHP_EOL;
echo f(Time\Duration::fromMicroseconds(999999)), PHP_EOL;
echo f(Time\Duration::fromMicroseconds(1_000000)), PHP_EOL;
echo f(Time\Duration::fromMicroseconds(2147_483647)), PHP_EOL;

try {
    Time\Duration::fromMicroseconds(-1);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/fromMicroseconds_64\n";
(function () {
echo f(Time\Duration::fromMicroseconds(9_223_372_035_999999)), PHP_EOL;

try {
    Time\Duration::fromMicroseconds(9_223_372_036_000000);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/fromMilliseconds\n";
(function () {
echo f(Time\Duration::fromMilliseconds(0)), PHP_EOL;
echo f(Time\Duration::fromMilliseconds(1)), PHP_EOL;
echo f(Time\Duration::fromMilliseconds(999)), PHP_EOL;
echo f(Time\Duration::fromMilliseconds(1_000)), PHP_EOL;
echo f(Time\Duration::fromMilliseconds(2147483_647)), PHP_EOL;

try {
    Time\Duration::fromMilliseconds(-1);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/fromMilliseconds_64\n";
(function () {
echo f(Time\Duration::fromMilliseconds(9_223_372_035_999)), PHP_EOL;

try {
    Time\Duration::fromMilliseconds(9_223_372_036_000);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/fromMinutes\n";
(function () {
echo f(Time\Duration::fromMinutes(0)), PHP_EOL;
echo f(Time\Duration::fromMinutes(1)), PHP_EOL;
echo f(Time\Duration::fromMinutes(35791394)), PHP_EOL;

try {
    Time\Duration::fromMinutes(-1);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/fromMinutes_64\n";
(function () {
echo f(Time\Duration::fromMinutes(153722867)), PHP_EOL;

try {
    Time\Duration::fromMinutes(153722868);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/fromNanoseconds\n";
(function () {
echo f(Time\Duration::fromNanoseconds(0)), PHP_EOL;
echo f(Time\Duration::fromNanoseconds(1)), PHP_EOL;
echo f(Time\Duration::fromNanoseconds(999999999)), PHP_EOL;
echo f(Time\Duration::fromNanoseconds(1_000000000)), PHP_EOL;
echo f(Time\Duration::fromNanoseconds(2_147483647)), PHP_EOL;

try {
    Time\Duration::fromNanoseconds(-1);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/fromNanoseconds_64\n";
(function () {
echo f(Time\Duration::fromNanoseconds(9_223_372_035_999999999)), PHP_EOL;

try {
    Time\Duration::fromNanoseconds(9_223_372_036_000000000);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/fromSeconds\n";
(function () {
echo f(Time\Duration::fromSeconds(0)), PHP_EOL;
echo f(Time\Duration::fromSeconds(1)), PHP_EOL;
echo f(Time\Duration::fromSeconds(2147483647)), PHP_EOL;

echo f(Time\Duration::fromSeconds(0, 0)), PHP_EOL;
echo f(Time\Duration::fromSeconds(0, 1)), PHP_EOL;
echo f(Time\Duration::fromSeconds(1, 1)), PHP_EOL;
echo f(Time\Duration::fromSeconds(2147483647, 999999999)), PHP_EOL;

try {
    Time\Duration::fromSeconds(-1);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

try {
    Time\Duration::fromSeconds(0, -1);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

try {
    Time\Duration::fromSeconds(0, 1000000000);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/fromSeconds_64\n";
(function () {
echo f(Time\Duration::fromSeconds(9_223_372_035)), PHP_EOL;
echo f(Time\Duration::fromSeconds(9_223_372_035, 999999999)), PHP_EOL;

try {
    Time\Duration::fromSeconds(9_223_372_036);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/multiplyBy\n";
(function () {
$durations = [
    Time\Duration::fromSeconds(0, 0),
    Time\Duration::fromSeconds(0, 1),
    Time\Duration::fromSeconds(0, 2),
    Time\Duration::fromSeconds(1, 0),
    Time\Duration::fromSeconds(1, 1),
    Time\Duration::fromSeconds(1, 2),
    Time\Duration::fromSeconds(2, 0),
    Time\Duration::fromSeconds(2, 1),
    Time\Duration::fromSeconds(2, 2),
];

$durations = [
    ...$durations,
    null,
    ...negate_all($durations),
];

$factors = [
    0,
    1,
    2,
    3,
    4,
    999999999,
    1_000000000,
];

foreach ($durations as $d) {
    if ($d === null) {
        continue;
    }

    echo "========", PHP_EOL;

    foreach ($factors as $factor) {
        $result = $d->multiplyBy($factor);
        echo f($d), " * ", sprintf("%10d", $factor), " = ", f($result), PHP_EOL;

        if (PHP_INT_SIZE != 4 && (as_int($d) * $factor !== as_int($result))) {
            throw new \Exception('Verification failed');
        }
    }
}

echo "========", PHP_EOL;
$d = Time\Duration::fromSeconds(0, 1);
$factor = 2_147_483_647;
$result = $d->multiplyBy($factor);
echo f($d), " * ", sprintf("%10d", $factor), " = ", f($result), PHP_EOL;

echo "========", PHP_EOL;
$d = Time\Duration::fromSeconds(1, 0);
$factor = 2_147_483_647;
$result = $d->multiplyBy($factor);
echo f($d), " * ", sprintf("%10d", $factor), " = ", f($result), PHP_EOL;
})();

echo "--- methods/multiplyBy_64\n";
(function () {
$d = Time\Duration::fromSeconds(9_223_372_035, 999999999);

echo f($d->multiplyBy(1)), PHP_EOL;

try {
    $d->multiplyBy(2);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

echo "====", PHP_EOL;

$d = Time\Duration::fromSeconds(4_611_686_017, 999999999);

echo f($d->multiplyBy(2)), PHP_EOL;

try {
    $d->multiplyBy(3);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

echo "====", PHP_EOL;

$d = Time\Duration::fromSeconds(3_074_457_345, 333333333);

echo f($d->multiplyBy(3)), PHP_EOL;

try {
    $d->multiplyBy(4);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

echo "====", PHP_EOL;

$d = Time\Duration::fromSeconds(0, 1);

echo f($d->multiplyBy(9_223_372_035_999999999)), PHP_EOL;

try {
    $d->multiplyBy(9_223_372_036_000000000);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- methods/negate\n";
(function () {
echo f(Time\Duration::fromSeconds(0, 0)->negate()), PHP_EOL;
echo f(Time\Duration::fromSeconds(0, 0)->negate()->negate()), PHP_EOL;

echo f(Time\Duration::fromSeconds(1, 0)->negate()), PHP_EOL;
echo f(Time\Duration::fromSeconds(1, 0)->negate()->negate()), PHP_EOL;

echo f(Time\Duration::fromSeconds(0, 1)->negate()), PHP_EOL;
echo f(Time\Duration::fromSeconds(0, 1)->negate()->negate()), PHP_EOL;

echo f(Time\Duration::fromSeconds(1, 1)->negate()), PHP_EOL;
echo f(Time\Duration::fromSeconds(1, 1)->negate()->negate()), PHP_EOL;
})();

echo "--- methods/sub\n";
(function () {
$durations = [
    Time\Duration::fromSeconds(0, 0),
    Time\Duration::fromSeconds(0, 1),
    Time\Duration::fromSeconds(0, 2),
    Time\Duration::fromSeconds(1, 0),
    Time\Duration::fromSeconds(1, 1),
    Time\Duration::fromSeconds(1, 2),
    Time\Duration::fromSeconds(2, 0),
    Time\Duration::fromSeconds(2, 1),
    Time\Duration::fromSeconds(2, 2),
];

$durations = [
    ...$durations,
    null,
    ...negate_all($durations),
];

foreach ($durations as $a) {
    if ($a === null) {
        continue;
    }

    echo "========", PHP_EOL;

    foreach ($durations as $b) {
        if ($b === null) {
            echo "====", PHP_EOL;
            continue;
        }

        $result = $a->sub($b);
        echo f($a, pad: false, plus_sign: false), " - ", f($b, pad: false, plus_sign: false), " = ", f($result, pad: false), PHP_EOL;
        if (PHP_INT_SIZE != 4 && (as_int($a) - as_int($b) !== as_int($result))) {
            throw new \Exception('Verification failed');
        }
    }
}
})();

echo "--- methods/sub_64\n";
(function () {
$a = Time\Duration::fromSeconds(0, 1)->negate();
$b = Time\Duration::fromSeconds(9_223_372_035, 999999999);

try {
    $a->sub($b);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- reflection\n";
echo new ReflectionClass('Time\Duration');
echo new ReflectionClass('Time\TimeException');
$rc = new ReflectionClass('Time\Duration');
var_dump($rc->isFinal(), $rc->isReadOnly(), $rc->isCloneable(), $rc->isInstantiable(), $rc->getExtensionName());
foreach ($rc->getProperties() as $p) {
    var_dump($p->getName(), $p->isReadOnly(), $p->hasDefaultValue(), (string)$p->getType(), $p->isProtectedSet(), $p->getModifiers());
}
var_dump((new ReflectionExtension('date'))->getClassNames());
