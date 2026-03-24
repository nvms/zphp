<?php
// covers: enums with instance methods, backed enums (string), match expressions,
//   try/catch/finally, custom exception hierarchy, static properties/methods,
//   fibers (suspend/resume), output buffering (ob_start/ob_get_clean),
//   array_map, array_keys, in_array, implode, is_scalar, ctype_alpha,
//   closures as transition guards, SplStack, constructor property promotion

// --- custom exception hierarchy ---

class StateMachineException extends RuntimeException {}
class InvalidTransitionException extends StateMachineException {}
class GuardRejectedException extends StateMachineException {}

// --- order status enum with methods ---

enum OrderStatus: string
{
    case Pending = "pending";
    case Paid = "paid";
    case Shipped = "shipped";
    case Delivered = "delivered";
    case Cancelled = "cancelled";
    case Refunded = "refunded";

    public function label(): string
    {
        return match ($this) {
            OrderStatus::Pending => "Pending Review",
            OrderStatus::Paid => "Payment Received",
            OrderStatus::Shipped => "In Transit",
            OrderStatus::Delivered => "Delivered",
            OrderStatus::Cancelled => "Cancelled",
            OrderStatus::Refunded => "Refunded",
        };
    }

    public function isFinal(): bool
    {
        return match ($this) {
            OrderStatus::Delivered, OrderStatus::Cancelled, OrderStatus::Refunded => true,
            default => false,
        };
    }

    public function allowsCancel(): bool
    {
        return match ($this) {
            OrderStatus::Pending, OrderStatus::Paid => true,
            default => false,
        };
    }
}

// --- transition log entry ---

class TransitionEntry
{
    public function __construct(
        public string $from,
        public string $to,
        public string $timestamp
    ) {}

    public function __toString(): string
    {
        return "{$this->from} -> {$this->to} at {$this->timestamp}";
    }
}

// --- the state machine ---

class StateMachine
{
    private OrderStatus $state;
    private array $transitions = [];
    private array $guards = [];
    private SplStack $history;
    private static int $instanceCount = 0;

    public function __construct(OrderStatus $initial)
    {
        $this->state = $initial;
        $this->history = new SplStack();
        self::$instanceCount++;
    }

    public static function getInstanceCount(): int
    {
        return self::$instanceCount;
    }

    public function addTransition(OrderStatus $from, OrderStatus $to): self
    {
        $key = $from->value . ":" . $to->value;
        $this->transitions[$key] = true;
        return $this;
    }

    public function addGuard(OrderStatus $from, OrderStatus $to, callable $guard): self
    {
        $key = $from->value . ":" . $to->value;
        $this->guards[$key] = $guard;
        return $this;
    }

    public function canTransition(OrderStatus $to): bool
    {
        $key = $this->state->value . ":" . $to->value;
        return isset($this->transitions[$key]);
    }

    public function transition(OrderStatus $to): void
    {
        if ($this->state->isFinal()) {
            throw new InvalidTransitionException(
                "Cannot transition from final state: " . $this->state->label()
            );
        }

        $key = $this->state->value . ":" . $to->value;

        if (!isset($this->transitions[$key])) {
            throw new InvalidTransitionException(
                "No transition from " . $this->state->value . " to " . $to->value
            );
        }

        if (isset($this->guards[$key])) {
            $guard = $this->guards[$key];
            if (!$guard($this->state, $to)) {
                throw new GuardRejectedException(
                    "Guard rejected: " . $this->state->value . " to " . $to->value
                );
            }
        }

        $from = $this->state;
        $this->state = $to;
        $entry = new TransitionEntry($from->value, $to->value, date("H:i:s"));
        $this->history->push($entry);
    }

    public function getState(): OrderStatus
    {
        return $this->state;
    }

    public function getHistory(): SplStack
    {
        return $this->history;
    }
}

// --- build the machine ---

function buildOrderMachine(): StateMachine
{
    $sm = new StateMachine(OrderStatus::Pending);

    $sm->addTransition(OrderStatus::Pending, OrderStatus::Paid)
       ->addTransition(OrderStatus::Pending, OrderStatus::Cancelled)
       ->addTransition(OrderStatus::Paid, OrderStatus::Shipped)
       ->addTransition(OrderStatus::Paid, OrderStatus::Cancelled)
       ->addTransition(OrderStatus::Paid, OrderStatus::Refunded)
       ->addTransition(OrderStatus::Shipped, OrderStatus::Delivered)
       ->addTransition(OrderStatus::Shipped, OrderStatus::Refunded);

    $sm->addGuard(OrderStatus::Paid, OrderStatus::Refunded, function ($from, $to) {
        return true;
    });

    return $sm;
}

// === test: basic transitions ===

$order = buildOrderMachine();
echo "initial: " . $order->getState()->label() . "\n";

$order->transition(OrderStatus::Paid);
echo "after pay: " . $order->getState()->label() . "\n";

$order->transition(OrderStatus::Shipped);
echo "after ship: " . $order->getState()->label() . "\n";

$order->transition(OrderStatus::Delivered);
echo "after deliver: " . $order->getState()->label() . "\n";
echo "is final: " . ($order->getState()->isFinal() ? "yes" : "no") . "\n";

// === test: invalid transition with try/catch ===

try {
    $order->transition(OrderStatus::Refunded);
    echo "ERROR: should not reach here\n";
} catch (InvalidTransitionException $e) {
    echo "caught: " . $e->getMessage() . "\n";
}

// === test: try/catch/finally ===

$order2 = buildOrderMachine();
$cleanupRan = false;
try {
    $order2->transition(OrderStatus::Paid);
    $order2->transition(OrderStatus::Shipped);
    $order2->transition(OrderStatus::Pending);
} catch (InvalidTransitionException $e) {
    echo "caught invalid: " . $e->getMessage() . "\n";
} finally {
    $cleanupRan = true;
}
echo "finally ran: " . ($cleanupRan ? "yes" : "no") . "\n";
echo "state after error: " . $order2->getState()->label() . "\n";

// === test: guard rejection ===

$order3 = buildOrderMachine();
$order3->addGuard(OrderStatus::Pending, OrderStatus::Paid, function ($from, $to) {
    return false;
});

try {
    $order3->transition(OrderStatus::Paid);
} catch (GuardRejectedException $e) {
    echo "guard: " . $e->getMessage() . "\n";
}

// === test: enum methods ===

$statuses = OrderStatus::cases();
$labels = array_map(function ($s) { return $s->label(); }, $statuses);
echo "labels: " . implode(", ", $labels) . "\n";

$finals = array_filter($statuses, function ($s) { return $s->isFinal(); });
$finalNames = array_map(function ($s) { return $s->value; }, array_values($finals));
echo "final states: " . implode(", ", $finalNames) . "\n";

$cancellable = array_filter($statuses, function ($s) { return $s->allowsCancel(); });
$cancelNames = array_map(function ($s) { return $s->value; }, array_values($cancellable));
echo "cancellable: " . implode(", ", $cancelNames) . "\n";

// === test: from/tryFrom ===

$found = OrderStatus::from("shipped");
echo "from: " . $found->label() . "\n";

$maybe = OrderStatus::tryFrom("nonexistent");
echo "tryFrom missing: " . ($maybe === null ? "null" : "found") . "\n";

// === test: history with SplStack ===

$order4 = buildOrderMachine();
$order4->transition(OrderStatus::Paid);
$order4->transition(OrderStatus::Shipped);
$order4->transition(OrderStatus::Delivered);

echo "history count: " . $order4->getHistory()->count() . "\n";
$top = $order4->getHistory()->top();
echo "last transition to: " . $top->to . "\n";

// === test: static property ===

echo "machines created: " . StateMachine::getInstanceCount() . "\n";

// === test: output buffering ===

ob_start();
echo "buffered content";
$captured = ob_get_clean();
echo "captured " . strlen($captured) . " chars\n";

// === test: fiber-based async processing ===

function processOrder(StateMachine $sm, array $steps): Fiber
{
    return new Fiber(function () use ($sm, $steps) {
        foreach ($steps as $step) {
            $sm->transition($step);
            Fiber::suspend($sm->getState()->label());
        }
        return $sm->getState()->value;
    });
}

$order5 = buildOrderMachine();
$fiber = processOrder($order5, [OrderStatus::Paid, OrderStatus::Shipped, OrderStatus::Delivered]);

$result = $fiber->start();
echo "fiber step 1: $result\n";

$result = $fiber->resume();
echo "fiber step 2: $result\n";

$result = $fiber->resume();
echo "fiber step 3: $result\n";
echo "fiber suspended: " . ($fiber->isSuspended() ? "yes" : "no") . "\n";

$fiber->resume();
echo "fiber terminated: " . ($fiber->isTerminated() ? "yes" : "no") . "\n";
echo "fiber return: " . $fiber->getReturn() . "\n";

// === test: is_scalar and ctype from new stdlib ===

echo "is_scalar string: " . (is_scalar("hello") ? "yes" : "no") . "\n";
echo "is_scalar array: " . (is_scalar([]) ? "yes" : "no") . "\n";
echo "ctype_alpha: " . (ctype_alpha("hello") ? "yes" : "no") . "\n";
echo "ctype_digit: " . (ctype_digit("12345") ? "yes" : "no") . "\n";

echo "done\n";
