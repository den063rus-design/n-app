import {
  Injectable,
  InternalServerErrorException,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { DeleteObjectCommand, GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { promises as fs } from 'fs';
import * as path from 'path';
import { v4 as uuidv4 } from 'uuid';
import 'multer';

type StorageDriver = 'local' | 'minio';

@Injectable()
export class FilesService {
  private readonly logger = new Logger(FilesService.name);
  private readonly storageDriver: StorageDriver;
  private readonly uploadsDir: string;
  private readonly bucket: string;
  private readonly s3Client?: S3Client;

  constructor() {
    this.storageDriver = process.env.FILE_STORAGE_DRIVER === 'minio' ? 'minio' : 'local';
    this.uploadsDir = path.resolve(process.cwd(), 'uploads');
    this.bucket = process.env.MINIO_BUCKET || 'n-app-files';

    if (this.storageDriver === 'minio') {
      const minioEndpoint = process.env.MINIO_ENDPOINT;
      const minioPort = process.env.MINIO_PORT;
      const accessKey = process.env.MINIO_ACCESS_KEY;
      const secretKey = process.env.MINIO_SECRET_KEY;

      if (!minioEndpoint || !minioPort || !accessKey || !secretKey) {
        throw new Error(
          'MinIO configuration error: FILE_STORAGE_DRIVER=minio requires MINIO_ENDPOINT, MINIO_PORT, MINIO_ACCESS_KEY, and MINIO_SECRET_KEY to be set',
        );
      }

      const endpoint = this.buildBaseUrl(minioEndpoint, minioPort);

      this.s3Client = new S3Client({
        endpoint,
        region: 'us-east-1',
        credentials: {
          accessKeyId: accessKey,
          secretAccessKey: secretKey,
        },
        forcePathStyle: true,
      });
    }
  }

  /**
   * Загружает файл в папку пользователя.
   * @param file - файл из multipart
   * @param targetUserId - ID пользователя, которому принадлежит файл
   * @param fio - ФИО пользователя для построения slug-папки
   */
  async uploadFile(
    file: Express.Multer.File,
    targetUserId: number,
    fio: string,
  ): Promise<{
    url: string;
    key: string;
    mimeType: string;
    originalName: string;
    fileSize: number;
  }> {
    if (!file) {
      throw new InternalServerErrorException('Файл не был передан');
    }

    const ext = path.extname(file.originalname);
    const fileName = `${uuidv4()}${ext}`;
    const folderName = this.buildUserFolderName(targetUserId, fio);
    const key = `${folderName}/${fileName}`;

    try {
      if (this.storageDriver === 'minio' && this.s3Client) {
        await this.s3Client.send(
          new PutObjectCommand({
            Bucket: this.bucket,
            Key: key,
            Body: file.buffer,
            ContentType: file.mimetype,
            ContentLength: file.size,
          }),
        );
      } else {
        const userDir = path.join(this.uploadsDir, folderName);
        await fs.mkdir(userDir, { recursive: true });
        await fs.writeFile(path.join(userDir, fileName), file.buffer);
      }

      const url = this.getFileUrl(key);
      this.logger.log(`File uploaded: ${key} (${this.storageDriver})`);
      return {
        url,
        key,
        mimeType: file.mimetype,
        originalName: file.originalname,
        fileSize: file.size,
      };
    } catch (error) {
      this.logger.error(`Failed to upload file: ${(error as Error).message}`);
      throw new InternalServerErrorException('Не удалось загрузить файл');
    }
  }

  async getFile(key: string): Promise<Buffer> {
    try {
      if (this.storageDriver === 'minio' && this.s3Client) {
        const response = await this.s3Client.send(
          new GetObjectCommand({
            Bucket: this.bucket,
            Key: key,
          }),
        );

        const chunks: Uint8Array[] = [];
        for await (const chunk of response.Body as AsyncIterable<Uint8Array>) {
          chunks.push(chunk);
        }
        return Buffer.concat(chunks);
      }

      return await fs.readFile(path.join(this.uploadsDir, key));
    } catch (error) {
      this.logger.error(`Failed to get file: ${(error as Error).message}`);
      throw new NotFoundException('Файл не найден');
    }
  }

  /**
   * Удаляет физический файл. Если файла нет на диске — только лог, без ошибки.
   */
  async deleteFile(key: string): Promise<void> {
    try {
      if (this.storageDriver === 'minio' && this.s3Client) {
        await this.s3Client.send(
          new DeleteObjectCommand({
            Bucket: this.bucket,
            Key: key,
          }),
        );
      } else {
        const filePath = path.join(this.uploadsDir, key);
        try {
          await fs.rm(filePath, { force: true });
        } catch (err) {
          // Если файл уже отсутствует — не валим запрос, только лог
          this.logger.warn(`File not found on disk, skipping delete: ${key}`);
          return;
        }
      }

      this.logger.log(`File deleted: ${key}`);
    } catch (error) {
      this.logger.error(`Failed to delete file: ${(error as Error).message}`);
      // Не кидаем исключение — удаление файла не должно ломать удаление сообщения
    }
  }

  getFileUrl(key: string): string {
    return `/files/${key}`;
  }

  /**
   * Строит имя папки пользователя по схеме: {userId}_{slug}
   * Пример: 12_ivanov_ivan_ivanovich
   */
  buildUserFolderName(userId: number, fio: string): string {
    const slug = this.transliterateAndSlugify(fio);
    return `${userId}_${slug}`;
  }

  /**
   * Транслитерирует ФИО в латиницу, приводит к lowercase,
   * заменяет пробелы на _, убирает спецсимволы, ограничивает длину.
   */
  private transliterateAndSlugify(input: string): string {
    const map: Record<string, string> = {
      а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'e',
      ж: 'zh', з: 'z', и: 'i', й: 'i', к: 'k', л: 'l', м: 'm',
      н: 'n', о: 'o', п: 'p', р: 'r', с: 's', т: 't', у: 'u',
      ф: 'f', х: 'kh', ц: 'ts', ч: 'ch', ш: 'sh', щ: 'shch',
      ъ: '', ы: 'y', ь: '', э: 'e', ю: 'iu', я: 'ia',
      А: 'A', Б: 'B', В: 'V', Г: 'G', Д: 'D', Е: 'E', Ё: 'E',
      Ж: 'Zh', З: 'Z', И: 'I', Й: 'I', К: 'K', Л: 'L', М: 'M',
      Н: 'N', О: 'O', П: 'P', Р: 'R', С: 'S', Т: 'T', У: 'U',
      Ф: 'F', Х: 'Kh', Ц: 'Ts', Ч: 'Ch', Ш: 'Sh', Щ: 'Shch',
      Ъ: '', Ы: 'Y', Ь: '', Э: 'E', Ю: 'Iu', Я: 'Ia',
    };

    // Транслитерация
    let result = '';
    for (const char of input) {
      result += map[char] ?? char;
    }

    // Приводим к lowercase
    result = result.toLowerCase();

    // Заменяем пробелы и подчёркивания на _
    result = result.replace(/[\s_]+/g, '_');

    // Удаляем всё, кроме букв, цифр, _, -
    result = result.replace(/[^a-z0-9_-]/g, '');

    // Удаляем ведущие/ trailing _ и -
    result = result.replace(/^[-_]+|[-_]+$/g, '');

    // Ограничиваем длину slug до 50 символов
    if (result.length > 50) {
      result = result.substring(0, 50);
      // Обрезаем по последнему целому слову (по _)
      const lastUnderscore = result.lastIndexOf('_');
      if (lastUnderscore > 0) {
        result = result.substring(0, lastUnderscore);
      }
    }

    // Fallback, если строка пустая
    if (!result) {
      result = 'user';
    }

    return result;
  }

  private buildBaseUrl(endpoint: string, port: string): string {
    const normalizedEndpoint = endpoint.replace(/\/+$/, '');

    try {
      const url = new URL(normalizedEndpoint);
      if (!url.port) {
        url.port = port;
      }
      return `${url.protocol}//${url.hostname}:${url.port}`;
    } catch {
      if (/:\d+$/.test(normalizedEndpoint)) {
        return normalizedEndpoint;
      }

      return `${normalizedEndpoint}:${port}`;
    }
  }
}
