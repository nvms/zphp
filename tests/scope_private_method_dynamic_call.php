<?php
// a class calling a method of its own instance by a dynamic name, or as a
// callable, runs its own private method even when a subclass redeclares it

class A
{
    private function test()
    {
        echo 'A::test on ' . get_class($this) . "\n";
    }

    public function call($method)
    {
        $this->test();
        $this->$method();
        call_user_func([$this, $method]);
        call_user_func_array([$this, $method], []);
        [$this, $method]();
        (Closure::fromCallable([$this, $method]))();
        $this->$method(...)();
        var_dump(is_callable([$this, $method]));
    }
}

class B extends A
{
    protected function test()
    {
        echo 'B::test on ' . get_class($this) . "\n";
    }

    public function own()
    {
        $this->test();
        call_user_func([$this, 'test']);
    }
}

(new A)->call('test');
(new B)->call('test');
(new B)->own();
