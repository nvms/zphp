<?php
// covers: curl_init, curl_setopt, curl_setopt_array, curl_getinfo, curl_error,
//   curl_errno, curl_reset, curl_version, CURLOPT constants, CURLINFO constants,
//   classes, constructor property promotion, match expressions, enums,
//   named arguments, method chaining, json_encode

enum HttpMethod: string {
    case GET = 'GET';
    case POST = 'POST';
    case PUT = 'PUT';
    case DELETE = 'DELETE';
    case PATCH = 'PATCH';
}

class HttpRequest {
    private array $headers = [];
    private ?string $body = null;
    private int $timeout = 30;
    private bool $followRedirects = true;
    private int $maxRedirects = 5;
    private bool $verifySSL = true;

    public function __construct(
        private HttpMethod $method,
        private string $url
    ) {}

    public function withHeader(string $name, string $value): self {
        $this->headers[] = "$name: $value";
        return $this;
    }

    public function withBody(string $body): self {
        $this->body = $body;
        return $this;
    }

    public function withTimeout(int $seconds): self {
        $this->timeout = $seconds;
        return $this;
    }

    public function withRedirects(bool $follow, int $max = 5): self {
        $this->followRedirects = $follow;
        $this->maxRedirects = $max;
        return $this;
    }

    public function withSSLVerification(bool $verify): self {
        $this->verifySSL = $verify;
        return $this;
    }

    public function toCurl() {
        $ch = curl_init($this->url);

        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => $this->timeout,
            CURLOPT_FOLLOWLOCATION => $this->followRedirects,
            CURLOPT_MAXREDIRS => $this->maxRedirects,
            CURLOPT_SSL_VERIFYPEER => $this->verifySSL,
        ]);

        if ($this->method !== HttpMethod::GET) {
            curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $this->method->value);
        }

        if ($this->body !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, $this->body);
        }

        if (count($this->headers) > 0) {
            curl_setopt($ch, CURLOPT_HTTPHEADER, $this->headers);
        }

        return $ch;
    }

    public function describe(): string {
        $parts = [$this->method->value, $this->url];
        if ($this->body !== null) {
            $parts[] = "body=" . strlen($this->body) . "b";
        }
        $parts[] = "timeout=" . $this->timeout . "s";
        $parts[] = count($this->headers) . " headers";
        return implode(' | ', $parts);
    }
}

class RequestInspector {
    public static function inspect($ch): array {
        $info = curl_getinfo($ch);
        return [
            'url' => $info['url'] ?? '',
            'http_code' => $info['http_code'] ?? 0,
        ];
    }

    public static function report($ch): void {
        $info = self::inspect($ch);
        echo "  url: {$info['url']}\n";
        echo "  http_code: {$info['http_code']}\n";
        echo "  error: '" . curl_error($ch) . "'\n";
        echo "  errno: " . curl_errno($ch) . "\n";
    }
}

// build and inspect requests
echo "--- GET request ---\n";
$get = new HttpRequest(HttpMethod::GET, "https://api.example.com/users");
$get->withHeader("Accept", "application/json")
    ->withHeader("Authorization", "Bearer token123")
    ->withTimeout(10);
echo $get->describe() . "\n";

$ch = $get->toCurl();
RequestInspector::report($ch);

echo "\n--- POST request ---\n";
$payload = json_encode(['name' => 'test', 'email' => 'test@example.com']);
$post = new HttpRequest(HttpMethod::POST, "https://api.example.com/users");
$post->withHeader("Content-Type", "application/json")
     ->withBody($payload)
     ->withTimeout(15);
echo $post->describe() . "\n";

$ch2 = $post->toCurl();
RequestInspector::report($ch2);

echo "\n--- DELETE request ---\n";
$delete = new HttpRequest(HttpMethod::DELETE, "https://api.example.com/users/42");
$delete->withSSLVerification(false)
       ->withRedirects(false);
echo $delete->describe() . "\n";

$ch3 = $delete->toCurl();
RequestInspector::report($ch3);

// test curl_reset
echo "\n--- reset ---\n";
curl_reset($ch);
$info = curl_getinfo($ch);
echo "after reset url: '" . ($info['url'] ?? '') . "'\n";
echo "after reset error: '" . curl_error($ch) . "'\n";

// test version info
echo "\n--- version ---\n";
$ver = curl_version();
echo "has version: " . (isset($ver['version']) ? 'yes' : 'no') . "\n";
echo "has ssl: " . (isset($ver['ssl_version']) ? 'yes' : 'no') . "\n";

// test method routing with match
echo "\n--- method routing ---\n";
$methods = [HttpMethod::GET, HttpMethod::POST, HttpMethod::PUT, HttpMethod::DELETE, HttpMethod::PATCH];
foreach ($methods as $method) {
    $label = match($method) {
        HttpMethod::GET => 'read',
        HttpMethod::POST => 'create',
        HttpMethod::PUT => 'replace',
        HttpMethod::DELETE => 'remove',
        HttpMethod::PATCH => 'update',
    };
    echo "{$method->value}: $label\n";
}

echo "\ndone\n";
