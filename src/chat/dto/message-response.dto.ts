import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { MessageStatus, MessageType } from '@prisma/client';

class AttachmentDto {
  @ApiProperty()
  id!: number;

  @ApiProperty()
  url!: string;

  @ApiProperty()
  type!: string;

  @ApiProperty()
  fileName!: string;
}

export class MessageResponseDto {
  @ApiProperty()
  id!: number;

  @ApiProperty()
  senderId!: number;

  @ApiProperty()
  receiverId!: number;

  @ApiProperty()
  text!: string;

  @ApiProperty({ enum: MessageType })
  type!: MessageType;

  @ApiPropertyOptional()
  metadata?: Record<string, any>;

  @ApiProperty({ enum: MessageStatus })
  status!: MessageStatus;

  @ApiProperty()
  createdAt!: Date;

  @ApiPropertyOptional({ type: [AttachmentDto] })
  attachments?: AttachmentDto[];
}
