<?php

declare(strict_types=1);

$env = parse_ini_file('/www/wwwroot/blin/.env', true, INI_SCANNER_RAW)['DATABASE'];
$database = trim((string) $env['DATABASE']);
$prefix = trim((string) ($env['PREFIX'] ?? 'mr_'));
$pdo = new PDO(
    'mysql:host=' . trim((string) $env['HOSTNAME']) . ';dbname=' . $database . ';charset=utf8mb4',
    trim((string) $env['USERNAME']),
    trim((string) $env['PASSWORD']),
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);

$hasColumn = static function (string $table, string $column) use ($pdo, $database): bool {
    $statement = $pdo->prepare('SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=? AND table_name=? AND column_name=?');
    $statement->execute([$database, $table, $column]);
    return (int) $statement->fetchColumn() > 0;
};
$hasIndex = static function (string $table, string $index) use ($pdo, $database): bool {
    $statement = $pdo->prepare('SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=? AND table_name=? AND index_name=?');
    $statement->execute([$database, $table, $index]);
    return (int) $statement->fetchColumn() > 0;
};
$tables = [
    $prefix . 'wallet_sweep_order' => [
        'lease_owner' => "varchar(80) NOT NULL DEFAULT ''",
        'lease_until' => 'datetime DEFAULT NULL',
        'next_retry_time' => 'datetime DEFAULT NULL',
        'confirmed_time' => 'datetime DEFAULT NULL',
    ],
    $prefix . 'wallet_withdraw_order' => [
        'lease_owner' => "varchar(80) NOT NULL DEFAULT ''",
        'lease_until' => 'datetime DEFAULT NULL',
        'retry_count' => 'int unsigned NOT NULL DEFAULT 0',
        'last_error' => "varchar(500) NOT NULL DEFAULT ''",
        'next_retry_time' => 'datetime DEFAULT NULL',
        'confirmed_time' => 'datetime DEFAULT NULL',
    ],
];
foreach ($tables as $table => $columns) {
    foreach ($columns as $column => $definition) {
        if (!$hasColumn($table, $column)) {
            $pdo->exec("ALTER TABLE `{$table}` ADD COLUMN `{$column}` {$definition}");
            echo "added {$table}.{$column}\n";
        }
    }
}
$indexes = [
    $prefix . 'wallet_sweep_order' => ['idx_sweep_lease', '(`status`,`next_retry_time`,`lease_until`,`id`)'],
    $prefix . 'wallet_withdraw_order' => ['idx_withdraw_lease', '(`status`,`next_retry_time`,`lease_until`,`id`)'],
];
foreach ($indexes as $table => [$name, $columns]) {
    if (!$hasIndex($table, $name)) {
        $pdo->exec("ALTER TABLE `{$table}` ADD KEY `{$name}` {$columns}");
    }
}
echo "migration ok\n";
