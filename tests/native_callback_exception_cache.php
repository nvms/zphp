<?php
// Repeat the same native method call site: the second call uses the method IC.
// Both callbacks that return before a later callback throws and immediate
// throws must reach the caller's catch without consuming an outer handler.
error_reporting(E_ALL & ~E_DEPRECATED);
function callbackQuery($db) {
    return $db->query('SELECT callback_fail(1)');
}
function checkCallbackCatch($db, $nested) {
    try {
        if ($nested) callbackQuery($db);
        else $db->query('SELECT callback_fail(1)');
        echo "lost exception\n";
    } catch (RuntimeException $e) {
        echo $e->getMessage(), "\n";
    } finally {
        echo "finally\n";
    }
    echo $db->query('SELECT 42')->fetchColumn(), "\n";
}
foreach (['step', 'final'] as $phase) {
    $db = new PDO('sqlite::memory:');
    $db->sqliteCreateAggregate('callback_fail',
        $phase === 'step' ? function ($c, $n, $v) { throw new RuntimeException('step'); } : fn($c, $n, $v) => $v,
        $phase === 'final' ? function ($c, $n) { throw new RuntimeException('final'); } : fn($c, $n) => $c, 1);
    foreach ([false, true] as $nested) {
        for ($i = 0; $i < 3; $i++) {
            try {
                checkCallbackCatch($db, $nested);
            } catch (Throwable $e) {
                echo "wrong outer catch\n";
            }
        }
    }
}
echo "done\n";
