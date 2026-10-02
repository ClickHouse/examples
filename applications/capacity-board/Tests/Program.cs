using CapacityBoard.Domain;

if (args.Contains("--cloud"))
{
    await CloudChecks.Run();
    return;
}

void Check(bool condition) { if (!condition) throw new Exception("Assertion failed"); }
void Rejected(Action action)
{
    try { action(); }
    catch (BoardError) { return; }
    throw new Exception("Expected validation rejection");
}
var id = Guid.NewGuid();
var operation = Guid.NewGuid();
var original = new SaveRequest(operation, 1, [new WorkItem(id, " Demo ", 4)]);
var canonical = Allocation.Validate(original);
Check(canonical.Items[0].Name == "Demo");
Check(canonical.Fingerprint == Allocation.Validate(original with
{ Items = [new WorkItem(id, "Demo", 4)] }).Fingerprint);
Check(canonical.Fingerprint != Allocation.Validate(original with
{ Items = [new WorkItem(id, "Demo", 5)] }).Fingerprint);
Console.WriteLine("PASS canonical exact-payload fingerprints");
Rejected(() => Allocation.Validate(original with { Items = [original.Items[0], original.Items[0]] }));
Rejected(() => Allocation.Validate(original with
{
    Items = Enumerable.Range(0, 21)
    .Select(_ => new WorkItem(Guid.NewGuid(), "Item", 1)).ToArray()
}));
Rejected(() => Allocation.Validate(original with { OperationId = Guid.Empty }));
Rejected(() => Allocation.Validate(original with { ExpectedRevision = int.MaxValue }));
Console.WriteLine("PASS complete-set UUID/count/revision bounds");
Check(Allocation.Name("✨ café") == "✨ café");
Check(Allocation.Name(new string('a', 80)).Length == 80);
Rejected(() => Allocation.Name(new string('a', 81)));
Rejected(() => Allocation.Name("bad\0name"));
Rejected(() => Allocation.Name("\ud800"));
Rejected(() => Allocation.Name("\udc00"));
Console.WriteLine("PASS Unicode/control/UTF-16 boundary");
foreach (var value in new[] { "1.5", "-1", "31", "1000000000000", "", " 2" })
    Rejected(() => Allocation.Points(value));
Check(Allocation.Points("0") == 0 && Allocation.Points("30") == 30);
Console.WriteLine("PASS bounded integer form parsing");
