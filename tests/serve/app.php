<?php
header("Content-Type: application/json");

$method = $_SERVER["REQUEST_METHOD"];
$path = parse_url($_SERVER["REQUEST_URI"], PHP_URL_PATH);

if ($path === "/health") {
    echo json_encode(["status" => "ok"]);
} elseif ($path === "/echo") {
    echo json_encode([
        "method" => $method,
        "get" => $_GET,
        "post" => $_POST,
        "uri" => $_SERVER["REQUEST_URI"],
    ], JSON_UNESCAPED_SLASHES);
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
} elseif ($path === "/header-replace") {
    header("X-Test: first");
    header("X-Test: second");
    echo "replaced";
} elseif ($path === "/header-no-replace") {
    header("X-Multi: one");
    header("X-Multi: two", false);
    echo "appended";
} elseif ($path === "/header-remove") {
    header("X-Keep: yes");
    header("X-Drop: no");
    header_remove("X-Drop");
    echo "removed";
} elseif ($path === "/header-remove-all") {
    header("X-A: 1");
    header("X-B: 2");
    header_remove();
    echo "cleared";
} elseif ($path === "/header-list") {
    header("X-Foo: bar");
    header("X-Baz: qux");
    echo json_encode(headers_list());
} elseif ($path === "/header-status") {
    header("X-Info: test", true, 202);
    echo "accepted";
} elseif ($path === "/header-from-function") {
    function setHeaders() {
        header("X-From-Func: yes");
        http_response_code(203);
    }
    setHeaders();
    echo "from-func";
} elseif ($path === "/redirect") {
    header("Location: /headers", true, 302);
    echo "redirecting";
} elseif ($path === "/isolation/dirty") {
    // touch every kind of request-scoped state; /isolation/probe must not see any of it
    function isolation_counter() { static $n = 0; return ++$n; }
    $GLOBALS["leak"] = "leaked-global";
    $_ENV["LEAK"] = "x";
    isolation_counter();
    header("X-Leak: yes");
    http_response_code(201);
    ob_start();
    echo "buffered";
    set_error_handler(fn() => true);
    set_exception_handler(fn($e) => null);
    register_shutdown_function(fn() => null);
    spl_autoload_register(fn($c) => null);
    ini_set("precision", 5);
    ini_set("memory_limit", "1M");
    error_reporting(0);
    date_default_timezone_set("Asia/Tokyo");
    mb_internal_encoding("ISO-8859-1");
    define("LEAKCONST", 1);
    class LeakClass {}
    function leak_fn() {}
    session_start();
    $_SESSION["leak"] = "session";
    srand(42);
    umask(0077);
    strtok("a,b,c", ",");
    @trigger_error("leaked warning", E_USER_WARNING);
    date_parse("not a date");
    ob_end_clean();
    echo "dirty";
} elseif ($path === "/isolation/probe") {
    function isolation_counter() { static $n = 0; return ++$n; }
    echo json_encode([
        "global" => $GLOBALS["leak"] ?? null,
        "env" => $_ENV["LEAK"] ?? null,
        "static" => isolation_counter(),
        "headers" => headers_list(),
        "status" => http_response_code(),
        "ob_level" => ob_get_level(),
        "error_handler" => set_error_handler(null),
        "exception_handler" => set_exception_handler(null),
        "autoloaders" => count(spl_autoload_functions()),
        "precision" => ini_get("precision"),
        "memory_limit" => ini_get("memory_limit"),
        "error_reporting" => error_reporting(),
        "tz" => date_default_timezone_get(),
        "mb" => mb_internal_encoding(),
        "const" => defined("LEAKCONST"),
        "class" => class_exists("LeakClass", false),
        "fn" => function_exists("leak_fn"),
        "session_status" => session_status(),
        "session" => $_SESSION["leak"] ?? null,
        "umask" => umask(),
        "strtok" => strtok(","),
        "last_error" => error_get_last(),
        "dt_errors" => DateTime::getLastErrors(),
    ]);
} elseif ($path === "/header-trailing-space") {
    header("X-Trailing-Space: hello    ");
    header("X-Tab-Space: world\t  ");
    header("X-Empty-Value:   ");
    echo "whitespace-test";
} else {
    http_response_code(404);
    echo json_encode(["error" => "not found", "path" => $path]);
}
