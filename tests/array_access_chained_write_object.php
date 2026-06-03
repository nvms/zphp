<?php

// `$base[$k1][$k2] = $v` where `$base[$k1]` resolves to an ArrayAccess OBJECT
// must call that object's offsetSet($k2, $v) - NOT replace `$base[$k1]` with a
// fresh array. the bug only triggered when $base was a PROPERTY or static prop
// (the ensure_array_prop / ensure_array_static_prop vivify path clobbered the
// object); a plain-variable base already worked. this is the shape Laravel's
// `$this->app['config']['database.default'] = $name` uses (container holds a
// config repository, both ArrayAccess).

class Repo implements ArrayAccess {
    public array $items = ['database' => ['default' => 'sqlite', 'connections' => ['x' => 1]]];
    public function offsetExists($k): bool { return isset($this->items[$k]); }
    #[\ReturnTypeWillChange] public function offsetGet($k) { return $this->items[$k] ?? null; }
    public function offsetSet($k, $v): void { $this->items[$k] = $v; }
    public function offsetUnset($k): void { unset($this->items[$k]); }
}

class Container implements ArrayAccess {
    private array $instances = [];
    public function instance($k, $v): void { $this->instances[$k] = $v; }
    public function make($k) { return $this->instances[$k]; }
    public function offsetExists($k): bool { return isset($this->instances[$k]); }
    #[\ReturnTypeWillChange] public function offsetGet($k) { return $this->make($k); }
    public function offsetSet($k, $v): void { $this->instances[$k] = $v; }
    public function offsetUnset($k): void { unset($this->instances[$k]); }
}

class Manager {
    public static Container $shared;
    public function __construct(public Container $app) {}
    public function setViaProp($name): void {
        // chained write through a PROPERTY base ($this->app is ArrayAccess,
        // $this->app['config'] returns the Repo object)
        $this->app['config']['database.default'] = $name;
    }
    public function setViaStatic($name): void {
        self::$shared['config']['database.default'] = $name;
    }
}

$app = new Container();
$app->instance('config', new Repo());

$m = new Manager($app);
$m->setViaProp('mysql');

$cfg = $app['config'];
echo "config is object: ", ($cfg instanceof Repo ? 'y' : 'n'), "\n";        // y
echo "default set: ", $cfg['database.default'], "\n";                       // mysql
echo "database key intact: ", isset($cfg['database']) ? 'y' : 'n', "\n";    // y
echo "connections intact: ", implode(',', array_keys($cfg['database']['connections'])), "\n"; // x

// static-property base
Manager::$shared = new Container();
Manager::$shared->instance('config', new Repo());
$m->setViaStatic('pgsql');
$scfg = Manager::$shared['config'];
echo "static config is object: ", ($scfg instanceof Repo ? 'y' : 'n'), "\n"; // y
echo "static default: ", $scfg['database.default'], "\n";                    // pgsql

// the plain-variable base case must keep working too
$c2 = new Container();
$c2->instance('config', new Repo());
$c2['config']['database.default'] = 'sqlsrv';
echo "var-base default: ", $c2['config']['database.default'], "\n";          // sqlsrv

// a null/false property still vivifies to an array (the original behavior)
class Holder { public $data; }
$h = new Holder();
$h->data['a']['b'] = 1;
echo "vivify null prop: ", $h->data['a']['b'], "\n";                         // 1
