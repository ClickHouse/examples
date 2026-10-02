<?php

use App\Http\Controllers\InvoiceController;
use App\Http\Controllers\SessionController;
use Illuminate\Support\Facades\Route;

Route::pattern('invoice', '[1-9][0-9]{0,17}');

Route::get('/login', [SessionController::class, 'create'])->name('login');
Route::post('/login', [SessionController::class, 'store'])->middleware('throttle:10,3');
Route::middleware('auth')->group(function () {
    Route::post('/logout', [SessionController::class, 'destroy']);
    Route::get('/', fn () => redirect('/invoices'));
    Route::get('/invoices', [InvoiceController::class, 'index'])->name('invoices.index');
    Route::get('/invoices/create', [InvoiceController::class, 'create']);
    Route::post('/invoices', [InvoiceController::class, 'store']);
    Route::get('/invoices/{invoice}', [InvoiceController::class, 'show'])->name('invoices.show');
    Route::get('/invoices/{invoice}/edit', [InvoiceController::class, 'edit']);
    Route::put('/invoices/{invoice}', [InvoiceController::class, 'update']);
    Route::post('/invoices/{invoice}/issue', [InvoiceController::class, 'issue']);
    Route::post('/invoices/{invoice}/settle', [InvoiceController::class, 'settle']);
});
