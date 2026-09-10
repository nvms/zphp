<?php
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
switch ($path) {
    case '/health': echo "ok"; break;
    case '/dirty': ini_set("memory_limit", "1G"); date_default_timezone_set("Asia/Tokyo"); echo ini_get("memory_limit"), "|", date_default_timezone_get(); break;
    case '/probe': echo ini_get("memory_limit"), "|", date_default_timezone_get(), "|", ini_get("app.name"); break;
    default: http_response_code(404); echo "nf";
}
