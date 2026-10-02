import {
  Body, Controller, Get, Module, Param, ParseUUIDPipe, Post, Query, Req, Res, UseGuards,
} from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import type { Response } from 'express';
import { AccountGuard, type AccountRequest } from './auth.js';
import { dbOptions } from './config.js';
import { TransitionDto, ListDto, HistoryDto, ReportDto } from './dto.js';
import { ShipmentsService } from './shipments.js';
import { ReportsService } from './reports.js';

@Controller()
@UseGuards(AccountGuard)
export class ShipmentController {
  constructor(private readonly shipments: ShipmentsService, private readonly reports: ReportsService) {}
  @Get('shipments')
  list(@Req() request: AccountRequest, @Query() input: ListDto) {
    return this.shipments.list(request.accountId, input);
  }
  @Get('shipments/:id')
  get(@Req() request: AccountRequest, @Param('id', new ParseUUIDPipe({ version: '4' })) id: string) {
    return this.shipments.get(request.accountId, id.toLowerCase());
  }
  @Get('shipments/:id/events')
  history(@Req() request: AccountRequest, @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
          @Query() input: HistoryDto) {
    return this.shipments.history(request.accountId, id.toLowerCase(), input);
  }
  @Post('shipments/:id/transitions')
  async transition(@Req() request: AccountRequest,
                   @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
                   @Body() input: TransitionDto, @Res({ passthrough: true }) response: Response) {
    const { created, event } = await this.shipments.transition(request.accountId, id.toLowerCase(), input);
    response.status(created ? 201 : 200);
    return event;
  }
  @Get('reports')
  report(@Req() request: AccountRequest, @Query() input: ReportDto) {
    return this.reports.report(request.accountId, input);
  }
}
@Module({
  imports: [TypeOrmModule.forRootAsync({ useFactory: () => ({ ...dbOptions(), retryAttempts: 1 }) })],
  controllers: [ShipmentController], providers: [AccountGuard, ShipmentsService, ReportsService],
})
export class AppModule {}
