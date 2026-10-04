import { cp, mkdir } from 'node:fs/promises'
await mkdir('api/build/public', { recursive: true })
await cp('ui/dist/asset-audit/browser', 'api/build/public', { recursive: true })
