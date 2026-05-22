<?php
// covers: __destruct timing - RAII scope guards, an auto-rollback
//   transaction guard, a buffered writer that flushes when it leaves
//   scope, connection-pool leases returned on destruct, an owned-node
//   chain that cascades, and destruct on reassignment / unset / function
//   return; constructor-promoted properties, readonly properties,
//   closures stored in object properties

require __DIR__ . '/Guards.php';

echo "== transactions ==\n";

function runCommitted(Ledger $ledger): void
{
    $tx = new Transaction($ledger, 'salary');
    $tx->record(5000);
    $tx->record(250);
    $tx->commit();
}

function runAbandoned(Ledger $ledger): void
{
    $tx = new Transaction($ledger, 'bonus');
    $tx->record(9999);
    // the caller forgot to commit - the guard rolls back on return
}

$ledger = new Ledger();
runCommitted($ledger);
runAbandoned($ledger);
echo "ledger balance: {$ledger->balance()}\n";

echo "== buffered writer ==\n";

function buildReport(array $lines): string
{
    $writer = new BufferedWriter();
    foreach ($lines as $line) {
        $writer->writeLine($line);
    }
    return $writer->snapshot();
}

$report = buildReport(['alpha', 'beta', 'gamma']);
echo "report: {$report}\n";

echo "== scope guards ==\n";

function withGuards(): void
{
    $outer = new ScopeGuard('outer', fn() => print("  (outer cleanup)\n"));
    echo "  outer work\n";
    innerGuarded();
    echo "  outer work done\n";
}

function innerGuarded(): void
{
    $inner = new ScopeGuard('inner', fn() => print("  (inner cleanup)\n"));
    echo "  inner work\n";
}

withGuards();

echo "== connection pool ==\n";

$pool = new ConnectionPool(2);

function queryWith(ConnectionPool $pool, string $tag): void
{
    $lease = $pool->acquire();
    echo "  {$tag} -> connection #{$lease->id()}, free now: {$pool->available()}\n";
}

echo "pool free at start: {$pool->available()}\n";
queryWith($pool, 'lookup');
echo "pool free after lookup: {$pool->available()}\n";
queryWith($pool, 'report');
echo "pool free after report: {$pool->available()}\n";

echo "== reassignment and unset ==\n";

$slot = new ScopeGuard('first', fn() => print("  (first done)\n"));
$slot = new ScopeGuard('second', fn() => print("  (second done)\n"));
echo "  slot reassigned\n";
unset($slot);
echo "  slot unset\n";

echo "== owned chain cascade ==\n";

function buildChain(): void
{
    $head = new Node('head');
    $head->chain(new Node('middle'))->chain(new Node('tail'));
    echo "  chain built\n";
}

buildChain();

echo "done\n";
