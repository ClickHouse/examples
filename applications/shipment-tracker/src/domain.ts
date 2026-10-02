import { BadRequestException, ConflictException, ServiceUnavailableException } from '@nestjs/common';
import type { ShipmentStatus } from './entities.js';

export function assertTransition(from: ShipmentStatus, to: ShipmentStatus): void {
  if (!((from === 'created' && (to === 'dispatched' || to === 'cancelled')) ||
        (from === 'dispatched' && (to === 'delivered' || to === 'cancelled')))) {
    throw new ConflictException('Transition is not allowed from the current state');
  }
}
export function deliveredDuration(eventAt: Date, dispatchedAt: Date | null): string {
  if (!dispatchedAt) throw new ServiceUnavailableException('Missing dispatch fact');
  const duration = eventAt.getTime() - dispatchedAt.getTime();
  if (!Number.isSafeInteger(duration) || duration < 0) {
    throw new ServiceUnavailableException('Server clock precedes dispatch');
  }
  return String(duration);
}
export function reportRange(from?: string, to?: string, now = new Date()): [string, string] {
  const today = now.toISOString().slice(0, 10);
  const earliest = new Date(Date.parse(today) - 30 * 86_400_000).toISOString().slice(0, 10);
  const start = from ?? new Date(Date.parse(today) - 6 * 86_400_000).toISOString().slice(0, 10);
  const end = to ?? today;
  for (const day of [start, end]) {
    const parsed = new Date(day);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !Number.isFinite(parsed.getTime()) ||
        parsed.toISOString().slice(0, 10) !== day) throw new BadRequestException('Invalid report date');
  }
  if (start > end || start < earliest || end > today) {
    throw new BadRequestException('Reports cover at most the last 31 UTC days');
  }
  return [start, end];
}
