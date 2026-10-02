<?php

namespace App\Http\Controllers;

use App\Domain\InvoiceLifecycle;
use App\Domain\Money;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class InvoiceController
{
    public function index(Request $request)
    {
        $request->validate(['page' => 'sometimes|integer|min:1|max:1000']);

        return view('index', ['invoices' => $request->user()->invoices()->orderByDesc('id')->simplePaginate(20)]);
    }

    public function create()
    {
        return view('edit', ['invoice' => null, 'lines' => [['description' => '', 'quantity' => 1, 'unit_price' => '0.00']]]);
    }

    public function show(Request $request, int $invoice)
    {
        $record = $request->user()->invoices()->findOrFail($invoice);

        return view('show', ['invoice' => $record, 'lines' => $record->status === 'draft'
            ? $record->lines()->get()->toArray() : $record->snapshot['lines']]);
    }

    public function edit(Request $request, int $invoice)
    {
        $record = $request->user()->invoices()->findOrFail($invoice);
        abort_unless($record->status === 'draft', 409, 'An issued invoice cannot be edited.');

        return view('edit', ['invoice' => $record, 'lines' => $record->lines()->get()->map(fn ($line) => [
            'description' => $line->description, 'quantity' => $line->quantity,
            'unit_price' => intdiv($line->unit_cents, 100).'.'.str_pad((string) ($line->unit_cents % 100), 2, '0', STR_PAD_LEFT),
        ])->all()]);
    }

    public function store(Request $request, InvoiceLifecycle $lifecycle)
    {
        [$header,$lines] = $this->validated($request);
        $invoice = $lifecycle->create($request->user()->id, $header, $lines);

        return redirect('/invoices/'.$invoice->id, 303)->with('notice', 'Draft created.');
    }

    public function update(Request $request, int $invoice, InvoiceLifecycle $lifecycle)
    {
        // Scope before validation, so another user's identifier always gets404.
        $request->user()->invoices()->findOrFail($invoice);
        [$header,$lines] = $this->validated($request);
        $record = $lifecycle->edit($request->user()->id, $invoice, $header, $lines);

        return redirect('/invoices/'.$record->id, 303)->with('notice', 'Draft saved.');
    }

    public function issue(Request $request, int $invoice, InvoiceLifecycle $lifecycle)
    {
        $record = $lifecycle->issue($request->user()->id, $invoice);

        return redirect('/invoices/'.$record->id, 303)->with('notice', 'Invoice issued; its snapshot is fixed.');
    }

    public function settle(Request $request, int $invoice, InvoiceLifecycle $lifecycle)
    {
        $record = $lifecycle->settle($request->user()->id, $invoice);

        return redirect('/invoices/'.$record->id, 303)->with('notice', 'Settlement recorded.');
    }

    private function validated(Request $request): array
    {
        $data = $request->validate(['recipient' => 'required|string|max:120', 'reference' => 'required|string|max:120',
            'lines' => 'required|array|min:1|max:100', 'lines.*.description' => 'required|string|max:200',
            'lines.*.quantity' => 'required|integer|min:1|max:1000', 'lines.*.unit_price' => 'required|string|max:12']);
        $lines = [];
        foreach ($data['lines'] as $i => $line) {
            try {
                $cents = Money::cents($line['unit_price']);
            } catch (\InvalidArgumentException $error) {
                throw ValidationException::withMessages(["lines.$i.unit_price" => $error->getMessage()]);
            }
            $lines[] = ['description' => $line['description'], 'quantity' => (int) $line['quantity'], 'unit_cents' => $cents];
        }

        return [array_intersect_key($data, array_flip(['recipient', 'reference'])), $lines];
    }
}
