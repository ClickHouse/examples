<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;

final class Version202610020001 extends AbstractMigration
{
    public function getDescription(): string { return 'Finite room ranges with active-only overlap exclusion'; }

    public function up(Schema $schema): void
    {
        $this->abortIf(!($this->connection->getDatabasePlatform() instanceof \Doctrine\DBAL\Platforms\PostgreSQLPlatform), 'PostgreSQL is required.');
        $this->addSql("CREATE TABLE calendar.members(id uuid PRIMARY KEY,name varchar(80) NOT NULL)");
        $this->addSql("CREATE TABLE calendar.rooms(id uuid PRIMARY KEY,name varchar(80) NOT NULL)");
        $this->addSql(<<<'SQL'
            CREATE TABLE calendar.reservations (
                id uuid PRIMARY KEY,
                room_id uuid NOT NULL REFERENCES calendar.rooms(id),
                member_id uuid NOT NULL REFERENCES calendar.members(id),
                title varchar(120) NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
                start_at timestamptz(0) NOT NULL,
                end_at timestamptz(0) NOT NULL,
                status varchar(9) NOT NULL CHECK (status IN ('active','cancelled')),
                revision integer NOT NULL CHECK (revision BETWEEN 1 AND 1000000000),
                CONSTRAINT finite_interval CHECK (
                    isfinite(start_at) AND isfinite(end_at) AND start_at < end_at
                    AND start_at >= '2000-01-01T00:00:00Z'::timestamptz
                    AND end_at < '2101-01-01T00:00:00Z'::timestamptz
                    AND end_at - start_at <= interval '12 hours'
                ),
                CONSTRAINT active_room_no_overlap EXCLUDE USING gist (
                    room_id WITH =,
                    tstzrange(start_at,end_at,'[)') WITH &&
                ) WHERE (status='active')
            )
            SQL);
        $this->addSql('CREATE INDEX reservation_listing ON calendar.reservations(room_id,start_at,id) WHERE status=\'active\'');
        $this->addSql('GRANT SELECT ON calendar.rooms,calendar.reservations TO calendar_app');
        $this->addSql('GRANT INSERT ON calendar.reservations TO calendar_app');
        $this->addSql('GRANT UPDATE(start_at,end_at,status,revision) ON calendar.reservations TO calendar_app');
    }

    public function down(Schema $schema): void
    {
        $this->addSql('DROP TABLE calendar.reservations,calendar.rooms,calendar.members');
    }
}
