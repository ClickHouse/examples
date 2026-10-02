import { database, type Product } from './database.js';
export const products: Product[] = [
  ['Trail flask', 'Insulated steel flask for hiking and camping', 'camping', 1800],
  ['Camp mug', 'Enamel camping mug with folding handle', 'camping', 1800],
  ['Compact stove', 'Lightweight camping stove for trail cooking', 'camping', 4500],
  ['Two person tent', 'Waterproof tent for weekend camping', 'camping', 12900],
  ['Merino hiking socks', 'Warm wool socks for hiking boots', 'clothing', 1800],
  ['Trail fleece', 'Breathable fleece for hiking in cool weather', 'clothing', 4500],
  ['Rain shell', 'Waterproof jacket with packable hood', 'clothing', 9900],
  ['Cycling gloves', 'Padded gloves for long cycle rides', 'cycling', 1800],
  ['Bike light set', 'Rechargeable front and rear cycling lights', 'cycling', 4500],
  ['Floor pump', 'Bicycle tyre pump with pressure gauge', 'cycling', 4500],
  ['Repair kit', 'Portable bicycle repair tools and patches', 'cycling', 1800],
  ['Retired lantern', 'Discontinued camping lantern', 'camping', 1500],
].map(([name, description, category, price], i) => ({
  id: `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`,
  sku: `OUT-${String(i + 1).padStart(3, '0')}`, name: String(name),
  description: String(description), category: String(category), price_pence: Number(price), active: i !== 11,
}));
const db = database();
try {
  if (process.env.PGUSER !== 'catalogue_migrator') throw new Error('Use catalogue_migrator to seed');
  await db.transaction().execute(async tx => {
    for (const product of products) await tx.insertInto('products').values(product)
      .onConflict(oc => oc.column('id').doUpdateSet(product)).execute();
  });
  console.log('Seeded 12 outdoor products (11 active), priced in GBP pence');
} finally { await db.destroy(); }
