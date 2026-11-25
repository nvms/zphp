<?php
// gmp's integer strings (convert_zstr_to_gmp): a NUL byte or anything gmp
// can't read is a ValueError naming the argument, leading whitespace is
// skipped, 0x, 0o and 0b prefixes pick the base, and a base outside 2..62
// is refused
$cases = [
    fn() => gmp_init("1\0"),
    fn() => gmp_init("12\0", 10),
    fn() => gmp_init(""),
    fn() => gmp_init(" 42"),
    fn() => gmp_init("0o17"),
    fn() => gmp_init("0b101"),
    fn() => gmp_init("0x1f"),
    fn() => gmp_init("ff", 16),
    fn() => gmp_init("0xff", 16),
    fn() => gmp_init("12", 1),
    fn() => gmp_init("12", 63),
    fn() => new GMP("1\0"),
    fn() => new GMP("zz", 36),
    fn() => new GMP("5", 99),
    fn() => gmp_add("1\0", 1),
    fn() => gmp_add("x", 1),
    fn() => gmp_sub(1, "y"),
    fn() => gmp_cmp(1, "\0"),
    fn() => gmp_strval("5\0"),
    fn() => gmp_intval(" 0o10"),
    fn() => gmp_div("7", "x"),
    fn() => gmp_neg("--1"),
    fn() => gmp_sign("abc"),
    fn() => gmp_hamdist(1, "q"),
    fn() => gmp_jacobi("q", 3),
    fn() => gmp_init(5) + "1\0",
    fn() => gmp_init(5) * " 3",
];
foreach ($cases as $i => $case) {
    try {
        $r = $case();
        echo $i, ": ", is_object($r) ? gmp_strval($r) : var_export($r, true), "\n";
    } catch (\Throwable $t) {
        echo $i, ": ", get_class($t), ": ", $t->getMessage(), "\n";
    }
}
// a fractional float converts with php's deprecation
set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });
echo gmp_strval(gmp_add(1.5, 1)), "\n";
echo gmp_strval(gmp_init(2) * 2.5), "\n";
echo gmp_strval(gmp_init(2) << 1.5), "\n";
