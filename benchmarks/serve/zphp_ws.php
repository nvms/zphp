<?php

function ws_onOpen($ws) {
    $ws->send("welcome");
}

function ws_onMessage($ws, $data) {
    $ws->send("echo: " . $data);
}

function ws_onClose($ws) {}
