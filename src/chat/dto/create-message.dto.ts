import { Type } from 'class-transformer';
import { IsString, IsInt, MinLength, IsOptional, IsArray, ValidateIf, ValidateNested, IsNumber, Min } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

class FileAttachmentDto {
  @ApiProperty({ example: 'uuid-file-key-1.jpg' })
  @IsString()
  key!: string;

  @ApiProperty({ example: 'photo.jpg' })
  @IsString()
  originalName!: string;

  @ApiProperty({ example: 102400 })
  @IsNumber()
  @Min(0)
  fileSize!: number;

  @ApiProperty({ example: 'image/jpeg' })
  @IsString()
  mimeType!: string;
}

export class CreateMessageDto {
  @ApiProperty({ example: 'Привет, администратор!' })
  @IsString()
  @ValidateIf((o) => !o.files || o.files.length === 0)
  @MinLength(1)
  text!: string;

  @ApiPropertyOptional({ example: 1 })
  @IsOptional()
  @IsInt()
  userId?: number;

  @ApiPropertyOptional({
    type: [FileAttachmentDto],
    description: 'Список загруженных файлов с метаданными',
  })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => FileAttachmentDto)
  files?: FileAttachmentDto[];

  /** @deprecated Используйте `files` вместо `fileKeys` */
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  fileKeys?: string[];
}
