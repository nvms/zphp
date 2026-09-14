<?php
function square(int $n): int { return $n * $n; }
function boom(string $m): never { throw new InvalidArgumentException($m, 7); }
function slow(int $ms): string { usleep($ms * 1000); return "slept $ms"; }
function who(): array { return ['task' => Zphp\Task::id(), 'worker' => Zphp\Task::worker()]; }
class Jobs { public static function sum(array $xs): int { return array_sum($xs); } }
$GLOBALS['bootstrapped'] = true;
class WorkerOnly extends RuntimeException {}
function throw_local(): never { throw new WorkerOnly("only the worker knows this class"); }
function spin(int $iterations): int { $x = 0; for ($i = 0; $i < $iterations; $i++) { $x = ($x * 31 + $i) % 1000003; } return $x; }
function until_cancelled(): string { while (!Zphp\Task::cancelled()) usleep(1000); return "stopped"; }
function counter(): int { static $n = 0; return ++$n; }
function big(int $n): array { return array_fill(0, $n, str_repeat("x", 64)); }
function echoes(string $s): void { echo $s, "\n"; }
function consume(Zphp\Channel $jobs, Zphp\Channel $results): int {
    $n = 0;
    foreach ($jobs as $job) { $results->send(['job' => $job, 'worker' => Zphp\Task::worker(), 'sq' => $job * $job]); $n++; }
    return $n;
}
function produce(Zphp\Channel $out, int $count): string {
    for ($i = 1; $i <= $count; $i++) $out->send($i);
    $out->close();
    return "produced $count";
}
function wait_recv(Zphp\Channel $ch, float $t): string {
    try { return "got " . $ch->recv($t); } catch (Zphp\TimeoutException $e) { return "timeout"; } catch (Zphp\ChannelException $e) { return "closed"; }
}
function make_channel(): array { $c = new Zphp\Channel(3); $c->send("hello from worker"); return ['ch' => $c]; }
function slow_drain(Zphp\Channel $ch): int { $n = 0; foreach ($ch as $v) { usleep(20000); $n++; } return $n; }
function forward(Zphp\Channel $in, Zphp\Channel $out): void { foreach ($in as $v) $out->send($v); $out->close(); }
function bad_result(): Closure { return fn() => 1; }
function produce_big(Zphp\Channel $out, int $n): void { for ($i = 0; $i < $n; $i++) $out->send(big(100)); }
class Counter {
    public function __construct(public int $base = 0) {}
    public function bump(int $n): int { return $this->base + $n; }
    private function secret(): string { return "secret " . $this->base; }
}
class Maker { public function __construct(private int $k) {} public function job(): Closure { return function (int $x) { return $x * $this->k; }; } }
function helper(int $x): int { return $x * 3; }
