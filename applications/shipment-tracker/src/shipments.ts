import { ConflictException, Injectable, NotFoundException, OnModuleInit } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { randomUUID } from 'node:crypto';
import { DataSource } from 'typeorm';
import { AccountGuard } from './auth.js';
import type { TransitionDto, ListDto, HistoryDto } from './dto.js';
import { AccountSchema, EventSchema, ShipmentSchema } from './entities.js';
import { assertTransition, deliveredDuration } from './domain.js';

@Injectable()
export class ShipmentsService implements OnModuleInit {
  constructor(@InjectDataSource() private readonly source: DataSource, private readonly guard: AccountGuard) {}
  async onModuleInit(): Promise<void> {
    for (const id of this.guard.scopes.accountIds) {
      if (!await this.source.getRepository(AccountSchema).existsBy({ id })) throw new Error('Configured account missing');
    }
  }
  async get(accountId: string, id: string) {
    const shipment = await this.source.getRepository(ShipmentSchema).findOneBy({ accountId, id });
    if (!shipment) throw new NotFoundException('Shipment not found');
    return shipment;
  }
  async list(accountId: string, input: ListDto) {
    const query = this.source.getRepository(ShipmentSchema).createQueryBuilder('shipment')
      .where('shipment.accountId = :accountId', { accountId })
      .orderBy('shipment.id', 'ASC').take(input.limit + 1);
    if (input.after) query.andWhere('shipment.id > :after', { after: input.after });
    const rows = await query.getMany();
    const items = rows.slice(0, input.limit);
    return { items, nextAfter: rows.length > input.limit ? items.at(-1)!.id : null, consistency: 'live' };
  }
  async history(accountId: string, id: string, input: HistoryDto) {
    await this.get(accountId, id);
    const rows = await this.source.getRepository(EventSchema).createQueryBuilder('event')
      .where('event.accountId = :accountId AND event.shipmentId = :id AND event.revision > :after', {
        accountId, id, after: input.afterRevision,
      }).orderBy('event.revision', 'ASC').take(input.limit + 1).getMany();
    const items = rows.slice(0, input.limit);
    return { items, nextRevision: rows.length > input.limit ? items.at(-1)!.revision : null };
  }
  async transition(accountId: string, id: string, input: TransitionDto) {
    // Every repository in this callback belongs to this transaction's manager.
    return this.source.transaction('READ COMMITTED', async manager => {
      await manager.getRepository(AccountSchema).createQueryBuilder('account')
        .where('account.id = :accountId', { accountId }).setLock('pessimistic_write').getOneOrFail();
      // Account lock also serializes same request IDs across different shipments.
      const retained = await manager.getRepository(EventSchema).findOneBy({ accountId, requestId: input.requestId });
      if (retained) {
        if (retained.shipmentId !== id || retained.expectedRevision !== input.expectedRevision ||
            retained.toStatus !== input.toStatus) throw new ConflictException('Request ID already has different data');
        return { created: false, event: retained };
      }
      const shipment = await manager.getRepository(ShipmentSchema).createQueryBuilder('shipment')
        .where('shipment.accountId = :accountId AND shipment.id = :id', { accountId, id })
        .setLock('pessimistic_write').getOne();
      if (!shipment) throw new NotFoundException('Shipment not found');
      if (shipment.revision !== input.expectedRevision) throw new ConflictException('Shipment revision changed; refetch before retrying');
      assertTransition(shipment.status, input.toStatus);
      const eventAt = new Date();
      const dispatchedAt = input.toStatus === 'dispatched' ? eventAt : shipment.dispatchedAt;
      const event = manager.getRepository(EventSchema).create({
        id: randomUUID(), accountId, shipmentId: id, requestId: input.requestId,
        expectedRevision: input.expectedRevision, revision: shipment.revision + 1,
        fromStatus: shipment.status, toStatus: input.toStatus, serviceLevel: shipment.serviceLevel,
        eventAt, eventDay: eventAt.toISOString().slice(0, 10), dispatchedAt,
        durationMs: input.toStatus === 'delivered' ? deliveredDuration(eventAt, dispatchedAt) : '0',
      });
      await manager.getRepository(ShipmentSchema).update({ accountId, id }, {
        status: input.toStatus, revision: event.revision, dispatchedAt, updatedAt: eventAt,
      });
      await manager.getRepository(EventSchema).insert(event);
      return { created: true, event };
    });
  }
}
