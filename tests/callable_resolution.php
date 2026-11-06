<?php
// a callable runs what php resolves it to: __call and __callStatic for a
// missing method, the calling scope for self/parent/static and private
// methods, and php's errors for one it cannot call, both handed to an
// internal function and called directly
class Magic {
    function __call($n, $a) { echo "__call $n(", implode(',', $a), ")\n"; return "c"; }
    static function __callStatic($n, $a) { echo "__callStatic $n(", implode(',', $a), ")\n"; return "s"; }
    private function priv() { return "priv"; }
    protected static function prot() { return "prot"; }
    function inst() { return "inst"; }
    static function stat() { return "stat"; }
    function inside() {
        var_dump(call_user_func([$this, 'priv']));
        var_dump(call_user_func('self::stat'));
        var_dump(call_user_func(['self', 'stat']));
        var_dump(call_user_func('static::prot'));
        var_dump(call_user_func([$this, 'nope'], 1));
        var_dump(call_user_func('Magic::nope2', 2));
        $f = 'self::stat'; var_dump($f());
        $f = ['Magic', 'priv']; var_dump($f());
    }
}
class Plain { function inst() { return "pinst"; } private function priv() {} static function stat() { return "pstat"; } }

function t($label, $fn) {
    try { $r = $fn(); echo "$label => "; var_dump($r); }
    catch (Throwable $e) { echo "$label !! ", get_class($e), ": ", $e->getMessage(), "\n"; }
}
$m = new Magic; $p = new Plain;
t('dyn obj undefined', function () use ($m) { $f = [$m, 'foo']; return $f(1, 2); });
t('dyn class undefined', function () { $f = ['Magic', 'foo']; return $f(3); });
t('dyn string undefined', function () { $f = 'Magic::foo'; return $f(4); });
t('cuf obj undefined', fn() => call_user_func([$m, 'bar'], 5));
t('cuf class undefined', fn() => call_user_func(['Magic', 'bar'], 6));
t('cuf string undefined', fn() => call_user_func('Magic::bar', 7));
t('cufa obj', fn() => call_user_func_array([$m, 'baz'], [8, 9]));
t('array_map magic', fn() => array_map([$m, 'mapped'], [1, 2]));
t('usort magic', function () use ($m) { $a = [2, 1]; usort($a, [new class { function __call($n, $a) { return $a[0] <=> $a[1]; } }, 'cmp']); return $a; });
t('cuf private outside', fn() => call_user_func([$m, 'priv']));
t('dyn private outside', function () use ($m) { $f = [$m, 'priv']; return $f(); });
t('cuf plain undefined', fn() => call_user_func([$p, 'nope']));
t('dyn plain undefined', function () use ($p) { $f = [$p, 'nope']; return $f(); });
t('cuf plain private', fn() => call_user_func([$p, 'priv']));
t('dyn plain private', function () use ($p) { $f = [$p, 'priv']; return $f(); });
t('cuf nonstatic statically', fn() => call_user_func(['Plain', 'inst']));
t('dyn nonstatic statically', function () { $f = ['Plain', 'inst']; return $f(); });
t('cuf null target', fn() => call_user_func([null, 'x']));
t('dyn null target', function () { $f = [null, 'x']; return $f(); });
t('cuf 3 elems', fn() => call_user_func([1, 2, 3]));
t('dyn 3 elems', function () { $f = [1, 2, 3]; return $f(); });
t('cuf int method', fn() => call_user_func([$p, 5]));
t('dyn int method', function () use ($p) { $f = [$p, 5]; return $f(); });
t('cuf no class', fn() => call_user_func(['NoSuch', 'x']));
t('dyn no class', function () { $f = ['NoSuch', 'x']; return $f(); });
t('cuf no class str', fn() => call_user_func('NoSuch::x'));
t('dyn no class str', function () { $f = 'NoSuch::x'; return $f(); });
t('cuf no func', fn() => call_user_func('nofunc'));
t('dyn no func', function () { $f = 'nofunc'; return $f(); });
t('cuf int', fn() => call_user_func(5));
t('dyn int', function () { $f = 5; return $f(); });
t('cuf self outside', fn() => call_user_func('self::x'));
t('cuf obj no invoke', fn() => call_user_func($p));
t('dyn obj no invoke', function () use ($p) { return $p(); });
t('cuf many args', fn() => call_user_func('max', ...range(1, 40)));
t('dyn many args', function () { $f = [new Magic, 'many']; return $f(...range(1, 20)); });
t('array_map no func', fn() => array_map('nofunc', [1]));
t('usort no func', function () { $a = [1, 2]; return usort($a, 'nofunc'); });
t('cuf parent str', fn() => call_user_func('parent::x'));
$m->inside();
