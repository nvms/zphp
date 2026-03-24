<?php
// covers: closures with use binding, method chaining (return $this),
//   callable dispatch, global variables, null coalescing (??),
//   closure pipeline pattern, string interpolation

class Request
{
    public array $headers = [];
    public string $method;
    public string $path;
    public string $body;

    public function __construct(string $method, string $path, string $body = "")
    {
        $this->method = $method;
        $this->path = $path;
        $this->body = $body;
    }

    public function setHeader(string $key, string $value): void
    {
        $this->headers[$key] = $value;
    }

    public function getHeader(string $key): ?string
    {
        return $this->headers[$key] ?? null;
    }
}

class Response
{
    public int $status = 200;
    public string $body = "";
    public array $headers = [];

    public function setStatus(int $code): self
    {
        $this->status = $code;
        return $this;
    }

    public function setBody(string $body): self
    {
        $this->body = $body;
        return $this;
    }

    public function setHeader(string $key, string $value): self
    {
        $this->headers[$key] = $value;
        return $this;
    }
}

class Pipeline
{
    private array $middleware = [];

    public function pipe(callable $middleware): self
    {
        $this->middleware[] = $middleware;
        return $this;
    }

    public function handle(Request $request, callable $final): Response
    {
        $stack = $final;

        for ($i = count($this->middleware) - 1; $i >= 0; $i--) {
            $mw = $this->middleware[$i];
            $next = $stack;
            $stack = function (Request $req) use ($mw, $next) {
                return $mw($req, $next);
            };
        }

        return $stack($request);
    }
}

// middleware: add request ID
function addRequestId(Request $req, callable $next): Response
{
    $req->setHeader("X-Request-ID", "req-12345");
    $response = $next($req);
    $response->setHeader("X-Request-ID", "req-12345");
    return $response;
}

// middleware: log
$log = [];
function logMiddleware(Request $req, callable $next): Response
{
    global $log;
    $log[] = "before: " . $req->method . " " . $req->path;
    $response = $next($req);
    $log[] = "after: status " . $response->status;
    return $response;
}

// middleware: auth check
function authMiddleware(Request $req, callable $next): Response
{
    $token = $req->getHeader("Authorization");
    if ($token === null) {
        $resp = new Response();
        return $resp->setStatus(401)->setBody("Unauthorized");
    }
    return $next($req);
}

// final handler
function handler(Request $req): Response
{
    $resp = new Response();
    return $resp->setStatus(200)->setBody("Hello from " . $req->path);
}

// test 1: request with auth
$pipeline = new Pipeline();
$pipeline->pipe("addRequestId")
         ->pipe("logMiddleware")
         ->pipe("authMiddleware");

$req1 = new Request("GET", "/api/users");
$req1->setHeader("Authorization", "Bearer abc123");

$resp1 = $pipeline->handle($req1, "handler");
echo "status: " . $resp1->status . "\n";
echo "body: " . $resp1->body . "\n";
echo "request-id: " . $resp1->headers["X-Request-ID"] . "\n";

// test 2: request without auth (should be blocked)
$req2 = new Request("GET", "/api/secret");

$resp2 = $pipeline->handle($req2, "handler");
echo "status: " . $resp2->status . "\n";
echo "body: " . $resp2->body . "\n";

// log output
foreach ($log as $entry) {
    echo "log: " . $entry . "\n";
}

echo "done\n";
