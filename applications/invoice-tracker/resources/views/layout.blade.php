<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Invoice tracker</title><link rel="stylesheet" href="/style.css"><script src="/editor.js" defer></script></head>
<body><header><a href="/invoices" class="brand">◈ Invoice tracker</a>@auth<nav><span>{{ auth()->user()->name }}</span><form method="post" action="/logout">@csrf<button class="quiet">Sign out</button></form></nav>@endauth</header>
<main>@if(session('notice'))<p class="notice" role="status">{{ session('notice') }}</p>@endif
@if($errors->any())<div role="alert" class="alert"><strong>Please check the form.</strong><ul>@foreach($errors->all() as $error)<li>{{ $error }}</li>@endforeach</ul></div>@endif
@yield('content')</main><footer>USD only · Manual invoice records</footer></body></html>
