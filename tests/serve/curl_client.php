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

echo "done\n";
