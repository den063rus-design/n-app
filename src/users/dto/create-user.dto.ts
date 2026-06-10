import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Role } from '@prisma/client';
import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsOptional, IsString, Min, MinLength } from 'class-validator';

export class CreateUserDto {
  @ApiProperty({ example: 'Иван Иванов' })
  @IsString()
  @MinLength(2)
  fio!: string;

  @ApiPropertyOptional({ example: 28 })
  @Type(() => Number)
  @IsOptional()
  @IsInt()
  @Min(1)
  age?: number;

  @ApiProperty({ example: 'ivan.ivanov' })
  @IsString()
  @MinLength(3)
  login!: string;

  @ApiProperty({ example: 'password123' })
  @IsString()
  @MinLength(6)
  password!: string;

  @ApiPropertyOptional({ enum: Role, example: Role.USER })
  @IsOptional()
  @IsEnum(Role)
  role?: Role;

  @ApiPropertyOptional({ example: 'Заметка о пользователе' })
  @IsOptional()
  @IsString()
  notes?: string;
}
