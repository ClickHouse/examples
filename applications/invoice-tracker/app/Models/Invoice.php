<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Invoice extends Model
{
    protected $fillable = ['recipient', 'reference'];

    protected function casts(): array
    {
        return ['snapshot' => 'array', 'issued_total_cents' => 'integer',
            'issued_at' => 'immutable_datetime', 'settled_at' => 'immutable_datetime'];
    }

    public function lines()
    {
        return $this->hasMany(InvoiceLine::class)->orderBy('position')->orderBy('id');
    }
}
