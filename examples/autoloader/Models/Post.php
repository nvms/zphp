<?php

class Post
{
    public string $title;
    public string $author;

    public function __construct(string $title, string $author)
    {
        $this->title = $title;
        $this->author = $author;
    }

    public function summary(): string
    {
        return '"' . $this->title . '" by ' . $this->author;
    }
}
