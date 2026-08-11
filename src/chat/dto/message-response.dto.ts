import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { MessageStatus } from '@prisma/client';

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

  @ApiProperty({ enum: MessageStatus })
  status!: MessageStatus;

  @ApiProperty()
  createdAt!: Date;

  @ApiPropertyOptional({ type: [AttachmentDto] })
  attachments?: AttachmentDto[];
}
