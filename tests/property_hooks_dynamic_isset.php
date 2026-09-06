<?php
// Dynamic names must share hook dispatch, write-context checks, and COW.
class DynamicHooks {
    public array $items = [] {
        get { echo "get\n"; return $this->items; }
        set { echo "set\n"; $this->items = $value; }
    }
}
$o = new DynamicHooks;
$p = 'items';
$o->$p = ['key' => [1]];
var_dump($o->$p);
var_dump(isset($o->items['key']), isset($o->$p['key']));
var_dump(isset($o->items['missing']), isset($o->$p['missing']));
var_dump(isset($o->items['key'][0]), isset($o->$p['key'][0]));
foreach ([0, 1, 2, 3] as $mode) {
    try {
        if ($mode === 0) $o->$p[] = 2;
        if ($mode === 1) $o->$p['key'] = 2;
        if ($mode === 2) $o->$p['key'][0] = 2;
        if ($mode === 3) $o->$p['key'][0] += 2;
    } catch (Error $e) { echo $e->getMessage(), "\n"; }
}
$o->{$p} = [];
var_dump($o->{$p});
class PlainDynamic { public array $a = [1]; public array $b = [2]; }
$o = new PlainDynamic;
$copy = $o->a;
foreach (['a', 'b'] as $p) { $o->$p[] = 3; var_dump($o->$p); }
var_dump($copy);
class IssetMagic {
    public bool $present = false;
    public function __isset($p) { echo "isset:$p\n"; return $this->present; }
    public function __get($p) { echo "magic:$p\n"; return [1]; }
}
$o = new IssetMagic; $p = 'a';
var_dump(isset($o->a[0]), isset($o->$p[0]));
$o->present = true;
var_dump(isset($o->a[0]), isset($o->$p[0]));
class ChangingGetter {
    public int $calls = 0;
    public array $a { get { ++$this->calls; return $this->calls === 1 ? [1] : []; } }
}
$o = new ChangingGetter;
var_dump(isset($o->a[0]), $o->calls);
class DynamicOffsets implements ArrayAccess {
    public function offsetExists(mixed $k): bool { return true; }
    public function offsetGet(mixed $k): mixed { return 1; }
    public function offsetSet(mixed $k, mixed $v): void { echo "offset:", $k ?? 'append', ":$v\n"; }
    public function offsetUnset(mixed $k): void {}
}
class ObjectGetter {
    public DynamicOffsets $a { get { echo "object-get\n"; return new DynamicOffsets; } }
}
$o = new ObjectGetter; $p = 'a';
$o->$p[] = 4;
$o->$p['key'] = 5;
class ThrowingDynamic {
    public int $a {
        get { throw new Exception('get failed'); }
        set { throw new Exception('set failed'); }
    }
}
$o = new ThrowingDynamic;
try { $o->$p = 1; } catch (Exception $e) { echo $e->getMessage(), "\n"; }
try { var_dump(isset($o->$p[0])); } catch (Exception $e) { echo $e->getMessage(), "\n"; }
try { var_dump($o->$p); } catch (Exception $e) { echo $e->getMessage(), "\n"; }
