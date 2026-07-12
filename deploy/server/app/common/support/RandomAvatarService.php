<?php

declare(strict_types=1);

namespace app\common\support;

final class RandomAvatarService
{
    public static function choose(array $configuration): string
    {
        $fallback = trim((string)($configuration['usertx'] ?? ''));
        if ((int)($configuration['random_avatar_enabled'] ?? 0) !== 1) {
            return $fallback;
        }
        $pool = self::pool($configuration['random_avatar_pool'] ?? []);
        if (!$pool) {
            return $fallback;
        }
        return $pool[random_int(0, count($pool) - 1)];
    }

    public static function pool(mixed $value): array
    {
        if (is_string($value)) {
            $decoded = json_decode($value, true);
            $source = is_array($decoded) ? $decoded : preg_split('/[\r\n,]+/', $value);
        } else {
            $source = is_array($value) ? $value : [];
        }
        $pool = [];
        foreach ($source as $avatar) {
            $avatar = trim((string)$avatar);
            if ($avatar !== '') {
                $pool[$avatar] = $avatar;
            }
        }
        return array_values($pool);
    }
}
