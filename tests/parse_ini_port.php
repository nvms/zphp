<?php
// parse_ini_string as php's ini scanner and parser read it, in each scanner
// mode, with php's syntax error warnings
error_reporting(E_ALL);
set_error_handler(function ($no, $msg) {
    echo "  [$no] ", rtrim(str_replace($GLOBALS["file"] ?? "\0", "FILE", $msg)), "\n";
    return true;
});
define('MY_CONST', 'const value');
putenv('ZPHP_INI_TEST=from env');

$ini = <<<'INI'
; comment
[first]
plain = hello world
quoted = "a \"b\" c \\ \$x ${ZPHP_INI_TEST}"
single = 'raw $x ${y}'
number = 42
float = 1.5e3
negative = -7
yes = yes
off = Off
none = none
null = NULL
trueish = TRUE
const = MY_CONST
const_concat = MY_CONST" and "MY_CONST
colon = a:b
math = 1 | 4
bits = 7 & ~2
not = !0
paren = (1 | 2) ^ 1
env = ${ZPHP_INI_TEST}
fallback = ${UNDEFINED_ZPHP_VAR:-fallback value}
fallback_true = ${UNDEFINED_ZPHP_VAR:-true}
empty =
spaces =    padded   ; trailing comment
dollar = cost $5 and $$
arr[] = one
arr[] = two
arr[key] = three
arr[7] = four
5[x] = numeric section key
[second section]
123 = numeric key
08 = leading zero key
"quoted key" = q
with.dot = d
path = "C:\path\"
multi = "line one
line two"
[ third ]
x = 1
INI;

foreach ([INI_SCANNER_NORMAL, INI_SCANNER_RAW, INI_SCANNER_TYPED] as $mode) {
    echo "mode $mode\n";
    var_dump(parse_ini_string($ini, true, $mode));
    var_dump(parse_ini_string($ini, false, $mode));
}

$bad = [
    "a = b = c", "x[ = 1", "=x", "a = \${", "a = \${x", "a = \${:-x}", "a = \"unterminated", "[sec", "a = (1",
    "a = 1 |", "\xef\xbb\xbfbom = yes", "nul = a\0b", "x = 1\n\n[s]\ny = )", "a = \${x:-}", "}",
];
foreach ($bad as $s) {
    echo json_encode($s), "\n";
    var_dump(parse_ini_string($s));
}
var_dump(parse_ini_string("a = 1", false, 5));

$file = tempnam(sys_get_temp_dir(), 'ini');
file_put_contents($file, "[s]\nk = v\nbad = = x\n");
var_dump(str_replace($file, 'FILE', var_export(parse_ini_file($file, true), true)));
file_put_contents($file, "[s]\nk = v\nlist[] = 1\n");
var_dump(parse_ini_file($file, true, INI_SCANNER_TYPED));
unlink($file);
