<?php

declare(strict_types=1);

namespace App\Security;

use Symfony\Component\Security\Core\User\UserInterface;

final class MemberIdentity implements UserInterface
{
    public function __construct(public readonly string $id) {}
    public function getUserIdentifier(): string { return $this->id; }
    public function getRoles(): array { return ['ROLE_MEMBER']; }
    public function eraseCredentials(): void {}
}
