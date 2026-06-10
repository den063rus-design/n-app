import { IsOptional, IsString, IsEnum } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { UserStatus } from '@prisma/client';

export class QueryUsersDto {
  @ApiPropertyOptional({ description: 'Поиск по ФИО (частичный, без учета регистра)' })
  @IsOptional()
  @IsString()
  search?: string;

  @ApiPropertyOptional({ enum: ['name', 'age', 'created'], description: 'Поле для сортировки' })
  @IsOptional()
  @IsString()
  sort?: 'name' | 'age' | 'created';

  @ApiPropertyOptional({ enum: ['asc', 'desc'], description: 'Направление сортировки' })
  @IsOptional()
  @IsString()
  order?: 'asc' | 'desc';

  @ApiPropertyOptional({ enum: UserStatus, description: 'Фильтр по статусу' })
  @IsOptional()
  @IsEnum(UserStatus)
  status?: UserStatus;
}
