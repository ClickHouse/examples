package migrations

import "embed"

// Files holds reviewed SQL applied by the migration CLI.
//
//go:embed 001_initial.sql seed.sql down.sql
var Files embed.FS
