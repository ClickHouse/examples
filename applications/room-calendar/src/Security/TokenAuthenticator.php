<?php

declare(strict_types=1);

namespace App\Security;

use Symfony\Component\HttpFoundation\{JsonResponse,Request,Response};
use Symfony\Component\Security\Core\Authentication\Token\TokenInterface;
use Symfony\Component\Security\Core\Exception\{AuthenticationException,CustomUserMessageAuthenticationException};
use Symfony\Component\Security\Http\Authenticator\AbstractAuthenticator;
use Symfony\Component\Security\Http\Authenticator\Passport\Badge\UserBadge;
use Symfony\Component\Security\Http\Authenticator\Passport\{Passport,SelfValidatingPassport};
use Symfony\Component\Security\Http\EntryPoint\AuthenticationEntryPointInterface;

final class TokenAuthenticator extends AbstractAuthenticator implements AuthenticationEntryPointInterface
{
    public function __construct(private readonly string $firstToken, private readonly string $secondToken)
    {
        foreach ([$firstToken,$secondToken] as $token) {
            if (!preg_match('/\A[a-f0-9]{64}\z/D', $token)) {
                throw new \LogicException('Configure distinct 256-bit hexadecimal member tokens.');
            }
        }
        if (hash_equals($firstToken, $secondToken)) {
            throw new \LogicException('Member tokens must be distinct.');
        }
    }

    public function supports(Request $request): ?bool { return $request->getPathInfo() !== '/health'; }

    public function authenticate(Request $request): Passport
    {
        $header = $request->headers->get('Authorization', '');
        if (!preg_match('/\ABearer ([a-f0-9]{64})\z/D', $header, $matches)) {
            throw new CustomUserMessageAuthenticationException('A member bearer token is required.');
        }
        $first = hash_equals($this->firstToken, $matches[1]);
        $second = hash_equals($this->secondToken, $matches[1]);
        if (!$first && !$second) {
            throw new CustomUserMessageAuthenticationException('Invalid member token.');
        }
        $id = $first ? '00000000-0000-4000-8000-000000000001' : '00000000-0000-4000-8000-000000000002';
        return new SelfValidatingPassport(new UserBadge($id, static fn () => new MemberIdentity($id)));
    }

    public function onAuthenticationSuccess(Request $request, TokenInterface $token, string $firewallName): ?Response { return null; }
    public function onAuthenticationFailure(Request $request, AuthenticationException $exception): ?Response { return $this->start($request); }
    public function start(Request $request, ?AuthenticationException $authException = null): Response
    {
        return new JsonResponse(['error' => 'A valid member bearer token is required.'], 401,
                                ['WWW-Authenticate' => 'Bearer', 'Cache-Control' => 'no-store']);
    }
}
