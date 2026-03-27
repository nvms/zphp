<?php

$path = $_SERVER["SCRIPT_NAME"] ?? "/";

if ($path === "/health") {
    echo "ok";
    return;
}

http_response_code(404);
echo "not found";

function ws_onOpen($conn) {
    $conn->send("welcome");
}

function ws_onMessage($conn, $msg) {
    if ($msg === "ping") {
        $conn->send("pong");
    } elseif ($msg === "echo") {
        $conn->send("echo:" . $msg);
    } else {
        $conn->send("got:" . $msg);
    }
}

function ws_onClose($conn) {
}
