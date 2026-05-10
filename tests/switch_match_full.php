<?php
function s1(int $n): string {
    switch ($n) {
        case 1: return "one";
        case 2: return "two";
        case 3: return "three";
        default: return "other";
    }
}
echo s1(1), " ", s1(2), " ", s1(99), "\n";

function s2(string $s): string {
    switch ($s) {
        case "a": return "A";
        case "b": return "B";
        default: return "?";
    }
}
echo s2("a"), " ", s2("b"), " ", s2("z"), "\n";

// fallthrough
function falls(int $n): string {
    $out = "";
    switch ($n) {
        case 1: $out .= "1";
        case 2: $out .= "2";
        case 3: $out .= "3"; break;
        case 4: $out .= "4"; break;
    }
    return $out;
}
echo falls(1), "\n"; // 123
echo falls(2), "\n"; // 23
echo falls(3), "\n"; // 3
echo falls(4), "\n"; // 4
echo falls(5), "\n"; // ""

// default in middle (executed only if nothing else matches)
function dmid(int $n): string {
    $out = "";
    switch ($n) {
        case 1: $out .= "1"; break;
        default: $out .= "d"; break;
        case 2: $out .= "2"; break;
    }
    return $out;
}
echo dmid(1), "\n"; // 1
echo dmid(2), "\n"; // 2
echo dmid(99), "\n"; // d

// default falls through
function dfall(int $n): string {
    $out = "";
    switch ($n) {
        case 1: $out .= "1"; break;
        default: $out .= "d";
        case 2: $out .= "2"; break;
    }
    return $out;
}
echo dfall(1), "\n"; // 1
echo dfall(2), "\n"; // 2
echo dfall(99), "\n"; // d2 (default falls through to next case)

// switch on string is case-sensitive
function strcase(string $s): string {
    switch ($s) {
        case "a": return "lower";
        case "A": return "upper";
        default: return "other";
    }
}
echo strcase("a"), " ", strcase("A"), " ", strcase("Z"), "\n";

// numeric/string juggling - PHP 8 == is loose for switch
function juggle($v): string {
    switch ($v) {
        case 0: return "zero";
        case "0": return "string-zero";
        default: return "other";
    }
}
echo juggle(0), "\n"; // zero
echo juggle("0"), "\n"; // zero (loose: 0 == "0")
echo juggle(1), "\n"; // other

// only match strings - need ===-like via if (PHP switch uses ==, not ===)
function abc($v): string {
    switch ($v) {
        case "abc": return "abc";
        case 0: return "zero"; // "abc" == 0 is false in PHP 8
        default: return "?";
    }
}
echo abc("abc"), "\n";
echo abc(0), "\n";
echo abc("xyz"), "\n";

// nested
function nested(int $a, int $b): string {
    switch ($a) {
        case 1:
            switch ($b) {
                case 1: return "1-1";
                case 2: return "1-2";
            }
            return "1-?";
        case 2:
            return "2";
        default:
            return "?";
    }
}
echo nested(1, 1), " ", nested(1, 2), " ", nested(1, 99), " ", nested(2, 0), " ", nested(3, 0), "\n";

// switch in loop
function inloop(array $arr): string {
    $out = "";
    foreach ($arr as $v) {
        switch ($v) {
            case "skip": continue 2;
            case "stop": break 2;
            default: $out .= $v;
        }
    }
    return $out;
}
echo inloop(["a", "b", "skip", "c", "stop", "d"]), "\n"; // abc

// match expression (PHP 8 alternative to switch)
function m(int $n): string {
    return match ($n) {
        1, 2 => "low",
        3 => "mid",
        4, 5, 6 => "hi",
        default => "?",
    };
}
echo m(1), " ", m(2), " ", m(3), " ", m(5), " ", m(99), "\n";

// match strict equality
$r = match("1") {
    1 => "int",
    "1" => "str",
    default => "?",
};
echo $r, "\n";

// match no default - throws
try {
    $r = match(99) {
        1 => "a",
    };
    echo "no\n";
} catch (\UnhandledMatchError $e) {
    echo "ume\n";
}

// match on bool
$x = 7;
$r = match(true) {
    $x < 0 => "neg",
    $x === 0 => "z",
    $x <= 10 => "small",
    default => "big",
};
echo $r, "\n";

// switch on float
function f($v): string {
    switch ($v) {
        case 1.5: return "1.5";
        case 2.5: return "2.5";
        default: return "?";
    }
}
echo f(1.5), " ", f(2.5), " ", f(3), "\n";

// switch with multiple cases (no fallthrough since each has body)
function multi(int $n): string {
    switch ($n) {
        case 1:
        case 2:
        case 3:
            return "1-3";
        case 4:
        case 5:
            return "4-5";
        default:
            return "?";
    }
}
echo multi(1), " ", multi(2), " ", multi(3), " ", multi(4), " ", multi(5), " ", multi(99), "\n";

// continue inside switch in loop (PHP behavior - continue 1 = continue switch = act like break)
function looper(array $a): string {
    $out = "";
    foreach ($a as $v) {
        switch ($v) {
            case 1:
                $out .= "1";
                continue 2; // jump to next foreach iter
            case 2:
                $out .= "2";
                break;
        }
        $out .= "+";
    }
    return $out;
}
echo looper([1, 2, 3]), "\n"; // 12++

// alt syntax: switch ... endswitch
function alt(int $n): string {
    $out = "";
    switch ($n):
        case 1: $out = "one"; break;
        case 2: $out = "two"; break;
        default: $out = "other";
    endswitch;
    return $out;
}
echo alt(1), " ", alt(2), " ", alt(99), "\n";
