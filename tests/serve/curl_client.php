<?php
$port = getenv('CURL_TEST_PORT') ?: 19876;
$base = "http://127.0.0.1:$port";

function test($name, $expected, $actual) {
    if ($expected === $actual) {
        echo "  pass  $name\n";
    } else {
        echo "  FAIL  $name\n";
        echo "    expected: $expected\n";
        echo "    got:      $actual\n";
    }
}

// GET with RETURNTRANSFER
$ch = curl_init("$base/health");
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
$body = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
$err = curl_errno($ch);
test("GET /health returns data", '{"status":"ok"}', $body);
test("GET /health status 200", 200, $code);
test("GET /health no error", 0, $err);

// GET with query params
$ch2 = curl_init("$base/echo?foo=bar&n=42");
curl_setopt($ch2, CURLOPT_RETURNTRANSFER, true);
$body = curl_exec($ch2);
$data = json_decode($body, true);
test("GET /echo method", "GET", $data['method']);
test("GET /echo query foo", "bar", $data['get']['foo']);
test("GET /echo query n", "42", $data['get']['n']);

// POST with fields
$ch3 = curl_init("$base/echo");
curl_setopt_array($ch3, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST => true,
    CURLOPT_POSTFIELDS => "key=value&other=test",
]);
$body = curl_exec($ch3);
$data = json_decode($body, true);
test("POST /echo method", "POST", $data['method']);
test("POST /echo field key", "value", $data['post']['key']);
test("POST /echo field other", "test", $data['post']['other']);

// custom headers
$ch4 = curl_init("$base/echo");
curl_setopt($ch4, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch4, CURLOPT_HTTPHEADER, [
    "X-Test: hello",
    "Accept: application/json",
]);
$body = curl_exec($ch4);
test("GET with headers succeeds", 0, curl_errno($ch4));

// response status code
$ch5 = curl_init("$base/status");
curl_setopt($ch5, CURLOPT_RETURNTRANSFER, true);
$body = curl_exec($ch5);
$code = curl_getinfo($ch5, CURLINFO_RESPONSE_CODE);
test("GET /status code 201", 201, $code);
test("GET /status body", '{"created":true}', $body);

// curl_getinfo all
$info = curl_getinfo($ch5);
test("getinfo has url", true, isset($info['url']));
test("getinfo has http_code", true, isset($info['http_code']));
test("getinfo http_code matches", 201, $info['http_code']);
test("getinfo has total_time", true, isset($info['total_time']));
test("getinfo total_time > 0", true, $info['total_time'] > 0);

// error handling - connection refused
$ch6 = curl_init("http://localhost:1/nope");
curl_setopt($ch6, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch6, CURLOPT_TIMEOUT, 1);
$result = curl_exec($ch6);
test("connection refused returns false", false, $result);
test("connection refused has errno", true, curl_errno($ch6) > 0);
test("connection refused has error", true, strlen(curl_error($ch6)) > 0);

// JSON POST
$ch7 = curl_init("$base/echo");
$json = json_encode(["name" => "test", "count" => 3]);
curl_setopt_array($ch7, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST => true,
    CURLOPT_POSTFIELDS => $json,
    CURLOPT_HTTPHEADER => ["Content-Type: application/json"],
]);
$body = curl_exec($ch7);
test("JSON POST succeeds", 0, curl_errno($ch7));
test("JSON POST status 200", 200, curl_getinfo($ch7, CURLINFO_RESPONSE_CODE));

// custom method
$ch8 = curl_init("$base/echo");
curl_setopt_array($ch8, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_CUSTOMREQUEST => "DELETE",
]);
$body = curl_exec($ch8);
$data = json_decode($body, true);
test("DELETE method", "DELETE", $data['method']);

// file_get_contents with HTTP URL
$fgc = file_get_contents("$base/health");
test("fgc http body", '{"status":"ok"}', $fgc);
test("fgc http type", "string", gettype($fgc));

// http_get_last_response_headers with successful request
$fgc_headers_body = file_get_contents("$base/headers");
$hdrs = http_get_last_response_headers();
test("http_get_last_response_headers is array after request", true, is_array($hdrs));
test("http_get_last_response_headers status 200", true, isset($hdrs[0]) && str_contains($hdrs[0], "200"));
test("http_get_last_response_headers contains custom header", true, in_array("X-Custom: hello", $hdrs, true) || in_array("x-custom: hello", $hdrs, true) || str_contains(implode("\n", $hdrs), "X-Custom: hello"));

// http_clear_last_response_headers after real request
http_clear_last_response_headers();
test("http_clear_last_response_headers clears headers", null, http_get_last_response_headers());

// http_get_last_response_headers with 404 response
$fgc_404 = @file_get_contents("$base/nonexistent");
$hdrs_404 = http_get_last_response_headers();
test("http_get_last_response_headers on 404 is array", true, is_array($hdrs_404));
test("http_get_last_response_headers on 404 status", true, isset($hdrs_404[0]) && str_contains($hdrs_404[0], "404"));

// http_get_last_response_headers with redirect chain (302 -> 200)
$fgc_redir = file_get_contents("$base/redirect");
$hdrs_redir = http_get_last_response_headers();
test("http_get_last_response_headers on redirect is array", true, is_array($hdrs_redir));
$redir_str = implode("\n", $hdrs_redir ?: []);
test("http_get_last_response_headers contains 302", true, str_contains($redir_str, "302"));
test("http_get_last_response_headers contains final 200", true, str_contains($redir_str, "200"));

// http_get_last_response_headers trailing whitespace handling
$fgc_ws = file_get_contents("$base/header-trailing-space");
$hdrs_ws = http_get_last_response_headers();
test("http_get_last_response_headers trailing space stripped", true, in_array("X-Trailing-Space: hello", $hdrs_ws ?: [], true));
test("http_get_last_response_headers trailing tab and space stripped", true, in_array("X-Tab-Space: world", $hdrs_ws ?: [], true));
test("http_get_last_response_headers empty value with spaces stripped", true, in_array("X-Empty-Value:", $hdrs_ws ?: [], true));
test("http_get_last_response_headers status line preserved", true, isset($hdrs_ws[0]) && str_starts_with($hdrs_ws[0], "HTTP/"));

// file_get_contents with bad URL resets headers to null
$fgc_bad = @file_get_contents("http://127.0.0.1:1/nope");
test("fgc bad returns false", false, $fgc_bad);
test("http_get_last_response_headers on failed request is null", null, http_get_last_response_headers());

// http_get_last_response_headers preserved on failed transfer after headers received
$fail_port = getenv('CURL_FAIL_PORT');
if ($fail_port) {
    http_clear_last_response_headers();
    $fgc_fail = @file_get_contents("http://127.0.0.1:$fail_port");
    // php's http wrapper doesn't hold the body to Content-Length: what arrived is the result
    test("fgc on a short body returns what arrived", "partial", $fgc_fail);
    $hdrs_fail = http_get_last_response_headers();
    test("http_get_last_response_headers preserved on failed transfer", true, is_array($hdrs_fail));
    test("http_get_last_response_headers contains header from failed transfer", true, in_array("X-Transfer-Fail: true", $hdrs_fail ?: [], true));
    test("status line trailing whitespace preserved exact", "HTTP/1.1 200 OK   ", $hdrs_fail[0] ?? "");
    test("100 Continue discarded from headers", false, in_array("HTTP/1.1 100 Continue", $hdrs_fail ?: [], true));
    test("1xx intermediate headers discarded", false, in_array("X-100-Ignore: true", $hdrs_fail ?: [], true));

    // copy-on-write / isolation test: modifying returned array does not mutate internal VM state
    $copy = $hdrs_fail;
    $copy[0] = "MODIFIED_STATUS_LINE";
    $hdrs_second = http_get_last_response_headers();
    test("http_get_last_response_headers array isolation (COW)", "HTTP/1.1 200 OK   ", $hdrs_second[0] ?? "");
}

echo "done\n";

