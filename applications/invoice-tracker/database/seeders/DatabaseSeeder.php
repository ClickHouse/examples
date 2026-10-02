<?php

namespace Database\Seeders;

use App\Domain\InvoiceLifecycle;
use App\Models\User;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $password = env('DEMO_PASSWORD');
        if (! is_string($password) || strlen($password) < 12) {
            throw new \RuntimeException('Set a private DEMO_PASSWORD of at least12 characters.');
        }
        foreach ([['Alex', 'alex@example.test'], ['Sam', 'sam@example.test']] as [$name,$email]) {
            $user = User::firstOrCreate(['email' => $email], ['name' => $name, 'password' => $password]);
            if (! $user->invoices()->exists()) {
                (new InvoiceLifecycle)->create($user->id,
                    ['recipient' => 'North Coast Studio', 'reference' => 'Website maintenance'],
                    [['description' => 'Support hours', 'quantity' => 3, 'unit_cents' => 12500],
                        ['description' => 'Domain renewal', 'quantity' => 1, 'unit_cents' => 2499]]);
            }
        }
        $this->command->info('Two demo users and draft invoices ready. Passwords set only on first creation.');
    }
}
