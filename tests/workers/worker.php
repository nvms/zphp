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
