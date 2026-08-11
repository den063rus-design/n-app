import { ApiProperty } from '@nestjs/swagger';
import { IsString, MinLength } from 'class-validator';

export class UpdateMessageDto {
  @ApiProperty({ example: 'Обновлённый текст сообщения' })
  @IsString()
  @MinLength(1)
  text!: string;
}
