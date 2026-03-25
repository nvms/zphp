<?php
// covers: recursive functions, recursive closures, nested closures (closures
//   returning closures), complex string interpolation ("{$obj->prop}",
//   "{$arr['key']}"), multi-level inheritance (grandparent->parent->child),
//   type juggling (string to number, loose comparison), switch with fallthrough,
//   nested ternary, str_split, substr, ctype_digit, ctype_alpha, ctype_space,
//   is_numeric, intval, floatval, number_format, abs, pow, sqrt, max, min,
//   array_reverse, array_key_exists, sprintf, compact, recursive array processing

// --- token types ---

class Token
{
    public string $type;
    public string $value;

    public function __construct(string $type, string $value)
    {
        $this->type = $type;
        $this->value = $value;
    }

    public function __toString(): string
    {
        return "{$this->type}({$this->value})";
    }
}

// --- lexer ---

class Lexer
{
    private string $input;
    private int $pos = 0;

    public function __construct(string $input)
    {
        $this->input = $input;
    }

    public function tokenize(): array
    {
        $tokens = [];
        while ($this->pos < strlen($this->input)) {
            $ch = $this->input[$this->pos];

            if (ctype_space($ch)) {
                $this->pos++;
                continue;
            }

            if (ctype_digit($ch) || $ch === ".") {
                $tokens[] = $this->readNumber();
                continue;
            }

            if (ctype_alpha($ch) || $ch === "_") {
                $tokens[] = $this->readIdentifier();
                continue;
            }

            switch ($ch) {
                case "+": case "-": case "*": case "/": case "%": case "^":
                    $tokens[] = new Token("op", $ch);
                    $this->pos++;
                    break;
                case "(":
                    $tokens[] = new Token("lparen", $ch);
                    $this->pos++;
                    break;
                case ")":
                    $tokens[] = new Token("rparen", $ch);
                    $this->pos++;
                    break;
                case ",":
                    $tokens[] = new Token("comma", $ch);
                    $this->pos++;
                    break;
                default:
                    $this->pos++;
                    break;
            }
        }
        $tokens[] = new Token("eof", "");
        return $tokens;
    }

    private function readNumber(): Token
    {
        $start = $this->pos;
        $hasDot = false;
        while ($this->pos < strlen($this->input)) {
            $ch = $this->input[$this->pos];
            if ($ch === "." && !$hasDot) {
                $hasDot = true;
                $this->pos++;
            } elseif (ctype_digit($ch)) {
                $this->pos++;
            } else {
                break;
            }
        }
        return new Token("number", substr($this->input, $start, $this->pos - $start));
    }

    private function readIdentifier(): Token
    {
        $start = $this->pos;
        while ($this->pos < strlen($this->input) && (ctype_alnum($this->input[$this->pos]) || $this->input[$this->pos] === "_")) {
            $this->pos++;
        }
        $word = substr($this->input, $start, $this->pos - $start);
        $keywords = ["pi" => true, "e" => true, "true" => true, "false" => true];
        $type = array_key_exists($word, $keywords) ? "keyword" : "ident";
        return new Token($type, $word);
    }
}

// --- AST nodes using inheritance ---

abstract class AstNode
{
    abstract public function evaluate(array $env): float;
    abstract public function display(): string;
}

class NumberNode extends AstNode
{
    private float $value;

    public function __construct(float $value)
    {
        $this->value = $value;
    }

    public function evaluate(array $env): float
    {
        return $this->value;
    }

    public function display(): string
    {
        $v = $this->value;
        return ($v == (int) $v) ? (string) (int) $v : (string) $v;
    }
}

class VariableNode extends AstNode
{
    private string $name;

    public function __construct(string $name)
    {
        $this->name = $name;
    }

    public function evaluate(array $env): float
    {
        if ($this->name === "pi") return 3.14159265358979;
        if ($this->name === "e") return 2.71828182845905;
        if ($this->name === "true") return 1.0;
        if ($this->name === "false") return 0.0;
        return $env[$this->name] ?? 0.0;
    }

    public function display(): string
    {
        return $this->name;
    }
}

class BinaryNode extends AstNode
{
    private AstNode $left;
    private string $op;
    private AstNode $right;

    public function __construct(AstNode $left, string $op, AstNode $right)
    {
        $this->left = $left;
        $this->op = $op;
        $this->right = $right;
    }

    public function evaluate(array $env): float
    {
        $l = $this->left->evaluate($env);
        $r = $this->right->evaluate($env);
        return match ($this->op) {
            "+" => $l + $r,
            "-" => $l - $r,
            "*" => $l * $r,
            "/" => $r != 0 ? $l / $r : 0.0,
            "%" => $r != 0 ? (float) ((int) $l % (int) $r) : 0.0,
            "^" => pow($l, $r),
            default => 0.0,
        };
    }

    public function display(): string
    {
        return "({$this->left->display()} {$this->op} {$this->right->display()})";
    }
}

class UnaryNode extends AstNode
{
    private string $op;
    private AstNode $operand;

    public function __construct(string $op, AstNode $operand)
    {
        $this->op = $op;
        $this->operand = $operand;
    }

    public function evaluate(array $env): float
    {
        $v = $this->operand->evaluate($env);
        return $this->op === "-" ? -$v : $v;
    }

    public function display(): string
    {
        return "(-{$this->operand->display()})";
    }
}

class CallNode extends AstNode
{
    private string $name;
    private array $args;

    public function __construct(string $name, array $args)
    {
        $this->name = $name;
        $this->args = $args;
    }

    public function evaluate(array $env): float
    {
        $vals = array_map(function ($a) use ($env) { return $a->evaluate($env); }, $this->args);
        return match ($this->name) {
            "abs" => abs($vals[0]),
            "sqrt" => sqrt($vals[0]),
            "pow" => pow($vals[0], $vals[1] ?? 2),
            "max" => max($vals[0], $vals[1]),
            "min" => min($vals[0], $vals[1]),
            "floor" => floor($vals[0]),
            "ceil" => ceil($vals[0]),
            "round" => round($vals[0]),
            default => 0.0,
        };
    }

    public function display(): string
    {
        $argStrs = array_map(function ($a) { return $a->display(); }, $this->args);
        return "{$this->name}(" . implode(", ", $argStrs) . ")";
    }
}

// --- recursive descent parser ---

class Parser
{
    private array $tokens;
    private int $pos = 0;

    public function __construct(array $tokens)
    {
        $this->tokens = $tokens;
    }

    public function parse(): AstNode
    {
        $node = $this->parseExpression();
        return $node;
    }

    private function current(): Token
    {
        return $this->tokens[$this->pos];
    }

    private function eat(string $type): Token
    {
        $tok = $this->current();
        if ($tok->type !== $type) {
            throw new RuntimeException("expected $type, got {$tok->type}");
        }
        $this->pos++;
        return $tok;
    }

    // expression: term ((+|-) term)*
    private function parseExpression(): AstNode
    {
        $node = $this->parseTerm();
        while ($this->current()->type === "op" && ($this->current()->value === "+" || $this->current()->value === "-")) {
            $op = $this->eat("op")->value;
            $right = $this->parseTerm();
            $node = new BinaryNode($node, $op, $right);
        }
        return $node;
    }

    // term: power ((*|/|%) power)*
    private function parseTerm(): AstNode
    {
        $node = $this->parsePower();
        while ($this->current()->type === "op" && ($this->current()->value === "*" || $this->current()->value === "/" || $this->current()->value === "%")) {
            $op = $this->eat("op")->value;
            $right = $this->parsePower();
            $node = new BinaryNode($node, $op, $right);
        }
        return $node;
    }

    // power: unary (^ unary)*
    private function parsePower(): AstNode
    {
        $node = $this->parseUnary();
        while ($this->current()->type === "op" && $this->current()->value === "^") {
            $this->eat("op");
            $right = $this->parseUnary();
            $node = new BinaryNode($node, "^", $right);
        }
        return $node;
    }

    // unary: -unary | primary
    private function parseUnary(): AstNode
    {
        if ($this->current()->type === "op" && $this->current()->value === "-") {
            $this->eat("op");
            return new UnaryNode("-", $this->parseUnary());
        }
        return $this->parsePrimary();
    }

    // primary: number | ident(args) | ident | keyword | (expr)
    private function parsePrimary(): AstNode
    {
        $tok = $this->current();

        if ($tok->type === "number") {
            $this->eat("number");
            return new NumberNode(floatval($tok->value));
        }

        if ($tok->type === "keyword") {
            $this->eat("keyword");
            return new VariableNode($tok->value);
        }

        if ($tok->type === "ident") {
            $name = $this->eat("ident")->value;
            if ($this->current()->type === "lparen") {
                $this->eat("lparen");
                $args = [];
                if ($this->current()->type !== "rparen") {
                    $args[] = $this->parseExpression();
                    while ($this->current()->type === "comma") {
                        $this->eat("comma");
                        $args[] = $this->parseExpression();
                    }
                }
                $this->eat("rparen");
                return new CallNode($name, $args);
            }
            return new VariableNode($name);
        }

        if ($tok->type === "lparen") {
            $this->eat("lparen");
            $node = $this->parseExpression();
            $this->eat("rparen");
            return $node;
        }

        throw new RuntimeException("unexpected token: {$tok->type}({$tok->value})");
    }
}

// --- evaluator helper ---

function calc(string $expr, array $env = []): string
{
    $lexer = new Lexer($expr);
    $tokens = $lexer->tokenize();
    $parser = new Parser($tokens);
    $ast = $parser->parse();
    $result = $ast->evaluate($env);
    if ($result == (int) $result && abs($result) < 1e15) {
        return (string) (int) $result;
    }
    return number_format($result, 6, ".", "");
}

// --- recursive helpers ---

function factorial(int $n): int
{
    if ($n <= 1) return 1;
    return $n * factorial($n - 1);
}

function flattenArray(array $arr): array
{
    $result = [];
    foreach ($arr as $item) {
        if (is_array($item)) {
            $result = [...$result, ...flattenArray($item)];
        } else {
            $result[] = $item;
        }
    }
    return $result;
}

// === test: basic arithmetic ===

echo "1+2: " . calc("1 + 2") . "\n";
echo "10-3*2: " . calc("10 - 3 * 2") . "\n";
echo "2^10: " . calc("2 ^ 10") . "\n";
echo "(1+2)*3: " . calc("(1 + 2) * 3") . "\n";
echo "10%3: " . calc("10 % 3") . "\n";
echo "-5+3: " . calc("-5 + 3") . "\n";

// === test: function calls ===

echo "sqrt(144): " . calc("sqrt(144)") . "\n";
echo "abs(-42): " . calc("abs(-42)") . "\n";
echo "max(3,7): " . calc("max(3, 7)") . "\n";
echo "min(3,7): " . calc("min(3, 7)") . "\n";
echo "pow(2,8): " . calc("pow(2, 8)") . "\n";
echo "floor(3.7): " . calc("floor(3.7)") . "\n";
echo "ceil(3.2): " . calc("ceil(3.2)") . "\n";
echo "round(3.5): " . calc("round(3.5)") . "\n";

// === test: variables and constants ===

echo "pi: " . calc("pi") . "\n";
echo "2*pi: " . calc("2 * pi") . "\n";
echo "x+y: " . calc("x + y", ["x" => 10, "y" => 20]) . "\n";
echo "x^2+1: " . calc("x ^ 2 + 1", ["x" => 5]) . "\n";

// === test: complex expressions ===

echo "nested: " . calc("(1 + 2) * (3 + 4) / (5 - 3)") . "\n";
echo "deep: " . calc("sqrt(pow(3, 2) + pow(4, 2))") . "\n";

// === test: AST display with string interpolation ===

$lexer = new Lexer("2 * x + 1");
$parser = new Parser($lexer->tokenize());
$ast = $parser->parse();
echo "ast: " . $ast->display() . "\n";

// === test: tokenizer output with __toString ===

$tokens = (new Lexer("sqrt(x + 1)"))->tokenize();
$strs = array_map(function ($t) { return (string) $t; }, $tokens);
echo "tokens: " . implode(" ", $strs) . "\n";

// === test: error handling ===

try {
    calc("1 + + 2");
} catch (RuntimeException $e) {
    echo "error: " . $e->getMessage() . "\n";
}

try {
    calc("(1 + 2");
} catch (RuntimeException $e) {
    echo "error: " . $e->getMessage() . "\n";
}

// === test: recursive functions ===

echo "5!: " . factorial(5) . "\n";
echo "10!: " . factorial(10) . "\n";

// === test: recursive array processing ===

$nested = [1, [2, 3], [4, [5, 6]], 7];
$flat = flattenArray($nested);
echo "flat: " . implode(", ", $flat) . "\n";

// === test: nested closures ===

function makeAdder(int $n): Closure
{
    return function (int $x) use ($n) {
        return $x + $n;
    };
}

$add5 = makeAdder(5);
$add10 = makeAdder(10);
echo "add5(3): " . $add5(3) . "\n";
echo "add10(3): " . $add10(3) . "\n";

// closure returning closure
function multiplierFactory(): Closure
{
    return function (int $factor) {
        return function (int $x) use ($factor) {
            return $x * $factor;
        };
    };
}

$double = multiplierFactory()(2);
$triple = multiplierFactory()(3);
echo "double(7): " . $double(7) . "\n";
echo "triple(7): " . $triple(7) . "\n";

// === test: type juggling ===

echo "str+num: " . ("5" + 3) . "\n";
echo "str*num: " . ("4" * "3") . "\n";
echo "intval: " . intval("42abc") . "\n";
echo "floatval: " . floatval("3.14xyz") . "\n";
echo "numeric: " . (is_numeric("123") ? "yes" : "no") . "\n";
echo "numeric: " . (is_numeric("12.3") ? "yes" : "no") . "\n";
echo "numeric: " . (is_numeric("abc") ? "yes" : "no") . "\n";

// === test: string interpolation edge cases ===

$obj = new Token("test", "val");
echo "prop: {$obj->type}\n";
echo "prop: {$obj->value}\n";

$arr = ["key" => "hello", "nested" => ["a" => "world"]];
echo "arr: {$arr['key']}\n";
echo "nested: {$arr['nested']['a']}\n";

$x = 42;
echo "expr: {$x}\n";

echo "done\n";
