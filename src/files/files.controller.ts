import {
  Controller,
  Post,
  Get,
  Delete,
  Param,
  UseInterceptors,
  UploadedFile,
  UseGuards,
  Res,
  MaxFileSizeValidator,
  ParseFilePipe,
  Body,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { Response } from 'express';
import { FilesService } from './files.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { PrismaService } from '../prisma/prisma.service';
import 'multer';

@Controller('files')
export class FilesController {
  constructor(
    private readonly filesService: FilesService,
    private readonly prisma: PrismaService,
  ) {}

  @Post('upload')
  @UseGuards(JwtAuthGuard)
  @UseInterceptors(FileInterceptor('file'))
  async uploadFile(
    @UploadedFile(
      new ParseFilePipe({
        validators: [
          new MaxFileSizeValidator({ maxSize: 50 * 1024 * 1024 }), // 50MB
        ],
        fileIsRequired: true,
      }),
    )
    file: Express.Multer.File,
    @CurrentUser() currentUser: { id: number; role: string },
    @Body('userId') bodyUserId?: number,
  ) {
    // Определяем, для какого пользователя загружается файл
    let targetUserId: number;

    if (currentUser.role === 'ADMIN') {
      // ADMIN обязан указать userId получателя
      if (!bodyUserId) {
        throw new BadRequestException(
          'Для администратора необходимо указать userId получателя',
        );
      }
      targetUserId = Number(bodyUserId);
    } else {
      // USER — файл для себя
      targetUserId = currentUser.id;
    }

    // Получаем ФИО пользователя для построения папки
    const user = await this.prisma.user.findUnique({
      where: { id: targetUserId },
    });

    if (!user) {
      throw new NotFoundException('Пользователь не найден');
    }

    return this.filesService.uploadFile(file, targetUserId, user.fio);
  }

  /**
   * Wildcard-маршрут для поддержки ключей с вложенными путями.
   * Пример: /files/12_ivanov_ivan_ivanovich/uuid.jpg
   * Старые плоские ключи тоже работают: /files/uuid.jpg
   */
  @Get(':key(*)')
  async getFile(@Param('key') key: string, @Res() res: Response) {
    const buffer = await this.filesService.getFile(key);
    const ext = key.includes('.') ? key.split('.').pop()?.toLowerCase() : '';
    const mimeMap: Record<string, string> = {
      jpg: 'image/jpeg',
      jpeg: 'image/jpeg',
      png: 'image/png',
      gif: 'image/gif',
      webp: 'image/webp',
      bmp: 'image/bmp',
      heic: 'image/heic',
      mp4: 'video/mp4',
      mov: 'video/quicktime',
      mkv: 'video/x-matroska',
      webm: 'video/webm',
      avi: 'video/x-msvideo',
      mp3: 'audio/mpeg',
      wav: 'audio/wav',
      m4a: 'audio/mp4',
      aac: 'audio/aac',
      ogg: 'audio/ogg',
      flac: 'audio/flac',
      pdf: 'application/pdf',
      doc: 'application/msword',
      docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      xls: 'application/vnd.ms-excel',
      xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      zip: 'application/zip',
      rar: 'application/vnd.rar',
    };
    const mimeType = mimeMap[ext || ''] || 'application/octet-stream';
    res.set('Content-Type', mimeType);
    res.send(buffer);
  }

  @Delete(':key(*)')
  @UseGuards(JwtAuthGuard)
  async deleteFile(@Param('key') key: string) {
    await this.filesService.deleteFile(key);
    return { message: 'Файл удалён' };
  }
}
