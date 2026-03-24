<?php
$server = new Swoole\Http\Server("0.0.0.0", 9501);
$server->set(['worker_num' => 4]);
$server->on("request", function ($request, $response) {
    $response->end("hello");
});
$server->start();
