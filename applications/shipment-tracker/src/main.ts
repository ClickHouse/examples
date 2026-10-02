import 'reflect-metadata';
import { ArgumentsHost, Catch, ExceptionFilter, HttpException, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import type { Response } from 'express';
import { AppModule } from './app.js';

@Catch()
class PublicErrors implements ExceptionFilter {
  catch(error: unknown, host: ArgumentsHost): void {
    const parser = error as { status?: number; type?: string };
    const status = error instanceof HttpException ? error.getStatus() :
      parser?.status === 413 ? 413 :
      parser?.status === 400 && parser.type === 'entity.parse.failed' ? 400 : 503;
    const message = status === 503 ? 'Service unavailable; shipment state is authoritative in Postgres' :
      status === 413 ? 'Request body exceeds 4 KiB' :
      error instanceof HttpException ? error.message : 'Invalid request';
    host.switchToHttp().getResponse<Response>().status(status).json({ error: message });
  }
}
async function main(): Promise<void> {
  const port = Number(process.env.PORT ?? 3000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid port');
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { logger: false, abortOnError: false });
  app.useBodyParser('json', { limit: '4kb' });
  app.useGlobalPipes(new ValidationPipe({
    transform: true, whitelist: true, forbidNonWhitelisted: true,
    validationError: { target: false, value: false },
  }));
  app.useGlobalFilters(new PublicErrors());
  app.enableShutdownHooks();
  await app.listen(port, '127.0.0.1');
  console.log('Shipment API ready on loopback');
}
main().catch(() => { console.error('Shipment API startup failed; check configuration, TLS, roles and database'); process.exitCode = 1; });
