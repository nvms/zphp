<?php

// match with no default and no arm matched should throw UnhandledMatchError
try {
    $x = 99;
    $result = match($x) {
        1 => "one",
        2 => "two",
    };
    echo "no error: " . var_export($result, true) . "\n";
} catch (\UnhandledMatchError $e) {
    echo "caught unhandled match\n";
} catch (\Error $e) {
    echo "caught error: " . $e->getMessage() . "\n";
} catch (\Exception $e) {
    echo "caught exception: " . $e->getMessage() . "\n";
}

// match with default works fine
$y = 99;
echo match($y) {
    1 => "one",
    default => "other",
} . "\n";
