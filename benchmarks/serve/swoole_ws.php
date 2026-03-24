<?php
$server = new Swoole\WebSocket\Server("0.0.0.0", 9501);
$server->set(['worker_num' => 4]);
$server->on("open", function ($server, $request) {
    $server->push($request->fd, "welcome");
});
$server->on("message", function ($server, $frame) {
    $server->push($frame->fd, "echo: " . $frame->data);
});
$server->on("close", function ($server, $fd) {});
$server->start();
