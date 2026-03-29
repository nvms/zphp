<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\PostController;

Route::get('/posts', [PostController::class, 'apiIndex']);
Route::post('/posts', [PostController::class, 'apiStore']);
