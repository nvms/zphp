<?php
header("Content-Type: application/json");

$method = $_SERVER["REQUEST_METHOD"];
$path = $_SERVER["SCRIPT_NAME"];

if ($path === "/health") {
    echo json_encode(["status" => "ok"]);
} elseif ($path === "/echo") {
    echo json_encode([
        "method" => $method,
        "get" => $_GET,
        "post" => $_POST,
        "uri" => $_SERVER["REQUEST_URI"],
    ]);
} elseif ($path === "/headers") {
    header("X-Custom: hello");
    header("X-Another: world");
    echo json_encode(["ok" => true]);
} elseif ($path === "/status") {
    http_response_code(201);
    echo json_encode(["created" => true]);
} elseif ($path === "/html") {
    header("Content-Type: text/html");
    echo "<h1>Hello</h1>";
} elseif ($path === "/upload") {
    $file_info = [];
    foreach ($_FILES as $key => $f) {
        $file_info[$key] = [
            "name" => $f["name"],
            "type" => $f["type"],
            "size" => $f["size"],
            "error" => $f["error"],
            "has_tmp" => strlen($f["tmp_name"]) > 0,
        ];
    }
    echo json_encode([
        "post" => $_POST,
        "files" => $file_info,
    ]);
} elseif ($path === "/json-api") {
    $raw = file_get_contents("php://input");
    $data = json_decode($raw, true);
    echo json_encode([
        "raw_length" => strlen($raw),
        "parsed" => $data,
    ]);
} elseif ($path === "/session-set") {
    session_start();
    $_SESSION["user"] = $_GET["user"] ?? "anonymous";
    $_SESSION["count"] = ($_SESSION["count"] ?? 0) + 1;
    echo json_encode([
        "id" => session_id(),
        "user" => $_SESSION["user"],
        "count" => $_SESSION["count"],
    ]);
} elseif ($path === "/session-get") {
    session_start();
    echo json_encode([
        "id" => session_id(),
        "user" => $_SESSION["user"] ?? null,
        "count" => $_SESSION["count"] ?? 0,
    ]);
} elseif ($path === "/session-destroy") {
    session_start();
    session_destroy();
    echo json_encode(["destroyed" => true]);
} else {
    http_response_code(404);
    echo json_encode(["error" => "not found", "path" => $path]);
}
