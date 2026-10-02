using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace HabitApi.Migrations
{
    /// <inheritdoc />
    public partial class Initial : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "habits");

            migrationBuilder.CreateTable(
                name: "habit",
                schema: "habits",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    owner_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    archived = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_habit", x => x.id);
                    table.CheckConstraint("habit_name_nonblank", "length(btrim(name)) > 0");
                });

            migrationBuilder.CreateTable(
                name: "check_in",
                schema: "habits",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    habit_id = table.Column<Guid>(type: "uuid", nullable: false),
                    completed_on = table.Column<DateOnly>(type: "date", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_check_in", x => x.id);
                    table.CheckConstraint("check_in_date_bound", "completed_on BETWEEN DATE '2000-01-01' AND DATE '2100-12-31'");
                    table.ForeignKey(
                        name: "FK_check_in_habit_habit_id",
                        column: x => x.habit_id,
                        principalSchema: "habits",
                        principalTable: "habit",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "uq_check_in_habit_date",
                schema: "habits",
                table: "check_in",
                columns: new[] { "habit_id", "completed_on" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "habit_owner_created",
                schema: "habits",
                table: "habit",
                columns: new[] { "owner_id", "created_at", "id" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "check_in",
                schema: "habits");

            migrationBuilder.DropTable(
                name: "habit",
                schema: "habits");
        }
    }
}
