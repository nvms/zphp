<?php
// a dimension of a call's result passed by reference fetches into the
// result (FETCH_DIM_FUNC_ARG on the VAR): no notice for the call, and a
// string result refuses the offset
set_error_handler(function ($no, $msg) {
    echo "notice: $msg\n";
    return true;
});
function byRef(&$a) { $a = 'changed'; }
eval('function lateByRef(&$a) { $a = "changed"; }');
function values() { return ['one', 'two']; }
class Maker {
    public function make() { return ['m' => 1]; }
    public static function build() { return "built"; }
}

byRef(values()[0]);
lateByRef(values()[1]);
byRef((new Maker)->make()['m']);
byRef(array_values([1, 2])[1]);
foreach ([
    fn() => byRef(chr(65)[0]),
    fn() => lateByRef(chr(0)[0]),
    fn() => lateByRef(strrev("ab")[0]),
    fn() => byRef(Maker::build()[0]),
    fn() => lateByRef(values()[0][0]),
] as $i => $f) {
    try {
        $f();
        echo "$i passed\n";
    } catch (Throwable $e) {
        echo "$i ", $e::class, ': ', $e->getMessage(), "\n";
    }
}
// the call itself as the argument still gets its notice
byRef(values());
echo "done\n";
