import { IsString, IsInt, MinLength, IsOptional, IsArray } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class CreateMessageDto {
  @ApiProperty({ example: 'Привет, администратор!' })
  @IsString()
  @MinLength(1)
  text!: string;

  @ApiProperty({ example: 1 })
  @IsInt()
  userId!: number;

  @ApiPropertyOptional({ example: ['uuid-file-key-1.jpg', 'uuid-file-key-2.pdf'] })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  fileKeys?: string[];
}
