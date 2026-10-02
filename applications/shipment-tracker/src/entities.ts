import { EntitySchema } from 'typeorm';

export type ShipmentStatus = 'created' | 'dispatched' | 'delivered' | 'cancelled';
export type ServiceLevel = 'standard' | 'express';
export interface Account { id: string; name: string }
export interface Shipment {
  id: string; accountId: string; serviceLevel: ServiceLevel;
  status: ShipmentStatus; revision: number;
  dispatchedAt: Date | null; createdAt: Date; updatedAt: Date;
}
export interface TransitionEvent {
  id: string; accountId: string; shipmentId: string; requestId: string;
  expectedRevision: number; revision: number;
  fromStatus: ShipmentStatus; toStatus: ShipmentStatus; serviceLevel: ServiceLevel;
  eventAt: Date; eventDay: string; dispatchedAt: Date | null; durationMs: string;
}
export const AccountSchema = new EntitySchema<Account>({
  name: 'Account', schema: 'shipments', tableName: 'accounts',
  columns: { id: { type: 'uuid', primary: true, name: 'account_id' }, name: { type: 'text' } },
});
export const ShipmentSchema = new EntitySchema<Shipment>({
  name: 'Shipment', schema: 'shipments', tableName: 'shipments',
  columns: {
    id: { type: 'uuid', primary: true, name: 'shipment_id' },
    accountId: { type: 'uuid', name: 'account_id' },
    serviceLevel: { type: 'text', name: 'service_level' },
    status: { type: 'text' }, revision: { type: 'integer' },
    dispatchedAt: { type: 'timestamptz', precision: 3, nullable: true, name: 'dispatched_at' },
    createdAt: { type: 'timestamptz', precision: 3, name: 'created_at' },
    updatedAt: { type: 'timestamptz', precision: 3, name: 'updated_at' },
  },
});
export const EventSchema = new EntitySchema<TransitionEvent>({
  name: 'TransitionEvent', schema: 'shipments', tableName: 'events',
  columns: {
    id: { type: 'uuid', primary: true, name: 'event_id' },
    accountId: { type: 'uuid', name: 'account_id' },
    shipmentId: { type: 'uuid', name: 'shipment_id' },
    requestId: { type: 'text', name: 'request_id' },
    expectedRevision: { type: 'integer', name: 'expected_revision' },
    revision: { type: 'integer' },
    fromStatus: { type: 'text', name: 'from_status' },
    toStatus: { type: 'text', name: 'to_status' },
    serviceLevel: { type: 'text', name: 'service_level' },
    eventAt: { type: 'timestamptz', precision: 3, name: 'event_at' },
    eventDay: { type: 'date', name: 'event_day' },
    dispatchedAt: { type: 'timestamptz', precision: 3, nullable: true, name: 'dispatched_at' },
    durationMs: { type: 'bigint', name: 'duration_ms' },
  },
});
