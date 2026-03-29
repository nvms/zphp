<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\PostController;
use App\Http\Middleware\AddTestHeader;

Route::get('/', function () {
    return 'Hello from Laravel on zphp!';
});

Route::get('/posts', [PostController::class, 'index']);
Route::post('/posts', [PostController::class, 'store']);
Route::get('/posts/{id}', [PostController::class, 'show']);
Route::put('/posts/{id}', [PostController::class, 'update']);
Route::delete('/posts/{id}', [PostController::class, 'destroy']);

Route::post('/validate', [PostController::class, 'validateDemo']);

Route::get('/middleware-test', function () {
    return 'middleware works';
})->middleware(AddTestHeader::class);

Route::get('/error-test', function () {
    throw new \RuntimeException('intentional error');
});
