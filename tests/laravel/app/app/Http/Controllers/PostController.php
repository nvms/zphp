<?php

namespace App\Http\Controllers;

use App\Models\Post;
use App\Http\Requests\StorePostRequest;
use App\Http\Resources\PostResource;
use Illuminate\Http\Request;

class PostController extends Controller
{
    public function index()
    {
        $posts = Post::orderBy('id')->get();
        return view('posts.index', ['posts' => $posts]);
    }

    public function store(StorePostRequest $request)
    {
        $post = Post::create($request->validated());
        return response()->json(['id' => $post->id, 'title' => $post->title], 201);
    }

    public function show(int $id)
    {
        $post = Post::findOrFail($id);
        return view('posts.show', ['post' => $post]);
    }

    public function apiIndex()
    {
        $posts = Post::orderBy('id')->get();
        return PostResource::collection($posts);
    }

    public function apiStore(StorePostRequest $request)
    {
        $post = Post::create($request->validated());
        return new PostResource($post);
    }

    public function update(Request $request, int $id)
    {
        $post = Post::findOrFail($id);
        $post->update($request->only(['title', 'body', 'published']));
        return response()->json(['id' => $post->id, 'title' => $post->title]);
    }

    public function destroy(int $id)
    {
        $post = Post::findOrFail($id);
        $post->delete();
        return response()->json(['deleted' => true]);
    }

    public function validateDemo(Request $request)
    {
        $validated = $request->validate([
            'title' => 'required|string|min:3|max:255',
            'body' => 'required|string',
            'email' => 'required|email',
        ]);
        return response()->json(['valid' => true, 'data' => $validated]);
    }
}
