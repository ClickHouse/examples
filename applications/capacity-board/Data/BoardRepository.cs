using System.Text.Json;
using CapacityBoard.Domain;
using Dapper;
using Npgsql;

namespace CapacityBoard.Data;

// This service keeps only a data source and admission gate, never an open connection.
public sealed class BoardRepository(NpgsqlDataSource source) : IDisposable
{
    private readonly SemaphoreSlim admission = new(4);

    public async Task<BoardSnapshot> ReadAsync(CancellationToken cancellation = default)
    {
        if (!await admission.WaitAsync(0, cancellation)) throw new BoardError("busy");
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            deadline.CancelAfter(TimeSpan.FromSeconds(10));
            await using var conn = await source.OpenConnectionAsync(deadline.Token);
            return await ReadOnAsync(conn, null, deadline.Token);
        }
        finally { admission.Release(); }
    }

    private static async Task<BoardSnapshot> ReadOnAsync(NpgsqlConnection conn, NpgsqlTransaction? tx,
        CancellationToken cancellation)
    {
        // One joined statement observes parent and children from the same read snapshot.
        var rows = (await conn.QueryAsync<SnapshotRow>(new CommandDefinition("""
            SELECT b.id AS BoardId, b.title, b.capacity, b.revision,
                   i.id AS ItemId, i.name, i.points
            FROM capacity_board.boards b
            LEFT JOIN capacity_board.work_items i ON i.board_id = b.id
            WHERE b.id = @Id ORDER BY i.position
            """, new { Id = Allocation.BoardId }, tx, 4, cancellationToken: cancellation))).ToArray();
        if (rows.Length == 0) throw new BoardError("missing_board");
        var first = rows[0];
        return new BoardSnapshot(first.BoardId, first.Title, first.Capacity, first.Revision,
            rows.Where(row => row.ItemId.HasValue)
                .Select(row => new WorkItem(row.ItemId!.Value, row.Name!, row.Points!.Value)).ToArray());
    }

    public async Task<BoardSnapshot> SaveAsync(SaveRequest request, CancellationToken cancellation = default)
    {
        var save = Allocation.Validate(request);
        if (!await admission.WaitAsync(0, cancellation)) throw new BoardError("busy");
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            deadline.CancelAfter(TimeSpan.FromSeconds(10));
            var ct = deadline.Token;
            await using var conn = await source.OpenConnectionAsync(ct);
            await using var tx = await conn.BeginTransactionAsync(ct);
            CommandDefinition Command(string sql, object? parameters = null) =>
                new(sql, parameters, tx, 4, cancellationToken: ct);
            var board = await conn.QuerySingleAsync<ParentRow>(Command("""
                SELECT capacity, revision FROM capacity_board.boards WHERE id = @Id FOR UPDATE
                """, new { Id = Allocation.BoardId }));
            var previous = await conn.QuerySingleOrDefaultAsync<RetainedRow>(Command("""
                SELECT fingerprint, response::text AS Response
                FROM capacity_board.saves WHERE operation_id = @OperationId AND board_id = @BoardId
                """, new { save.OperationId, BoardId = Allocation.BoardId }));
            if (previous is not null)
            {
                if (previous.Fingerprint != save.Fingerprint) throw new BoardError("operation_conflict");
                var response = JsonSerializer.Deserialize<BoardSnapshot>(previous.Response)
                    ?? throw new BoardError("unavailable");
                await tx.CommitAsync(ct);
                return response;
            }
            if (board.Revision != save.ExpectedRevision) throw new BoardError("stale_revision");
            if (board.Revision > Allocation.MaxSaves) throw new BoardError("revision_limit");
            if (save.Items.Sum(item => item.Points) > board.Capacity) throw new BoardError("over_capacity");
            await conn.ExecuteAsync(Command("DELETE FROM capacity_board.work_items WHERE board_id = @Id",
                new { Id = Allocation.BoardId }));
            for (var position = 0; position < save.Items.Length; position++)
            {
                var item = save.Items[position];
                await conn.ExecuteAsync(Command("""
                    INSERT INTO capacity_board.work_items(board_id,id,position,name,points)
                    VALUES (@BoardId,@Id,@Position,@Name,@Points)
                    """, new { BoardId = Allocation.BoardId, item.Id, Position = position, item.Name, item.Points }));
            }
            await conn.ExecuteAsync(Command("""
                UPDATE capacity_board.boards SET revision = revision + 1 WHERE id = @Id
                """, new { Id = Allocation.BoardId }));
            var result = await ReadOnAsync(conn, tx, ct);
            await conn.ExecuteAsync(Command("""
                INSERT INTO capacity_board.saves(operation_id,board_id,fingerprint,revision,response)
                VALUES (@OperationId,@BoardId,@Fingerprint,@Revision,CAST(@Response AS jsonb))
                """, new
            {
                save.OperationId,
                BoardId = Allocation.BoardId,
                save.Fingerprint,
                result.Revision,
                Response = JsonSerializer.Serialize(result)
            }));
            await tx.CommitAsync(ct);
            return result;
        }
        finally { admission.Release(); }
    }

    public void Dispose() => admission.Dispose();

    private sealed class SnapshotRow
    {
        public Guid BoardId { get; set; }
        public string Title { get; set; } = "";
        public int Capacity { get; set; }
        public int Revision { get; set; }
        public Guid? ItemId { get; set; }
        public string? Name { get; set; }
        public int? Points { get; set; }
    }
    private sealed class ParentRow
    {
        public int Capacity { get; set; }
        public int Revision { get; set; }
    }
    private sealed class RetainedRow
    {
        public string Fingerprint { get; set; } = "";
        public string Response { get; set; } = "";
    }
}
