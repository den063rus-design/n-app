import { IsString, IsInt, MinLength } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class CreateMessageDto {
  @ApiProperty({ example: 'Привет, администратор!' })
  @IsString()
  @MinLength(1)
  text!: string;

  @ApiProperty({ example: 1 })
  @IsInt()
  userId!: number;
}