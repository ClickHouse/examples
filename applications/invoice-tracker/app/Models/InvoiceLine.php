<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class InvoiceLine extends Model
{
    protected $fillable = ['description', 'quantity', 'unit_cents', 'position'];

    public $timestamps = false;

    protected function casts(): array
    {
        return ['quantity' => 'integer', 'unit_cents' => 'integer'];
    }
}
