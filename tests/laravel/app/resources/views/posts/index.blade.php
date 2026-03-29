Posts ({{ count($posts) }}):
@forelse($posts as $post)
- [{{ $post->id }}] {{ $post->title }}{{ $post->published ? ' (published)' : '' }}
@empty
No posts found.
@endforelse
