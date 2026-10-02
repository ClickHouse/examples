@extends('layout')
@section('content')<section class="login"><p class="eyebrow">A CLEAR RECORD</p><h1>Welcome back.</h1><p>Sign in to manage your own invoices.</p><form action="/login" method="post">@csrf
<label for="email">Email</label><input type="email" id="email" name="email" value="{{ old('email') }}" required autocomplete="username">
<label for="password">Password</label><input type="password" id="password" name="password" required autocomplete="current-password"><button>Sign in</button></form></section>@endsection
