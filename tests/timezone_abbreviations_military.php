<?php
// covers: timezone_abbreviations_list() returns the 25 single-letter military
// timezone abbreviations (RFC 822 / NATO), each with a fixed UTC offset, dst
// false, and a null timezone_id. these are defined by spec (not the tz
// database), so they're stable across PHP/tzdb versions and can be asserted
// exactly. 'j' (local) is intentionally absent.
//
// NOTE: zphp does not reproduce PHP's full multi-letter historical abbreviation
// lists byte-for-byte - that set is coupled to PHP's bundled timezonedb version
// and treated as implementation-defined. this test only pins the stable part.

$a = timezone_abbreviations_list();

$military = [
    'a' => 3600,  'b' => 7200,  'c' => 10800, 'd' => 14400, 'e' => 18000,
    'f' => 21600, 'g' => 25200, 'h' => 28800, 'i' => 32400, 'k' => 36000,
    'l' => 39600, 'm' => 43200, 'n' => -3600, 'o' => -7200, 'p' => -10800,
    'q' => -14400, 'r' => -18000, 's' => -21600, 't' => -25200, 'u' => -28800,
    'v' => -32400, 'w' => -36000, 'x' => -39600, 'y' => -43200, 'z' => 0,
];

foreach ($military as $letter => $offset) {
    if (!isset($a[$letter])) {
        echo "MISSING: $letter\n";
        continue;
    }
    $e = $a[$letter][0];
    $ok = $e['dst'] === false && $e['offset'] === $offset && $e['timezone_id'] === null;
    echo $letter, ': ', $ok ? 'ok' : ('WRONG ' . json_encode($e)), "\n";
}

// 'j' is not a military abbreviation in the list
echo "j present: ", isset($a['j']) ? 'yes' : 'no', "\n";

// keys are lowercase, values are non-empty lists of {dst, offset, timezone_id}
$shape_ok = true;
foreach ($a as $k => $entries) {
    if ($k !== strtolower($k) || !is_array($entries) || count($entries) === 0) { $shape_ok = false; break; }
    foreach ($entries as $e) {
        if (!array_key_exists('dst', $e) || !array_key_exists('offset', $e) || !array_key_exists('timezone_id', $e)) {
            $shape_ok = false; break 2;
        }
    }
}
echo "shape ok: ", $shape_ok ? 'yes' : 'no', "\n";
