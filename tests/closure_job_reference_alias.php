<?php
class Jobs {
    private $jobs = [];
    public function create() {
        $job = ['id' => 0, 'status' => 1];
        $resolver = static function ($resolve) use (&$job) { $job['resolve'] = $resolve; };
        $resolver(function () {});
        $callback = function () use (&$job) { echo json_encode(array_keys($job)), "\n"; };
        $this->jobs[$job['id']] = &$job;
        $this->start(0);
        $callback();
    }
    private function start($id) {
        $job = &$this->jobs[$id];
        $job['status'] = 2;
        $job['process'] = 'process';
    }
}
(new Jobs())->create();
$x = ['a' => 1];
$a = [];
$a[0] = &$x;
$b = &$a[0];
unset($a[0]);
$b['b'] = 2;
var_dump($x, $b);
