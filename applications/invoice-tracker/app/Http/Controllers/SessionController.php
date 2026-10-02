<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\ValidationException;

class SessionController
{
    public function create()
    {
        return view('login');
    }

    public function store(Request $request)
    {
        $data = $request->validate(['email' => 'required|email|max:254', 'password' => 'required|string|max:100']);
        if (! Auth::attempt(['email' => strtolower(trim($data['email'])), 'password' => $data['password']])) {
            throw ValidationException::withMessages(['email' => 'Email or password is incorrect.']);
        }
        $request->session()->regenerate();

        return redirect('/invoices', 303);
    }

    public function destroy(Request $request)
    {
        Auth::logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return redirect('/login', 303);
    }
}
