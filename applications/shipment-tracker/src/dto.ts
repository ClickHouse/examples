import { Transform } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, Max, Min } from 'class-validator';

export class TransitionDto {
  @IsString() @Matches(/^[A-Za-z0-9._-]{1,64}$(?![\s\S])/u)
  requestId!: string;
  @IsInt() @Min(0) @Max(9_999)
  expectedRevision!: number;
  @IsIn(['dispatched', 'delivered', 'cancelled'])
  toStatus!: 'dispatched' | 'delivered' | 'cancelled';
}
export class ListDto {
  @IsOptional() @IsUUID('4') after?: string;
  @Transform(({ value }) => typeof value === 'string' && /^\d+$/.test(value) ? Number(value) : value)
  @IsInt() @Min(1) @Max(50)
  limit = 20;
}
export class HistoryDto {
  @Transform(({ value }) => typeof value === 'string' && /^\d+$/.test(value) ? Number(value) : value)
  @IsInt() @Min(0) @Max(10_000)
  afterRevision = 0;
  @Transform(({ value }) => typeof value === 'string' && /^\d+$/.test(value) ? Number(value) : value)
  @IsInt() @Min(1) @Max(50)
  limit = 20;
}
export class ReportDto {
  @IsOptional() @IsString() @Matches(/^\d{4}-\d{2}-\d{2}$/) from?: string;
  @IsOptional() @IsString() @Matches(/^\d{4}-\d{2}-\d{2}$/) to?: string;
}
