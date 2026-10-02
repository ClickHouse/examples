<?php

declare(strict_types=1);

namespace App;

use Doctrine\Bundle\DoctrineBundle\DoctrineBundle;
use Doctrine\Bundle\MigrationsBundle\DoctrineMigrationsBundle;
use Symfony\Bundle\FrameworkBundle\FrameworkBundle;
use Symfony\Bundle\FrameworkBundle\Kernel\MicroKernelTrait;
use Symfony\Bundle\SecurityBundle\SecurityBundle;
use Symfony\Component\DependencyInjection\Loader\Configurator\ContainerConfigurator;
use Symfony\Component\HttpKernel\Kernel as BaseKernel;
use Symfony\Component\Routing\Loader\Configurator\RoutingConfigurator;

final class Kernel extends BaseKernel
{
    use MicroKernelTrait;

    public function registerBundles(): iterable
    {
        yield new FrameworkBundle();
        yield new SecurityBundle();
        yield new DoctrineBundle();
        yield new DoctrineMigrationsBundle();
    }

    protected function configureContainer(ContainerConfigurator $container): void
    {
        $container->extension('framework', [
            'secret' => '%env(APP_SECRET)%',
            'http_method_override' => false,
            'handle_all_throwables' => true,
            'validation' => ['enable_attributes' => true],
        ]);
        $container->extension('security', [
            'providers' => ['members' => ['memory' => ['users' => []]]],
            'firewalls' => ['api' => [
                'pattern' => '^/', 'stateless' => true,
                'custom_authenticators' => [Security\TokenAuthenticator::class],
            ]],
            'access_control' => [
                ['path' => '^/health$', 'roles' => 'PUBLIC_ACCESS'],
                ['path' => '^/', 'roles' => 'ROLE_MEMBER'],
            ],
        ]);
        $container->extension('doctrine', [
            'dbal' => [
                'driver' => 'pdo_pgsql', 'server_version' => '18',
                'host' => '%env(PGHOST)%', 'port' => '%env(int:PGPORT)%',
                'dbname' => '%env(PGDATABASE)%', 'user' => '%env(PGUSER)%',
                'password' => '%env(PGPASSWORD)%',
                'sslmode' => 'verify-full', 'sslrootcert' => '%env(PGSSLROOTCERT)%',
                'application_name' => 'room-calendar',
                'options' => [\PDO::ATTR_TIMEOUT => 5],
            ],
            'orm' => [
                'auto_generate_proxy_classes' => false,
                'mappings' => ['App' => [
                    'type' => 'attribute', 'dir' => '%kernel.project_dir%/src/Entity',
                    'prefix' => 'App\\Entity', 'is_bundle' => false,
                ]],
            ],
        ]);
        $container->extension('doctrine_migrations', [
            'migrations_paths' => ['DoctrineMigrations' => '%kernel.project_dir%/migrations'],
            'storage' => ['table_storage' => ['table_name' => 'migration_versions']],
            'all_or_nothing' => true,
        ]);
        $services = $container->services()->defaults()->autowire()->autoconfigure();
        $services->load('App\\', __DIR__.'/')
            ->exclude([__DIR__.'/Entity/', __DIR__.'/Dto/', __DIR__.'/Security/MemberIdentity.php', __DIR__.'/Kernel.php', __DIR__.'/ApiProblem.php']);
        $services->set(Dto\Inputs::class);
        $services->set(Security\TokenAuthenticator::class)
            ->arg('$firstToken', '%env(MEMBER_001_TOKEN)%')
            ->arg('$secondToken', '%env(MEMBER_002_TOKEN)%');
    }

    protected function configureRoutes(RoutingConfigurator $routes): void
    {
        $routes->import(__DIR__.'/Controller/', 'attribute');
    }
}
