import { IsOptional, IsString, IsEnum } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';

export class QueryUsersDto {
  @ApiPropertyOptional({ description: 'Поиск по fullName (частичный, без учета регистра)' })
  @IsOptional()
  @IsString()
  search?: string;

  @ApiPropertyOptional({ enum: ['fullName', 'age', 'createdAt'], description: 'Поле для сортировки' })
  @IsOptional()
  @IsString()
  sortBy?: 'fullName' | 'age' | 'createdAt';

  @ApiPropertyOptional({ enum: ['asc', 'desc'], description: 'Направление сортировки' })
  @IsOptional()
  @IsString()
  sortOrder?: 'asc' | 'desc';

  @ApiPropertyOptional({ enum: ['ACTIVE', 'BLOCKED'], description: 'Фильтр по статусу' })
  @IsOptional()
  @IsString()
  status?: 'ACTIVE' | 'BLOCKED';
}
