<?php
// Clean calls the handler too; START is used only on its first invocation.
$events = [];
ob_start(function ($s, $phase) use (&$events) {
    $events[] = [$s, $phase, ob_get_level(), ob_get_contents()];
    return strtoupper($s);
});
echo 'discard'; ob_clean();
echo 'flush'; ob_flush();
echo 'final'; $raw = ob_get_flush();
echo "\n", $raw, "\n", json_encode($events), "\n";
foreach (['ob_end_clean', 'ob_get_clean', 'ob_end_flush', 'ob_get_flush'] as $op) {
    ob_start(function ($s, $phase) use (&$events) {
        $events[] = [$s, $phase];
        return 'converted';
    });
    echo 'original';
    $result = $op();
    echo $op, ':', json_encode($result), "\n";
}
echo json_encode($events), "\n";
foreach ([false, null, true, 42, ''] as $result) {
    ob_start(function ($s, $phase) use ($result) { return $result; });
    echo 'raw'; ob_end_flush(); echo "|\n";
}
// A disabled handler passes later writes through even across clean operations.
$calls = 0;
ob_start(function ($s, $phase) use (&$calls) { ++$calls; return false; });
echo 'a'; ob_flush(); echo 'b';
var_dump(ob_get_contents(), ob_get_length());
ob_clean(); echo 'c'; ob_end_clean(); echo ':', $calls, "\n";
// Handler and retained input must outlive the original callable/buffer storage.
class OutputHandlerOwner {
    public $saved = '';
    public function __invoke($s, $phase) { $this->saved = $s; return $s; }
    public function __destruct() { echo 'released:', $this->saved, "\n"; }
}
$handler = new OutputHandlerOwner();
ob_start($handler);
unset($handler);
echo 'owned'; ob_clean();
echo 'last'; ob_end_clean();
