<?php
// covers: interfaces, class implements interface, closures with use(&$ref),
//   array_splice, json_encode, priority sorting, callable dispatch,
//   method chaining, event data mutation across listeners

interface EventInterface
{
    public function getName(): string;
    public function isPropagationStopped(): bool;
    public function stopPropagation(): void;
}

class Event implements EventInterface
{
    private string $name;
    private bool $stopped = false;
    private array $data;

    public function __construct(string $name, array $data = [])
    {
        $this->name = $name;
        $this->data = $data;
    }

    public function getName(): string { return $this->name; }
    public function isPropagationStopped(): bool { return $this->stopped; }
    public function stopPropagation(): void { $this->stopped = true; }
    public function get(string $key) { return $this->data[$key] ?? null; }
    public function set(string $key, $value): void { $this->data[$key] = $value; }
    public function getData(): array { return $this->data; }
}

interface ListenerInterface
{
    public function handle(EventInterface $event): void;
}

class CallableListener implements ListenerInterface
{
    private $callback;

    public function __construct(callable $callback)
    {
        $this->callback = $callback;
    }

    public function handle(EventInterface $event): void
    {
        ($this->callback)($event);
    }
}

class EventDispatcher
{
    private array $listeners = [];
    private array $log = [];

    public function listen(string $eventName, $listener, int $priority = 0): self
    {
        if (!isset($this->listeners[$eventName])) {
            $this->listeners[$eventName] = [];
        }
        if (is_callable($listener)) {
            $listener = new CallableListener($listener);
        }
        $this->listeners[$eventName][] = [
            "listener" => $listener,
            "priority" => $priority,
        ];
        return $this;
    }

    public function dispatch(EventInterface $event): EventInterface
    {
        $name = $event->getName();
        $this->log[] = "dispatch: $name";

        $listeners = $this->getListeners($name);
        foreach ($listeners as $entry) {
            if ($event->isPropagationStopped()) {
                $this->log[] = "stopped: $name";
                break;
            }
            $entry["listener"]->handle($event);
        }

        return $event;
    }

    public function getListeners(string $eventName): array
    {
        $listeners = $this->listeners[$eventName] ?? [];

        // sort by priority (higher first) using simple insertion sort
        $sorted = [];
        foreach ($listeners as $entry) {
            $inserted = false;
            for ($i = 0; $i < count($sorted); $i++) {
                if ($entry["priority"] > $sorted[$i]["priority"]) {
                    array_splice($sorted, $i, 0, [$entry]);
                    $inserted = true;
                    break;
                }
            }
            if (!$inserted) $sorted[] = $entry;
        }

        return $sorted;
    }

    public function hasListeners(string $eventName): bool
    {
        return isset($this->listeners[$eventName]) && count($this->listeners[$eventName]) > 0;
    }

    public function getLog(): array
    {
        return $this->log;
    }
}

class UserCreatedHandler implements ListenerInterface
{
    private array $notifications = [];

    public function handle(EventInterface $event): void
    {
        $name = $event->get("name");
        $this->notifications[] = "Welcome email sent to $name";
    }

    public function getNotifications(): array
    {
        return $this->notifications;
    }
}

class AuditLogger implements ListenerInterface
{
    private array $entries = [];

    public function handle(EventInterface $event): void
    {
        $this->entries[] = "[audit] " . $event->getName() . ": " . json_encode($event->getData());
    }

    public function getEntries(): array
    {
        return $this->entries;
    }
}

// set up dispatcher
$dispatcher = new EventDispatcher();
$auditLogger = new AuditLogger();
$userHandler = new UserCreatedHandler();

// register class-based listeners
$dispatcher->listen("user.created", $userHandler, 10);
$dispatcher->listen("user.created", $auditLogger, 5);

// register closure listener
$createdNames = [];
$dispatcher->listen("user.created", function (EventInterface $event) use (&$createdNames) {
    $createdNames[] = $event->get("name");
}, 1);

// register listener for different event
$deletedLog = [];
$dispatcher->listen("user.deleted", function (EventInterface $event) use (&$deletedLog) {
    $deletedLog[] = $event->get("name") . " was deleted";
});

// dispatch events
$event1 = new Event("user.created", ["name" => "Alice", "email" => "alice@test.com"]);
$dispatcher->dispatch($event1);

$event2 = new Event("user.created", ["name" => "Bob", "email" => "bob@test.com"]);
$dispatcher->dispatch($event2);

$event3 = new Event("user.deleted", ["name" => "Charlie"]);
$dispatcher->dispatch($event3);

// check results
echo "notifications:\n";
foreach ($userHandler->getNotifications() as $n) echo "  $n\n";

echo "audit log:\n";
foreach ($auditLogger->getEntries() as $e) echo "  $e\n";

echo "created: " . implode(", ", $createdNames) . "\n";
echo "deleted: " . implode(", ", $deletedLog) . "\n";

// test priority ordering
$order = [];
$d2 = new EventDispatcher();
$d2->listen("test", function ($e) use (&$order) { $order[] = "low"; }, 1);
$d2->listen("test", function ($e) use (&$order) { $order[] = "high"; }, 100);
$d2->listen("test", function ($e) use (&$order) { $order[] = "medium"; }, 50);
$d2->dispatch(new Event("test"));
echo "priority order: " . implode(", ", $order) . "\n";

// test propagation stopping
$stopped = [];
$d3 = new EventDispatcher();
$d3->listen("stop.test", function (EventInterface $e) use (&$stopped) {
    $stopped[] = "first";
    $e->stopPropagation();
}, 10);
$d3->listen("stop.test", function (EventInterface $e) use (&$stopped) {
    $stopped[] = "second";
}, 5);
$d3->dispatch(new Event("stop.test"));
echo "stopped after: " . implode(", ", $stopped) . "\n";

// test hasListeners
echo "has user.created: " . var_export($dispatcher->hasListeners("user.created"), true) . "\n";
echo "has unknown: " . var_export($dispatcher->hasListeners("unknown"), true) . "\n";

// test event data mutation
$mutator = new EventDispatcher();
$mutator->listen("transform", function (EventInterface $e) {
    $val = $e->get("value");
    $e->set("value", $val * 2);
}, 10);
$mutator->listen("transform", function (EventInterface $e) {
    $val = $e->get("value");
    $e->set("value", $val + 10);
}, 5);

$te = new Event("transform", ["value" => 5]);
$mutator->dispatch($te);
echo "transformed: " . $te->get("value") . "\n";

// test dispatch log
$log = $dispatcher->getLog();
echo "dispatched events: " . count($log) . "\n";
foreach ($log as $entry) echo "  $entry\n";

// test try/catch in listener
$errorDispatcher = new EventDispatcher();
$errorResults = [];
$errorDispatcher->listen("risky", function ($e) use (&$errorResults) {
    try {
        $val = $e->get("divisor");
        if ($val === 0) {
            throw new RuntimeException("division by zero");
        }
        $errorResults[] = "ok: " . (100 / $val);
    } catch (RuntimeException $ex) {
        $errorResults[] = "caught: " . $ex->getMessage();
    }
});

$errorDispatcher->dispatch(new Event("risky", ["divisor" => 5]));
$errorDispatcher->dispatch(new Event("risky", ["divisor" => 0]));
echo "error handling:\n";
foreach ($errorResults as $r) echo "  $r\n";

echo "done\n";
