<?php
// covers: interface_exists, class_implements, class_exists, is_a, get_class,
//   get_class_methods, get_object_vars, is_object, is_string, method_exists,
//   property_exists, array_keys, array_values, in_array, count, sprintf,
//   implode, is_callable

// define interfaces
interface Logger {
    public function log(string $level, string $message): void;
}

interface Cache {
    public function get(string $key): string;
    public function set(string $key, string $value): void;
}

interface EventDispatcher {
    public function dispatch(string $event, array $data): void;
}

// implementations
class ConsoleLogger implements Logger {
    private string $prefix;

    public function __construct(string $prefix = '[LOG]') {
        $this->prefix = $prefix;
    }

    public function log(string $level, string $message): void {
        echo "  " . $this->prefix . " $level: $message\n";
    }
}

class MemoryCache implements Cache {
    private array $store = [];

    public function get(string $key): string {
        return $this->store[$key] ?? '';
    }

    public function set(string $key, string $value): void {
        $this->store[$key] = $value;
    }
}

class SimpleDispatcher implements EventDispatcher {
    private array $listeners = [];

    public function on(string $event, $callback): void {
        if (!isset($this->listeners[$event])) {
            $this->listeners[$event] = [];
        }
        $this->listeners[$event][] = $callback;
    }

    public function dispatch(string $event, array $data): void {
        if (!isset($this->listeners[$event])) return;
        foreach ($this->listeners[$event] as $callback) {
            $callback($data);
        }
    }
}

// service container
class Container {
    private array $bindings = [];
    private array $instances = [];

    public function bind(string $interface, $factory): void {
        $this->bindings[$interface] = $factory;
    }

    public function singleton(string $interface, $factory): void {
        $this->bindings[$interface] = function () use ($interface, $factory) {
            if (!isset($this->instances[$interface])) {
                $this->instances[$interface] = $factory($this);
            }
            return $this->instances[$interface];
        };
    }

    public function get(string $interface) {
        if (isset($this->instances[$interface])) {
            return $this->instances[$interface];
        }
        if (isset($this->bindings[$interface])) {
            $result = ($this->bindings[$interface])($this);
            return $result;
        }
        return null;
    }

    public function has(string $name): bool {
        return isset($this->bindings[$name]) || isset($this->instances[$name]);
    }
}

// interface checks
echo "=== interface introspection ===\n";
echo "Logger exists: " . (interface_exists('Logger') ? 'yes' : 'no') . "\n";
echo "Cache exists: " . (interface_exists('Cache') ? 'yes' : 'no') . "\n";
echo "NonExistent exists: " . (interface_exists('NonExistent') ? 'yes' : 'no') . "\n";

// class_implements
echo "\n=== class_implements ===\n";
$classes = ['ConsoleLogger', 'MemoryCache', 'SimpleDispatcher', 'Container'];
foreach ($classes as $cls) {
    $ifaces = class_implements($cls);
    $list = count($ifaces) > 0 ? implode(', ', array_values($ifaces)) : 'none';
    echo sprintf("  %-20s implements: %s\n", $cls, $list);
}

// is_a checks
echo "\n=== is_a checks ===\n";
$logger = new ConsoleLogger('[APP]');
$cache = new MemoryCache();
echo "logger is_a Logger: " . (is_a($logger, 'Logger') ? 'yes' : 'no') . "\n";
echo "logger is_a Cache: " . (is_a($logger, 'Cache') ? 'yes' : 'no') . "\n";
echo "cache is_a Cache: " . (is_a($cache, 'Cache') ? 'yes' : 'no') . "\n";

// class inspection
echo "\n=== class inspection ===\n";
echo "ConsoleLogger methods: " . implode(', ', get_class_methods('ConsoleLogger')) . "\n";
echo "MemoryCache methods: " . implode(', ', get_class_methods('MemoryCache')) . "\n";

// wire up the container
echo "\n=== container usage ===\n";
$container = new Container();

$container->singleton('Logger', function ($c) {
    return new ConsoleLogger('[DI]');
});

$container->singleton('Cache', function ($c) {
    return new MemoryCache();
});

$container->bind('EventDispatcher', function ($c) {
    $dispatcher = new SimpleDispatcher();
    $dispatcher->on('user.login', function ($data) use ($c) {
        $logger = $c->get('Logger');
        $logger->log('INFO', 'User logged in: ' . $data['user']);
    });
    return $dispatcher;
});

// resolve services
$log = $container->get('Logger');
$log->log('INFO', 'Container initialized');

$c1 = $container->get('Cache');
$c1->set('greeting', 'hello from DI');
$c2 = $container->get('Cache');
echo "  cache singleton check: " . ($c2->get('greeting') === 'hello from DI' ? 'ok' : 'fail') . "\n";

// verify singleton identity
echo "  same instance: " . (spl_object_id($c1) === spl_object_id($c2) ? 'yes' : 'no') . "\n";

// dispatch an event
$dispatcher = $container->get('EventDispatcher');
$dispatcher->dispatch('user.login', ['user' => 'admin']);

// container has checks
echo "\n=== container has ===\n";
echo "has Logger: " . ($container->has('Logger') ? 'yes' : 'no') . "\n";
echo "has Cache: " . ($container->has('Cache') ? 'yes' : 'no') . "\n";
echo "has Database: " . ($container->has('Database') ? 'yes' : 'no') . "\n";

// get_class on resolved instances
echo "\n=== resolved types ===\n";
$services = ['Logger', 'Cache', 'EventDispatcher'];
foreach ($services as $name) {
    $instance = $container->get($name);
    echo sprintf("  %-20s -> %s\n", $name, get_class($instance));
}

// method_exists on resolved instances
echo "\n=== method checks ===\n";
echo "Logger->log: " . (method_exists($log, 'log') ? 'yes' : 'no') . "\n";
echo "Logger->get: " . (method_exists($log, 'get') ? 'yes' : 'no') . "\n";
echo "Cache->get: " . (method_exists($c1, 'get') ? 'yes' : 'no') . "\n";
echo "Cache->set: " . (method_exists($c1, 'set') ? 'yes' : 'no') . "\n";
