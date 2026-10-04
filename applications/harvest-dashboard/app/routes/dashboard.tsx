import { useCallback, useEffect, useState } from 'react';
import { data, useFetcher, useNavigation, Form } from 'react-router';
import { Alert, Badge, Button, Card, Container, Grid, Group, Loader, Modal, NumberInput, Select, Stack, Table, Text, Textarea, TextInput, Title } from '@mantine/core';
import { useForm } from '@mantine/form';
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import type { Route } from './+types/dashboard';
import { createHarvest, deleteHarvest, InvalidReference, loadDashboard, RevisionConflict, updateHarvest, type Harvest, type Lookup } from '../lib/harvest.server';
import { enforceOrigin } from '../lib/security.server';
import { entrySchema, fieldErrors, parseFilters, revisionSchema } from '../lib/validation';

type ActionResult = { ok: boolean; message: string; errors?: Record<string, string>; nonce?: string };
export function meta() { return [{ title: 'Harvest journal | Garden notes' }, { name: 'description', content: 'A garden harvest journal with weekly totals and crop comparisons.' }]; }
export async function loader({ request }: Route.LoaderArgs) {
  enforceOrigin(request);
  let filters;
  try { filters = parseFilters(new URL(request.url)); }
  catch { throw new Response('Choose a valid date range of at most 366 days and an existing crop identifier.', { status: 400 }); }
  return loadDashboard(filters);
}
export async function action({ request }: Route.ActionArgs) {
  enforceOrigin(request);
  const fields = Object.fromEntries(await request.formData());
  const intent = fields.intent;
  if (!['create', 'update', 'delete'].includes(String(intent))) return data<ActionResult>({ ok: false, message: 'Choose a supported journal action.' }, { status: 400 });
  const revision = revisionSchema.safeParse(fields);
  if (intent !== 'create' && !revision.success) return data<ActionResult>({ ok: false, message: 'Reload the entry before changing it.' }, { status: 400 });
  const parsed = entrySchema.safeParse(fields);
  if (intent !== 'delete' && !parsed.success) return data<ActionResult>({ ok: false, message: 'Check the highlighted fields.', errors: fieldErrors(parsed.error) }, { status: 400 });
  try {
    if (intent === 'create' && parsed.success) await createHarvest(parsed.data);
    else if (intent === 'update' && parsed.success && revision.success) await updateHarvest(revision.data.id, revision.data.version, parsed.data);
    else if (intent === 'delete' && revision.success) await deleteHarvest(revision.data.id, revision.data.version);
    return data<ActionResult>({ ok: true, message: intent === 'delete' ? 'Harvest removed.' : 'Harvest saved.', nonce: crypto.randomUUID() });
  } catch (error) {
    if (error instanceof RevisionConflict) return data<ActionResult>({ ok: false, message: 'This harvest changed in another tab or was removed. Reload the page, then reopen the entry.' }, { status: 409 });
    if (error instanceof InvalidReference) return data<ActionResult>({ ok: false, message: 'Choose a crop and bed from this garden.' }, { status: 400 });
    console.error('Harvest write failed.');
    return data<ActionResult>({ ok: false, message: 'The harvest could not be saved. Try again after checking the database connection.' }, { status: 503 });
  }
}
const kilos = (grams: number) => (grams / 1000).toLocaleString('en-GB', { maximumFractionDigits: 3 });
const shortDate = (value: string) => new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(new Date(value + 'T12:00:00Z'));

function HarvestEditor({ crops, beds, entry, onSaved }: { crops: Lookup[]; beds: Lookup[]; entry?: Harvest; onSaved?: () => void }) {
  const fetcher = useFetcher<typeof action>();
  const form = useForm({
    mode: 'controlled',
    initialValues: { cropId: entry?.crop_id ?? crops[0]?.id ?? '', bedId: entry?.bed_id ?? beds[0]?.id ?? '', harvestedOn: entry?.harvested_on ?? '2026-09-28', grams: entry?.grams ?? ('' as number | string), note: entry?.note ?? '' },
    validate: (values) => { const parsed = entrySchema.safeParse(values); return parsed.success ? {} : fieldErrors(parsed.error); },
  });
  useEffect(() => {
    if (fetcher.data?.ok) { if (entry) onSaved?.(); else form.reset(); }
    else if (fetcher.data?.errors) form.setErrors(fetcher.data.errors);
  }, [fetcher.data]); // Each action response applies once; fields remain editable after a server error.
  return <form onSubmit={form.onSubmit((values) => fetcher.submit({ ...values, grams: String(values.grams), intent: entry ? 'update' : 'create', ...(entry ? { id: entry.id, version: String(entry.version) } : {}) }, { method: 'post' }))}>
    <Stack gap="sm">
      <Select label="Crop" data={crops.map((c) => ({ value: c.id, label: c.name }))} {...form.getInputProps('cropId')} allowDeselect={false} disabled={fetcher.state !== 'idle'} />
      <Select label="Garden bed" data={beds.map((b) => ({ value: b.id, label: b.name }))} {...form.getInputProps('bedId')} allowDeselect={false} disabled={fetcher.state !== 'idle'} />
      <Group grow align="start">
        <TextInput type="date" label="Harvest date" {...form.getInputProps('harvestedOn')} disabled={fetcher.state !== 'idle'} />
        <NumberInput label="Weight (g)" placeholder="450" min={1} max={1_000_000} allowDecimal={false} {...form.getInputProps('grams')} disabled={fetcher.state !== 'idle'} />
      </Group>
      <Textarea label="Notes" placeholder="First basket from the south bed…" maxLength={500} autosize minRows={3} {...form.getInputProps('note')} disabled={fetcher.state !== 'idle'} />
      {fetcher.data && <Alert role="status" color={fetcher.data.ok ? 'teal' : 'red'}>{fetcher.data.message}</Alert>}
      <Button type="submit" loading={fetcher.state !== 'idle'}>{entry ? 'Save changes' : 'Record harvest'}</Button>
    </Stack>
  </form>;
}
function HarvestRow({ entry, edit }: { entry: Harvest; edit: (entry: Harvest) => void }) {
  const fetcher = useFetcher<typeof action>();
  return <Table.Tr data-testid={`entry-${entry.id}`}>
    <Table.Td><Text fw={600}>{shortDate(entry.harvested_on)}</Text><Text size="xs" c="dimmed">{entry.harvested_on}</Text></Table.Td>
    <Table.Td><Text fw={600}>{entry.crop}</Text><Text size="sm" c="dimmed">{entry.bed}</Text></Table.Td>
    <Table.Td><Text fw={600}>{kilos(entry.grams)} kg</Text><Text size="xs" c="dimmed">{entry.grams} g</Text></Table.Td>
    <Table.Td className="notes-cell">{entry.note || '—'}</Table.Td>
    <Table.Td><Group gap="xs" wrap="nowrap"><Button variant="light" size="xs" onClick={() => edit(entry)} aria-label={`Edit ${entry.crop} harvest ${entry.harvested_on}`}>Edit</Button>
      <fetcher.Form method="post"><input type="hidden" name="intent" value="delete" /><input type="hidden" name="id" value={entry.id} /><input type="hidden" name="version" value={entry.version} />
        <Button type="submit" size="xs" color="red" variant="subtle" loading={fetcher.state !== 'idle'} aria-label={`Delete ${entry.crop} harvest ${entry.harvested_on}`}>Delete</Button></fetcher.Form></Group>
      {fetcher.data && !fetcher.data.ok && <Text role="alert" size="xs" c="red">{fetcher.data.message}</Text>}
    </Table.Td></Table.Tr>;
}
export default function Dashboard({ loaderData }: Route.ComponentProps) {
  const { crops, beds, entries, weekly, cropTotals, summary, filters } = loaderData;
  const [editing, setEditing] = useState<Harvest>();
  const closeEditor = useCallback(() => setEditing(undefined), []);
  const navigation = useNavigation();
  const [chartsReady, setChartsReady] = useState(false);
  useEffect(() => setChartsReady(true), []);
  return <Container size="xl" py="xl">
    <header className="garden-header"><div><Text className="eyebrow">GARDEN NOTES / THE HARVEST JOURNAL</Text><Title order={1}>A season, basket by basket.</Title><Text size="lg" c="dimmed" mt="sm">Record what you grow. See when the garden gives back.</Text></div><Badge size="lg" variant="light" color="teal">One garden · Shared journal</Badge></header>
    <Card withBorder className="filter-card" padding="lg" mb="lg">
      <Form method="get"><Group align="end" gap="md">
        <TextInput type="date" label="From" name="from" defaultValue={filters.from} key={`from-${filters.from}`} required />
        <TextInput type="date" label="To" name="to" defaultValue={filters.to} key={`to-${filters.to}`} required />
        <Select label="Compare crop" name="cropId" defaultValue={filters.cropId} key={`crop-${filters.cropId}`} data={[{ value: '', label: 'All crops' }, ...crops.map((c) => ({ value: c.id, label: c.name }))]} allowDeselect={false} />
        <Button type="submit" variant="light" loading={navigation.state !== 'idle'}>Apply filters</Button>
        {navigation.state !== 'idle' && <Group gap="xs" role="status"><Loader size="xs" /><Text size="sm">Updating the journal…</Text></Group>}
      </Group></Form>
    </Card>
    <Grid gap="lg"><Grid.Col span={{ base: 12, lg: 8 }}>
      <Grid gap="md" mb="lg"><Grid.Col span={6}><Card withBorder padding="lg"><Text className="eyebrow">TOTAL HARVEST</Text><Text className="metric" data-testid="total-weight">{kilos(summary.grams)}<span> kg</span></Text><Text size="sm" c="dimmed">Within the selected dates</Text></Card></Grid.Col>
        <Grid.Col span={6}><Card withBorder padding="lg"><Text className="eyebrow">BASKETS RECORDED</Text><Text className="metric" data-testid="entry-count">{summary.count}</Text><Text size="sm" c="dimmed">{filters.cropId ? 'For this crop' : `${crops.length} crops in the garden`}</Text></Card></Grid.Col></Grid>
      <Card withBorder padding="lg" mb="lg"><Group justify="space-between" mb="md"><Title order={2}>The weekly rhythm</Title><Text size="sm" c="dimmed">Weeks start Monday · kg</Text></Group>
        {weekly.length ? <div className="chart" aria-label="Weekly harvest chart">{chartsReady && <ResponsiveContainer width="100%" height={240} minWidth={0}><BarChart data={weekly.map((v) => ({ ...v, kg: v.grams / 1000 }))} margin={{ left: 0, right: 12, bottom: 0, top: 10 }}><CartesianGrid strokeDasharray="3 3" vertical={false} /><XAxis dataKey="week" tickFormatter={shortDate} tick={{ fontSize: 12 }} /><YAxis unit=" kg" width={65} tick={{ fontSize: 12 }} /><Tooltip labelFormatter={(v) => `Week of ${shortDate(String(v))}`} formatter={(v) => [`${v} kg`, 'Harvest']} /><Bar dataKey="kg" fill="#2e7d63" radius={[5, 5, 0, 0]} isAnimationActive={false} /></BarChart></ResponsiveContainer>}</div> : <Text py="xl" c="dimmed">No harvests in this range. Record a basket or adjust the dates.</Text>}
        <details><summary>Read weekly totals</summary><Table><Table.Thead><Table.Tr><Table.Th>Week beginning</Table.Th><Table.Th>Weight</Table.Th></Table.Tr></Table.Thead><Table.Tbody>{weekly.map((v) => <Table.Tr key={v.week}><Table.Td>{v.week}</Table.Td><Table.Td>{kilos(v.grams)} kg</Table.Td></Table.Tr>)}</Table.Tbody></Table></details>
      </Card>
      <Card withBorder padding="lg" mb="lg"><Title order={2} mb="md">What filled the basket?</Title>
        {cropTotals.length ? <div className="chart" aria-label="Harvest by crop chart">{chartsReady && <ResponsiveContainer width="100%" height={220} minWidth={0}><BarChart data={cropTotals.map((v) => ({ ...v, kg: v.grams / 1000 }))} layout="vertical" margin={{ left: 0, right: 30 }}><CartesianGrid strokeDasharray="3 3" horizontal={false} /><XAxis type="number" unit=" kg" tick={{ fontSize: 12 }} /><YAxis type="category" dataKey="crop" width={88} tick={{ fontSize: 12 }} /><Tooltip formatter={(v) => [`${v} kg`, 'Harvest']} /><Bar dataKey="kg" fill="#d8a14d" radius={[0, 5, 5, 0]} isAnimationActive={false} /></BarChart></ResponsiveContainer>}</div> : <Text c="dimmed">The crop comparison will appear after a harvest is recorded.</Text>}
        <details><summary>Read crop totals</summary><Table><Table.Thead><Table.Tr><Table.Th>Crop</Table.Th><Table.Th>Weight</Table.Th></Table.Tr></Table.Thead><Table.Tbody>{cropTotals.map((v) => <Table.Tr key={v.crop}><Table.Td>{v.crop}</Table.Td><Table.Td>{kilos(v.grams)} kg</Table.Td></Table.Tr>)}</Table.Tbody></Table></details>
      </Card>
    </Grid.Col><Grid.Col span={{ base: 12, lg: 4 }}><Card withBorder padding="lg" className="entry-card"><Text className="eyebrow">STRAIGHT FROM THE GARDEN</Text><Title order={2} mt="xs" mb="sm">Record a basket</Title><Text size="sm" c="dimmed" mb="lg">Choose your crop and bed, then add the weight in whole grams.</Text><HarvestEditor crops={crops} beds={beds} /><Text size="xs" c="dimmed" mt="md">Showing seed dates in September 2026. Change both the entry date and filters for your own season.</Text></Card></Grid.Col></Grid>
    <Card withBorder padding="lg"><Group justify="space-between" mb="md"><Title order={2}>The harvest log</Title><Text size="sm" c="dimmed">{summary.count > 200 ? 'Latest 200 entries · charts include all matches' : `${summary.count} entries in this view`}</Text></Group>
      {entries.length ? <Table.ScrollContainer minWidth={700}><Table striped highlightOnHover verticalSpacing="sm"><Table.Thead><Table.Tr><Table.Th>Date</Table.Th><Table.Th>Crop / bed</Table.Th><Table.Th>Weight</Table.Th><Table.Th>Notes</Table.Th><Table.Th>Actions</Table.Th></Table.Tr></Table.Thead><Table.Tbody>{entries.map((entry) => <HarvestRow key={entry.id} entry={entry} edit={setEditing} />)}</Table.Tbody></Table></Table.ScrollContainer> : <Text py="lg" c="dimmed">This page of the journal is empty. Try another date range or record your first harvest.</Text>}
    </Card><footer><Text size="sm" c="dimmed">Harvest journal · React Router, Mantine and Recharts · Stored in ClickHouse Managed Postgres</Text></footer>
    <Modal opened={Boolean(editing)} onClose={closeEditor} title="Edit harvest" centered>{editing && <HarvestEditor key={editing.id} crops={crops} beds={beds} entry={editing} onSaved={closeEditor} />}</Modal>
  </Container>;
}
