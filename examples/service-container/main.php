<?php

class Container
{
    private array $bindings = [];
    private array $singletons = [];
    private array $instances = [];

    public function bind(string $name, callable $factory): void
    {
        $this->bindings[$name] = $factory;
    }

    public function singleton(string $name, callable $factory): void
    {
        $this->singletons[$name] = $factory;
    }

    public function get(string $name)
    {
        if (isset($this->instances[$name])) {
            return $this->instances[$name];
        }

        if (isset($this->singletons[$name])) {
            $this->instances[$name] = ($this->singletons[$name])($this);
            return $this->instances[$name];
        }

        if (isset($this->bindings[$name])) {
            return ($this->bindings[$name])($this);
        }

        return null;
    }

    public function has(string $name): bool
    {
        return isset($this->bindings[$name]) || isset($this->singletons[$name]) || isset($this->instances[$name]);
    }
}

interface Logger
{
    public function log(string $message): void;
    public function getMessages(): array;
}

class ArrayLogger implements Logger
{
    private array $messages = [];

    public function log(string $message): void
    {
        $this->messages[] = $message;
    }

    public function getMessages(): array
    {
        return $this->messages;
    }
}

class UserService
{
    private $logger;
    private array $users = [];

    public function __construct(Logger $logger)
    {
        $this->logger = $logger;
    }

    public function create(string $name, string $email): array
    {
        $user = ["name" => $name, "email" => $email, "id" => count($this->users) + 1];
        $this->users[] = $user;
        $this->logger->log("created user: " . $name);
        return $user;
    }

    public function find(int $id): ?array
    {
        foreach ($this->users as $user) {
            if ($user["id"] === $id) return $user;
        }
        return null;
    }

    public function all(): array
    {
        return $this->users;
    }
}

class NotificationService
{
    private $logger;

    public function __construct(Logger $logger)
    {
        $this->logger = $logger;
    }

    public function send(string $to, string $message): void
    {
        $this->logger->log("notification to " . $to . ": " . $message);
    }
}

// wire up container
$container = new Container();

$container->singleton("logger", function ($c) {
    return new ArrayLogger();
});

$container->singleton("users", function ($c) {
    return new UserService($c->get("logger"));
});

$container->bind("notifications", function ($c) {
    return new NotificationService($c->get("logger"));
});

// use services
$userService = $container->get("users");
$userService->create("Alice", "alice@example.com");
$userService->create("Bob", "bob@example.com");

$notifier = $container->get("notifications");
$notifier->send("alice@example.com", "Welcome!");

// singleton test: same logger instance shared
$logger = $container->get("logger");
$messages = $logger->getMessages();
foreach ($messages as $msg) {
    echo $msg . "\n";
}

// verify singleton identity
$userService2 = $container->get("users");
echo ($userService === $userService2) ? "singleton works" : "not singleton";
echo "\n";

// binding creates new instances
$notifier2 = $container->get("notifications");
echo ($notifier === $notifier2) ? "same" : "different instances";
echo "\n";

// container has
echo $container->has("logger") ? "has logger" : "no logger";
echo "\n";
echo $container->has("missing") ? "has missing" : "no missing";
echo "\n";

// find user
$user = $userService->find(1);
echo $user["name"] . " " . $user["email"] . "\n";

echo "total users: " . count($userService->all()) . "\n";

echo "done\n";
