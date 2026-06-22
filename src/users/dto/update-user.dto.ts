import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsInt, IsOptional, IsString, Max, Min, MinLength } from 'class-validator';

export class UpdateUserDto {
  @ApiPropertyOptional({ example: 'Иван Петров' })
  @IsOptional()
  @IsString()
  @MinLength(2)
  fio?: string;

  @ApiPropertyOptional({ example: 'Иван Петров' })
  @IsOptional()
  @IsString()
  @MinLength(2)
  fullName?: string;

  @ApiPropertyOptional({ example: 25 })
  @IsOptional()
  age?: number | null;

  @ApiPropertyOptional({ example: 'ivan123' })
  @IsOptional()
  @IsString()
  @MinLength(3)
  login?: string;

  @ApiPropertyOptional({ example: 'Заметка о пользователе' })
  @IsOptional()
  @IsString()
  notes?: string;
}
