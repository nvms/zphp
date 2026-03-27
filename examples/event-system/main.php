<?php
// covers: closures, array_key_exists, usort, array_filter, array_map, array_values, is_callable, call_user_func_array, spl_object_id, get_class

class EventEmitter {
    private array $listeners = [];
    private array $onceListeners = [];

    public function on(string $event, callable $listener, int $priority = 0): void {
        if (!array_key_exists($event, $this->listeners)) {
            $this->listeners[$event] = [];
        }
        $this->listeners[$event][] = ['fn' => $listener, 'priority' => $priority];
        usort($this->listeners[$event], function($a, $b) {
            return $b['priority'] - $a['priority'];
        });
    }

    public function once(string $event, callable $listener, int $priority = 0): void {
        if (!array_key_exists($event, $this->onceListeners)) {
            $this->onceListeners[$event] = [];
        }
        $this->onceListeners[$event][] = ['fn' => $listener, 'priority' => $priority];
    }

    public function emit(string $event, array $args = []): int {
        $count = 0;

        if (array_key_exists($event, $this->listeners)) {
            foreach ($this->listeners[$event] as $entry) {
                call_user_func_array($entry['fn'], $args);
                $count++;
            }
        }

        if (array_key_exists($event, $this->onceListeners)) {
            foreach ($this->onceListeners[$event] as $entry) {
                call_user_func_array($entry['fn'], $args);
                $count++;
            }
            unset($this->onceListeners[$event]);
        }

        return $count;
    }

    public function off(string $event): void {
        unset($this->listeners[$event]);
        unset($this->onceListeners[$event]);
    }

    public function listenerCount(string $event): int {
        $count = 0;
        if (array_key_exists($event, $this->listeners)) {
            $count += count($this->listeners[$event]);
        }
        if (array_key_exists($event, $this->onceListeners)) {
            $count += count($this->onceListeners[$event]);
        }
        return $count;
    }
}

class Logger {
    private array $entries = [];

    public function log(string $level, string $message, array $context = []): void {
        $this->entries[] = [
            'level' => $level,
            'message' => $message,
            'context' => $context,
        ];
    }

    public function getEntries(): array {
        return $this->entries;
    }

    public function filter(string $level): array {
        return array_values(array_filter($this->entries, function($entry) use ($level) {
            return $entry['level'] === $level;
        }));
    }

    public function format(): array {
        return array_map(function($entry) {
            $ctx = '';
            if (count($entry['context']) > 0) {
                $parts = [];
                foreach ($entry['context'] as $k => $v) {
                    $parts[] = "$k=$v";
                }
                $ctx = ' [' . implode(', ', $parts) . ']';
            }
            return strtoupper($entry['level']) . ': ' . $entry['message'] . $ctx;
        }, $this->entries);
    }
}

// --- test event emitter ---

$emitter = new EventEmitter();
$log = [];

$emitter->on('user.login', function(string $name) use (&$log) {
    $log[] = "login: $name";
});

$emitter->on('user.login', function(string $name) use (&$log) {
    $log[] = "audit: $name logged in";
}, 10);

$emitter->emit('user.login', ['alice']);

echo "Event order (priority):\n";
foreach ($log as $entry) {
    echo "  $entry\n";
}

// once listeners
$onceLog = [];
$emitter->once('notify', function(string $msg) use (&$onceLog) {
    $onceLog[] = $msg;
});

$emitter->emit('notify', ['first']);
$emitter->emit('notify', ['second']);

echo "Once listener fired: " . count($onceLog) . " time(s)\n";
echo "Once value: " . $onceLog[0] . "\n";

// listener count
$emitter->on('data', function() {});
$emitter->on('data', function() {});
echo "Data listeners: " . $emitter->listenerCount('data') . "\n";

$emitter->off('data');
echo "After off: " . $emitter->listenerCount('data') . "\n";

// --- test logger with closures ---

$logger = new Logger();
$logger->log('info', 'Application started');
$logger->log('debug', 'Loading config', ['file' => 'app.ini']);
$logger->log('error', 'Connection failed', ['host' => 'db.local', 'port' => '5432']);
$logger->log('info', 'Retrying connection');
$logger->log('debug', 'Cache warmed', ['entries' => '142']);

echo "\nAll formatted:\n";
foreach ($logger->format() as $line) {
    echo "  $line\n";
}

echo "\nErrors only:\n";
$errors = $logger->filter('error');
echo "  Count: " . count($errors) . "\n";
echo "  Message: " . $errors[0]['message'] . "\n";

// --- middleware pipeline ---

function pipeline(array $middlewares, $input) {
    $next = function($value) { return $value; };

    for ($i = count($middlewares) - 1; $i >= 0; $i--) {
        $fn = $middlewares[$i];
        $currentNext = $next;
        $next = function($value) use ($fn, $currentNext) {
            return $fn($value, $currentNext);
        };
    }

    return $next($input);
}

$result = pipeline([
    function($val, $next) { return $next($val * 2); },
    function($val, $next) { return $next($val + 10); },
    function($val, $next) { return $next($val * $val); },
], 5);

echo "\nPipeline result: $result\n";

// --- observer pattern with classes ---

class Subject {
    private array $observers = [];
    private string $state = '';

    public function attach(object $observer): void {
        $this->observers[] = $observer;
    }

    public function setState(string $state): void {
        $this->state = $state;
        $this->notify();
    }

    public function getState(): string {
        return $this->state;
    }

    private function notify(): void {
        foreach ($this->observers as $observer) {
            $observer->update($this);
        }
    }
}

class ConsoleObserver {
    private string $name;
    public array $received = [];

    public function __construct(string $name) {
        $this->name = $name;
    }

    public function update(Subject $subject): void {
        $this->received[] = $subject->getState();
    }
}

$subject = new Subject();
$obs1 = new ConsoleObserver('A');
$obs2 = new ConsoleObserver('B');

$subject->attach($obs1);
$subject->attach($obs2);

$subject->setState('active');
$subject->setState('idle');

echo "\nObserver A received: " . implode(', ', $obs1->received) . "\n";
echo "Observer B received: " . implode(', ', $obs2->received) . "\n";

// --- closure composition ---

function compose(callable ...$fns): callable {
    return function($x) use ($fns) {
        $result = $x;
        for ($i = count($fns) - 1; $i >= 0; $i--) {
            $result = $fns[$i]($result);
        }
        return $result;
    };
}

$double = function($x) { return $x * 2; };
$addOne = function($x) { return $x + 1; };
$square = function($x) { return $x * $x; };

$transform = compose($square, $addOne, $double);
echo "\nCompose (5): " . $transform(5) . "\n";

// --- currying ---

function curry(callable $fn, ...$initial): callable {
    return function() use ($fn, $initial) {
        $args = array_merge($initial, func_get_args());
        return call_user_func_array($fn, $args);
    };
}

$add = function($a, $b) { return $a + $b; };
$add5 = curry($add, 5);
echo "Curry add5(3): " . $add5(3) . "\n";

$multiply = function($a, $b, $c) { return $a * $b * $c; };
$triple = curry($multiply, 1, 3);
echo "Curry triple(7): " . $triple(7) . "\n";
