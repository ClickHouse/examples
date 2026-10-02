<?php

namespace App\Domain;

use App\Models\Invoice;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

final class InvoiceLifecycle
{
    public function create(int $userId, array $header, array $lines): Invoice
    {
        return DB::transaction(function () use ($userId, $header, $lines) {
            $invoice = new Invoice($header);
            $invoice->user_id = $userId;
            $invoice->save();
            $this->replaceLines($invoice, $lines);

            return $invoice;
        });
    }

    public function edit(int $userId, int $id, array $header, array $lines): Invoice
    {
        return DB::transaction(function () use ($userId, $id, $header, $lines) {
            $invoice = $this->locked($userId, $id);
            abort_unless($invoice->status === 'draft', 409, 'An issued invoice cannot be edited.');
            $invoice->update($header);
            $this->replaceLines($invoice, $lines);

            return $invoice;
        });
    }

    public function issue(int $userId, int $id): Invoice
    {
        return DB::transaction(function () use ($userId, $id) {
            $invoice = $this->locked($userId, $id);
            if ($invoice->status !== 'draft') {
                return $invoice;
            } // Retry retains number, total and snapshot.
            $lines = $invoice->lines()->get()->map(fn ($line) => [
                'description' => $line->description, 'quantity' => $line->quantity,
                'unit_cents' => $line->unit_cents, 'line_total_cents' => $line->quantity * $line->unit_cents,
            ])->all();
            if (! $lines) {
                throw ValidationException::withMessages(['lines' => 'Add a line before issuing.']);
            }
            $invoice->issued_total_cents = Money::total($lines);
            $invoice->snapshot = ['recipient' => $invoice->recipient, 'reference' => $invoice->reference,
                'currency' => 'USD', 'lines' => $lines];
            $number = DB::selectOne("SELECT nextval('invoice_tracker.invoice_public_number') AS number")->number;
            $invoice->public_number = 'INV-'.str_pad((string) $number, 6, '0', STR_PAD_LEFT);
            $invoice->issued_at = now();
            $invoice->status = 'issued';
            $invoice->save();

            return $invoice;
        });
    }

    public function settle(int $userId, int $id): Invoice
    {
        return DB::transaction(function () use ($userId, $id) {
            $invoice = $this->locked($userId, $id);
            abort_if($invoice->status === 'draft', 409, 'Issue the invoice before recording settlement.');
            if ($invoice->status === 'issued') {
                $invoice->status = 'settled';
                $invoice->settled_at = now();
                $invoice->save();
            }

            return $invoice;
        });
    }

    private function locked(int $userId, int $id): Invoice
    {
        return Invoice::where('user_id', $userId)->whereKey($id)->lockForUpdate()->firstOrFail();
    }

    private function replaceLines(Invoice $invoice, array $lines): void
    {
        Money::total($lines);
        $invoice->lines()->delete();
        foreach ($lines as $position => $line) {
            $invoice->lines()->create($line + ['position' => $position]);
        }
    }
}
