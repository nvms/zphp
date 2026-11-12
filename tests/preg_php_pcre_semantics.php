<?php
// the preg functions as php_pcre.c runs them: regex parsing and its
// warnings, empty matches, backreferences in replacements, flags, limits
// and the errors left for preg_last_error
function show(...$v) {
    foreach ($v as $x) var_export($x);
    echo " | ", preg_last_error(), " ", preg_last_error_msg(), "\n";
}
foreach (['', '   ', 'abc', '\\x\\', "\0x\0", '/abc', '(abc', '{a{b}c', '[a]b]', '/a/F', "/a/\0", '/a/e', '/a/ i', "/a/\ni", '/a(/', '/(?<=\Kx)/', '/(?<1a>x)/', '#a#n', '/a{,2}/'] as $re) {
    echo json_encode($re), ": ";
    show(@preg_match($re, 'aaa'));
    $m = preg_match($re, 'a{,2}', $mm);
}
// empty matches are retried in place before moving on
show(preg_match_all('/a*/', 'baaac', $m), $m);
show(preg_match_all('/(?=a)|a/', 'aa', $m, PREG_OFFSET_CAPTURE), $m);
show(preg_replace('/a*/', '-', 'baaac'));
show(preg_replace('/\b/u', '|', 'héllo wörld'));
show(preg_split('//', 'abc'), preg_split('//u', 'äbc', -1, PREG_SPLIT_NO_EMPTY));
show(preg_split('/(-)|x/', 'a-bxc', -1, PREG_SPLIT_DELIM_CAPTURE | PREG_SPLIT_OFFSET_CAPTURE));
show(preg_split('/,/', 'a,b,c,d', 2), preg_split('/,/', 'a,b,c', -5), preg_split('/,/', 'a,b,c', 0), preg_split('/,/', ',a,,b,', -1, PREG_SPLIT_NO_EMPTY));
show(preg_split('/(\d)?,/', 'a,b1,c', -1, PREG_SPLIT_DELIM_CAPTURE));
// replacements
show(preg_replace('/(a)(b)?/', '[\1|$2|${1}x|$10|\\\\1|\$1|\0|${3}]', 'ac ab'));
show(preg_replace('/(.)/', '$1$', 'xy'), preg_replace('/x/', '\\', 'axb'), preg_replace('/x/', '${1', 'axb'));
show(preg_replace(['/a/', '/b/', '/c/'], ['b', 'c'], 'abc'), preg_replace(['/a/', '/b/'], 'z', ['k1' => 'ab', 5 => 'xy', 'ba']));
show(preg_filter(['/\d/', '/[a-z]/'], ['#', '@'], ['1', 'a', '#', 'x2']), preg_filter('/\d/', '#', 'abc'), preg_filter('/\d/', '#', 'a1'));
show(preg_replace('/a/', 'b', 'aaaa', 2, $count), $count, preg_replace('/a/', 'b', 'aaaa', 0, $count), $count);
show(preg_replace('/(x)/', 'y', ['x', 'xx', 3, 1.5, null, true]));
try { preg_replace('/a/', ['b'], 'a'); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { preg_replace('/a/', 'b', new stdClass); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
// callbacks get php's match arrays
show(preg_replace_callback('/(?<w>\w)(\d)?/', fn($m) => json_encode($m), 'a1 b', -1, $c, PREG_OFFSET_CAPTURE | PREG_UNMATCHED_AS_NULL), $c);
show(preg_replace_callback('/x/', fn($m) => [1], 'axb'));
show(preg_replace_callback(['/a/', '/b/'], fn($m) => strtoupper($m[0]), ['ab', 'k' => 'ba']));
show(preg_replace_callback_array(['/a/' => fn($m) => 'b', '/b/' => fn($m) => 'c'], 'ab', -1, $c), $c);
foreach ([[1 => 'strtoupper'], ['/a/' => 'not a function'], ['/a' => 'strtoupper']] as $map) {
    try { show(preg_replace_callback_array($map, 'a')); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
}
// match arrays: names, duplicate names, unmatched groups, marks
show(preg_match('/(?<a>x)|(?<b>y)/', 'y', $m), $m);
show(preg_match('/(?<a>x)|(?<b>y)/', 'y', $m, PREG_UNMATCHED_AS_NULL), $m);
show(preg_match('/(?J)(?<n>x)|(?<n>y)/', 'y', $m), $m);
show(preg_match('/(a)(b)?(c)?/', 'a', $m, PREG_OFFSET_CAPTURE), $m);
show(preg_match_all('/(a)(b)?/', 'a ab', $m), $m);
show(preg_match_all('/(?<l>a)(b)?/', 'a ab', $m, PREG_SET_ORDER | PREG_UNMATCHED_AS_NULL), $m);
show(preg_match_all('/(*MARK:A)a|(*MARK:B)b/', 'ab', $m), $m);
show(preg_match('/(*MARK:Z)z/', 'z', $m), $m);
// offsets and flags
show(preg_match('/b/', 'abc', $m, 0, -2), preg_match('/a/', 'abc', $m, 0, -10), preg_match('/a/', 'abc', $m, 0, 4), $m);
foreach ([3, 0x100 | 3] as $f) { try { preg_match('/a/', 'a', $m, $f); } catch (ValueError $e) { echo $e->getMessage(), "\n"; } }
try { preg_match_all('/a/', 'a', $m, 3); } catch (ValueError $e) { echo $e->getMessage(), "\n"; }
show(preg_match('/./u', "\xff"), preg_match('/./u', "aé", $m, 0, 2), preg_match_all('/./u', "\xc3"));
// grep, quote
show(preg_grep('/^\d+$/', ['1', 'a', 'k' => '22', 3, 1.5]), preg_grep('/^\d+$/', ['1', 'a'], PREG_GREP_INVERT));
show(preg_quote("a.b*c?d+(e)[f]{g}=h!i<j>k|l:m-n#o/p\0q", '/'), preg_quote('x', ''), preg_quote(''));
ini_set('pcre.backtrack_limit', '10');
show(preg_match('/(a+)+b/', str_repeat('a', 30)));
show(preg_replace('/(a+)+b/', 'x', str_repeat('a', 30)), preg_split('/(a+)+b/', str_repeat('a', 30)));
