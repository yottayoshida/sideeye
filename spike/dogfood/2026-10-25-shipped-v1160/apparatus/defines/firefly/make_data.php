<?php
// The books a Firefly III user keeps, made through the classes the web UI and the API store with:
// one user, a checking and a savings account with opening balances, and a month of withdrawals,
// deposits and transfers. Run once from /opt/firefly after migrate and upgrade-database.
require '/opt/firefly/vendor/autoload.php';
$app = require '/opt/firefly/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use FireflyIII\User;
$user = User::where('email', 'owner@example.com')->first();
$accounts = app(FireflyIII\Repositories\Account\AccountRepositoryInterface::class);
$accounts->setUser($user);
$mk = fn ($name, $type, $extra = []) => $accounts->store(array_merge([
    'name' => $name, 'account_type_name' => $type, 'account_type_id' => null, 'currency_id' => 1, 'iban' => null,
    'active' => true, 'account_role' => 'asset' === $type ? 'defaultAsset' : null, 'virtual_balance' => null,
], $extra));
$checking = $mk('Checking', 'asset', ['opening_balance' => '1500', 'opening_balance_date' => new Carbon\Carbon('2026-09-01')]);
$savings  = $mk('Savings', 'asset', ['account_role' => 'savingAsset', 'opening_balance' => '8000', 'opening_balance_date' => new Carbon\Carbon('2026-09-01')]);

$groups = app(FireflyIII\Factory\TransactionGroupFactory::class);
$groups->setUser($user);
$tx = function ($type, $amount, $date, $desc, $src, $dst) use ($user, $groups) {
    return $groups->create(['user' => $user, 'user_group' => $user->userGroup, 'group_title' => null, 'transactions' => [[
        'type' => $type, 'amount' => $amount, 'date' => new Carbon\Carbon($date), 'description' => $desc,
        'source_id' => $src['id'] ?? null, 'source_name' => $src['name'] ?? null,
        'destination_id' => $dst['id'] ?? null, 'destination_name' => $dst['name'] ?? null,
        'currency_id' => 1, 'order' => 0, 'reconciled' => false, 'tags' => [], 'notes' => '',
    ]]]);
};
$tx('deposit', '3200', '2026-09-25', 'Salary', ['name' => 'Employer'], ['id' => $checking->id]);
foreach (['2026-09-03' => 42.10, '2026-09-10' => 61.75, '2026-09-17' => 38.40, '2026-09-24' => 55.05] as $d => $a) {
    $tx('withdrawal', (string) $a, $d, 'Groceries', ['id' => $checking->id], ['name' => 'Grocer']);
}
$tx('withdrawal', '950', '2026-09-01', 'Rent', ['id' => $checking->id], ['name' => 'Landlord']);
$tx('transfer', '500', '2026-09-26', 'Monthly saving', ['id' => $checking->id], ['id' => $savings->id]);
echo "accounts ", FireflyIII\Models\Account::count(), " journals ", FireflyIII\Models\TransactionJournal::count(), "\n";
