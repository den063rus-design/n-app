import { ApiProperty } from '@nestjs/swagger';
import { MessageStatus } from '@prisma/client';

export class MessageResponseDto {
  @ApiProperty()
  id!: number;

  @ApiProperty()
  senderId!: number;

  @ApiProperty()
  receiverId!: number;

  @ApiProperty()
  text!: string;

  @ApiProperty({ enum: MessageStatus })
  status!: MessageStatus;

  @ApiProperty()
  createdAt!: Date;
}
