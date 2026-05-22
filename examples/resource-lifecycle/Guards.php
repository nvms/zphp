<?php

// RAII-style helpers built on __destruct - the pattern PHP code uses to
// guarantee cleanup without a finally block on every call site

// a running balance the transaction guard commits or discards against
final class Ledger
{
    private int $staged = 0;
    private int $balance = 0;

    public function stage(int $amount): void
    {
        $this->staged += $amount;
    }

    public function flush(): void
    {
        $this->balance += $this->staged;
        $this->staged = 0;
    }

    public function discard(): void
    {
        $this->staged = 0;
    }

    public function balance(): int
    {
        return $this->balance;
    }
}

// a transaction guard: if the caller never calls commit(), the destructor
// rolls the staged work back so an early return can never leak a half-done
// transaction
final class Transaction
{
    private bool $committed = false;

    public function __construct(private Ledger $ledger, private string $name)
    {
        echo "  begin '{$this->name}'\n";
    }

    public function record(int $amount): void
    {
        $this->ledger->stage($amount);
    }

    public function commit(): void
    {
        $this->ledger->flush();
        $this->committed = true;
        echo "  commit '{$this->name}'\n";
    }

    public function __destruct()
    {
        if (!$this->committed) {
            $this->ledger->discard();
            echo "  rollback '{$this->name}'\n";
        }
    }
}

// accumulates lines and reports how many it flushed when it leaves scope,
// so a caller never has to remember a trailing flush() call
final class BufferedWriter
{
    private array $buffer = [];

    public function writeLine(string $line): void
    {
        $this->buffer[] = $line;
    }

    public function snapshot(): string
    {
        return implode(' | ', $this->buffer);
    }

    public function __destruct()
    {
        echo '  flushed ' . count($this->buffer) . " line(s)\n";
    }
}

// runs an arbitrary cleanup closure when it is destructed - the generic
// form of a scope guard
final class ScopeGuard
{
    public function __construct(private string $label, private \Closure $cleanup)
    {
    }

    public function __destruct()
    {
        ($this->cleanup)();
        echo "  guard '{$this->label}' released\n";
    }
}

// a pooled connection (no destructor of its own - the pool owns its life)
final class Connection
{
    public function __construct(public readonly int $id)
    {
    }
}

// hands out Lease objects and takes connections back when a lease is
// destructed, so a borrowed connection is returned even on an early return
final class ConnectionPool
{
    private array $free = [];
    private int $next = 1;

    public function __construct(int $size)
    {
        for ($i = 0; $i < $size; $i++) {
            $this->free[] = new Connection($this->next++);
        }
    }

    public function acquire(): Lease
    {
        return new Lease($this, array_pop($this->free));
    }

    public function release(Connection $conn): void
    {
        $this->free[] = $conn;
    }

    public function available(): int
    {
        return count($this->free);
    }
}

final class Lease
{
    private bool $returned = false;

    public function __construct(private ConnectionPool $pool, private Connection $conn)
    {
    }

    public function id(): int
    {
        return $this->conn->id;
    }

    public function __destruct()
    {
        if (!$this->returned) {
            $this->pool->release($this->conn);
            $this->returned = true;
        }
    }
}

// a node that owns the next node as a property, so destructing the head
// of a chain cascades all the way down
final class Node
{
    private ?Node $next = null;

    public function __construct(private string $name)
    {
    }

    public function chain(Node $next): Node
    {
        $this->next = $next;
        return $next;
    }

    public function __destruct()
    {
        echo "  ~node {$this->name}\n";
    }
}
